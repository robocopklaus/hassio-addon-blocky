# How the Supervisor consumes an add-on's `watchdog` field

Primary-source research into what the Home Assistant Supervisor actually *does* with the `watchdog`
URL an add-on declares in its manifest — what it polls, how often, what counts as a failure, what it
does when the check fails, and whether editing that field in `blocky/config.yaml` reaches installs
that already exist.

Written to settle [#314](https://github.com/robocopklaus/hassio-addon-blocky/issues/314), which asked
for independent verification of the behavioural claim [PR #317](https://github.com/robocopklaus/hassio-addon-blocky/pull/317)
and [ADR-0012](https://github.com/robocopklaus/hassio-addon-blocky/blob/worktree-issue-310-upstream-probe/docs/adr/0012-upstream-reachability-is-observed-not-enforced.md)
(unmerged, on #317's branch) rest on: **a failing
watchdog makes the Supervisor restart the add-on.** That claim is why #317 rejects both repointing
the watchdog and serving a health endpoint of our own, in favour of a probe that only writes to the
log. It is the companion to [#313](https://github.com/robocopklaus/hassio-addon-blocky/issues/313),
which established that Blocky exposes no truthful upstream-health signal to point a watchdog at
(`blocky-upstream-health-signals.md`).

Everything below is read from the Supervisor's source, not from documentation prose. The official
documentation is quoted once, in §6, precisely because it is silent on the question asked.

## Sources and how to read the links

All Supervisor links are permalinks to tag
[`2026.07.5`](https://github.com/home-assistant/supervisor/tree/d8c87c4f2a1814b60688384f1c071e464947bbd0)
(commit `d8c87c4`, 2026-07-28) — the current stable Supervisor release at the time of writing. There
is no pinning relationship here: unlike `BLOCKY_VERSION`, the Supervisor version is chosen by the
operator's system, so this describes what a reasonably current install does, not a version this
repository controls.

**Note on the rename.** This Supervisor generation calls add-ons "apps" internally: the code lives in
`supervisor/apps/`, the model class is `App`, and the state enum is `AppState`. The externally
visible manifest key is still `watchdog`, the API path is still `/addons/<slug>`, and the logic is
the direct descendant of what used to sit in `supervisor/addons/`. A reader grepping for `addons/`
in a current checkout will find nothing; that is the rename, not a removal.

Add-on links are to this repository at the time of writing.

---

## 0. The answer, in one paragraph

**Claim A is confirmed, and the situation is worse than #317 argues.** A failing watchdog does not
merely flag the add-on as unhealthy in the UI — there is no such flag anywhere in the code path. The
Supervisor polls the URL every **120 seconds** with a **10-second** timeout, and on the **second**
recorded failure it calls `app.restart()`. Worse, the failure counter is **never cleared by a
successful poll** (§2.2): one isolated miss arms the counter permanently, so the *next* miss — an
hour or a week later — restarts the add-on immediately. For a DNS server on a transient upstream
outage that is exactly the restart-loop outcome #317 set out to avoid, and it needs only two
scattered failures rather than two consecutive ones. **The mechanism choice in #317 stands, on
stronger grounds than it claims.** Separately: the field is read from a **snapshot of the manifest
taken at install/update time**, so changing `watchdog:` reaches an existing install on that install's
next add-on **update** — not at container start, not at Supervisor restart (§3); and the whole
mechanism is gated behind a per-install toggle that defaults to **off** (§4).

---

## 1. Where the poll comes from

Registered as a periodic scheduler task at
[`tasks.py:96-98`](https://github.com/home-assistant/supervisor/blob/d8c87c4f2a1814b60688384f1c071e464947bbd0/supervisor/misc/tasks.py#L96-L98),
with the interval at
[`tasks.py:50`](https://github.com/home-assistant/supervisor/blob/d8c87c4f2a1814b60688384f1c071e464947bbd0/supervisor/misc/tasks.py#L50):

```python
RUN_WATCHDOG_APP_APPLICATION = 120
```

There is one loop for every installed add-on, not a timer per add-on
([`_watchdog_app_application`, tasks.py:333-361](https://github.com/home-assistant/supervisor/blob/d8c87c4f2a1814b60688384f1c071e464947bbd0/supervisor/misc/tasks.py#L333-L361)).
An add-on is polled only when **all** of these hold:

| Gate | Source | For this add-on |
|---|---|---|
| `app.watchdog` — the per-install toggle is on | [`app.py:505-507`](https://github.com/home-assistant/supervisor/blob/d8c87c4f2a1814b60688384f1c071e464947bbd0/supervisor/apps/app.py#L505-L507) | **Off by default** — see §4 |
| `app.state == AppState.STARTED` | [`tasks.py:337`](https://github.com/home-assistant/supervisor/blob/d8c87c4f2a1814b60688384f1c071e464947bbd0/supervisor/misc/tasks.py#L337) | Gated behind our Docker `HEALTHCHECK` — see §5 |
| `not app.in_progress` — no start/stop/update running | [`tasks.py:344`](https://github.com/home-assistant/supervisor/blob/d8c87c4f2a1814b60688384f1c071e464947bbd0/supervisor/misc/tasks.py#L344) | — |
| the manifest declares a parseable `watchdog` URL | [`app.py:825-826`](https://github.com/home-assistant/supervisor/blob/d8c87c4f2a1814b60688384f1c071e464947bbd0/supervisor/apps/app.py#L825-L826) | Yes, `config.yaml:10` |

If the URL is absent or does not match the runtime regex, `watchdog_application()` returns **`True`**
— i.e. *healthy*. Failing to declare a watchdog is silence, not a failure.

## 2. What happens when the poll fails

### 2.1 The check itself

[`Addon.watchdog_application`, app.py:823-863](https://github.com/home-assistant/supervisor/blob/d8c87c4f2a1814b60688384f1c071e464947bbd0/supervisor/apps/app.py#L823-L863):

```python
async with self.sys_websession.get(url, timeout=WATCHDOG_TIMEOUT, ssl=False) as req:
    if req.status < 300:
        return True
```

- **Timeout**: `WATCHDOG_TIMEOUT = aiohttp.ClientTimeout(total=10)`
  ([`app.py:127`](https://github.com/home-assistant/supervisor/blob/d8c87c4f2a1814b60688384f1c071e464947bbd0/supervisor/apps/app.py#L127)) — ten seconds for the whole request.
- **Pass condition**: `req.status < 300`. `aiohttp` follows redirects by default, so in practice this
  means the final response is 2xx. Every 4xx and 5xx is a failure, as is a timeout or any
  `aiohttp.ClientError` (connection refused, DNS failure, reset).
- **TLS is not verified** (`ssl=False`), so an `https://` watchdog against a self-signed certificate
  still passes.
- **The status code is what is read.** The response body is never touched. This settles the open
  question left at the end of #313's write-up: a hypothetical endpoint that reported upstream death
  *in its body* while returning 200 would be invisible to the watchdog. Only the status code counts.
- **`tcp://` mode short-circuits all of this**: it is a bare TCP connect with a **0.5-second**
  timeout ([`check_port`, utils/__init__.py:44-56](https://github.com/home-assistant/supervisor/blob/d8c87c4f2a1814b60688384f1c071e464947bbd0/supervisor/utils/__init__.py#L44-L56)),
  and any path suffix in the URL is ignored.

### 2.2 The counter, and the sticky-failure trap

[`tasks.py:333-361`](https://github.com/home-assistant/supervisor/blob/d8c87c4f2a1814b60688384f1c071e464947bbd0/supervisor/misc/tasks.py#L333-L361), reduced to its control flow:

```python
retry_scan = self._cache.get(app.slug, 0)

if app.in_progress or await app.watchdog_application():
    continue                      # <-- success does NOT reset self._cache[app.slug]

retry_scan += 1
if retry_scan == 1:
    self._cache[app.slug] = retry_scan
    _LOGGER.warning("Watchdog missing application response from %s", app.slug)
    return                        # <-- returns, does not continue

_LOGGER.warning("Watchdog found a problem with %s application!", app.slug)
try:
    await (await app.restart())
...
finally:
    self._cache[app.slug] = 0
```

Three things follow, and the second is the one that matters most for this add-on:

1. **Two failures, not one.** The first miss only logs a warning and arms the counter. The second
   restarts. With a 120 s interval and a 10 s timeout, the earliest restart is roughly **two to four
   minutes** after the endpoint starts failing.
2. **A success never disarms the counter.** The success path is `continue` — it does not write
   `self._cache[app.slug] = 0`. The counter is cleared only in the `finally` after a restart attempt,
   or when the Supervisor process restarts (the cache is a plain in-memory `dict`,
   [`tasks.py:69`](https://github.com/home-assistant/supervisor/blob/d8c87c4f2a1814b60688384f1c071e464947bbd0/supervisor/misc/tasks.py#L69)).
   **So the two failures need not be consecutive.** One dropped poll during a two-second network
   hiccup arms the add-on for the remaining uptime of the Supervisor; the next unrelated miss, at any
   later date, restarts it with no second chance.
3. **A miss aborts the sweep.** The first-failure branch `return`s out of the whole task rather than
   `continue`ing, so every add-on later in `sys_apps.installed` is skipped for that cycle. One flaky
   add-on delays the watchdog for the others.

**There is no "unhealthy" state.** Grepping the watchdog path for any issue, repair, or state flag
turns up nothing: the outcomes are a log warning and `app.restart()`. The premise the ticket offered
as the alternative — "the Supervisor merely flags the add-on as unhealthy in the UI" — does not exist
in this code.

### 2.3 The second, separate lever: container-state restarts

The same `watchdog` toggle also arms a Docker-event-driven restart, independent of the HTTP poll
([`watchdog_container`, app.py:1844-1858](https://github.com/home-assistant/supervisor/blob/d8c87c4f2a1814b60688384f1c071e464947bbd0/supervisor/apps/app.py#L1844-L1858)):
on a container transition to `FAILED`, `STOPPED`, or `UNHEALTHY` it calls
[`_restart_after_problem`](https://github.com/home-assistant/supervisor/blob/d8c87c4f2a1814b60688384f1c071e464947bbd0/supervisor/apps/app.py#L1758-L1820),
which retries up to `WATCHDOG_MAX_ATTEMPTS = 5` times with exponential backoff from
`WATCHDOG_RETRY_SECONDS = 10`, rate-limited to 10 calls per 30 minutes
([`apps/const.py:41-44`](https://github.com/home-assistant/supervisor/blob/d8c87c4f2a1814b60688384f1c071e464947bbd0/supervisor/apps/const.py#L41-L44)).

This matters here because **this add-on ships its own Docker `HEALTHCHECK`**
(`blocky/Dockerfile:100-101`):

```dockerfile
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD blocky blocking status || exit 1
```

Three consecutive failures at 30 s → Docker marks the container `UNHEALTHY` → with the toggle on, the
Supervisor restarts the add-on. So there are *two* Supervisor-driven restart paths, and both are
armed by the same switch. Neither is upstream-aware: `blocky blocking status` reads the same
`/api/blocking/status` that #313 showed has exactly one 200 return path. Consistent with #313 — no
part of this reopens the mechanism choice.

## 3. Where the field is read from — and whether edits reach existing installs

`watchdog_url` reads `self.data`
([`model.py:307-309`](https://github.com/home-assistant/supervisor/blob/d8c87c4f2a1814b60688384f1c071e464947bbd0/supervisor/apps/model.py#L307-L309)),
and for an installed add-on `data` is **not** the store copy
([`app.py:370-377`](https://github.com/home-assistant/supervisor/blob/d8c87c4f2a1814b60688384f1c071e464947bbd0/supervisor/apps/app.py#L370-L377)):

```python
@property
def data(self) -> Data:
    """Return app data/config."""
    return self.sys_apps.data.system[self.slug]     # local snapshot

@property
def data_store(self) -> Data:
    """Return app data from store."""
    return self.sys_store.data.apps.get(self.slug, self.data)   # live store — not used here
```

Across the entire Supervisor there are exactly **three** writers of `data.system[slug]`
([`apps/data.py:41-69`](https://github.com/home-assistant/supervisor/blob/d8c87c4f2a1814b60688384f1c071e464947bbd0/supervisor/apps/data.py#L41-L69)):

```python
async def install(self, app):  self.system[app.slug] = deepcopy(app.data)   # install
async def update(self, app):   self.system[app.slug] = deepcopy(app.data)   # update
async def restore(self, ...):  self.system[slug]     = deepcopy(system)     # backup restore
```

**So: yes, changing `watchdog:` reaches installs that already exist — on their next add-on update.**
Not on container start, not on Supervisor restart, and not when the store refreshes its copy of the
repository. The manifest is a snapshot, replaced wholesale each time the operator updates the add-on.

**This is the source-level basis for the ADR-0011 scope clarification.** The same `update` call that
replaces the manifest snapshot deliberately leaves the operator's option values alone:

```python
self.user[app.slug].update({ATTR_VERSION: app.version, ATTR_IMAGE: app.image})
```

Option values live in `user[slug][ATTR_OPTIONS]` and survive every update untouched — that is exactly
the pinning ADR-0011 describes. Manifest fields live in `system[slug]` and are *replaced* on every
update. `watchdog` sits at `blocky/config.yaml:10`, above `options:`, so it is a manifest field:
**not operator-owned, not subject to default pinning, and reaching every existing install one update
after we change it.** Confirmed from source.

## 4. The operator's toggle, and its default

`app.watchdog` reads `self.persist[ATTR_WATCHDOG]`
([`app.py:505-518`](https://github.com/home-assistant/supervisor/blob/d8c87c4f2a1814b60688384f1c071e464947bbd0/supervisor/apps/app.py#L505-L518)),
where `persist` is `sys_apps.data.user[slug]`. The user schema defaults it to **false**
([`apps/validate.py:624`](https://github.com/home-assistant/supervisor/blob/d8c87c4f2a1814b60688384f1c071e464947bbd0/supervisor/apps/validate.py#L624)):

```python
vol.Optional(ATTR_WATCHDOG, default=False): vol.Boolean(),
```

`data.install` writes a user record containing only `options`, `version`, and `image`, and
`save_data` re-validates the whole file through the schema before writing
([`utils/common.py:115-135`](https://github.com/home-assistant/supervisor/blob/d8c87c4f2a1814b60688384f1c071e464947bbd0/supervisor/utils/common.py#L115-L135)),
so the `False` default lands on disk at install time. The frontend only ever writes the key in
response to an explicit toggle
([`supervisor-app-info.ts`, `_watchdogToggled`](https://github.com/home-assistant/frontend/blob/dev/src/panels/config/apps/app-view/info/supervisor-app-info.ts)),
rendering the switch from `this._currentAddon.watchdog || false`.

**So on a fresh install the watchdog is off, and nothing in the add-on's manifest can turn it on.**
Consequences worth stating plainly:

- Our shipped `watchdog:` URL does nothing at all for an operator who never found the toggle. Both
  restart levers in §2 are dark for them.
- Conversely, for an operator who *did* enable it, the sticky-failure behaviour in §2.2 is live
  today.
- The toggle survives add-on updates (`data.update` touches only `version` and `image`), so an
  operator's choice is not reset by shipping a new version.
- The setter refuses to enable the watchdog for `startup: once` add-ons
  ([`app.py:512-516`](https://github.com/home-assistant/supervisor/blob/d8c87c4f2a1814b60688384f1c071e464947bbd0/supervisor/apps/app.py#L512-L516)).
  This add-on is `startup: system`, so that exemption does not apply.
- Home Assistant Core's own watchdog defaults to `True`
  ([`homeassistant/validate.py:36`](https://github.com/home-assistant/supervisor/blob/d8c87c4f2a1814b60688384f1c071e464947bbd0/supervisor/homeassistant/validate.py#L36)).
  The opposite default for add-ons is deliberate, not an oversight.

## 5. Placeholder substitution, and what the URL may contain

Two separate patterns constrain the value — one at manifest-validation time, one at poll time.

**Manifest schema** ([`apps/validate.py:472-474`](https://github.com/home-assistant/supervisor/blob/d8c87c4f2a1814b60688384f1c071e464947bbd0/supervisor/apps/validate.py#L472-L474)):

```python
vol.Optional(ATTR_WATCHDOG): vol.Match(
    r"^(?:https?|\[PROTO:\w+\]|tcp):\/\/\[HOST\]:(\[PORT:\d+\]|\d+).*$"
),
```

**Runtime** ([`RE_WATCHDOG`, app.py:122-125](https://github.com/home-assistant/supervisor/blob/d8c87c4f2a1814b60688384f1c071e464947bbd0/supervisor/apps/app.py#L122-L125)):

```python
RE_WATCHDOG = re.compile(
    r"^(?:(?P<s_prefix>https?|tcp)|\[PROTO:(?P<t_proto>\w+)\])"
    r":\/\/\[HOST\]:(?:\[PORT:)?(?P<t_port>\d+)\]?(?P<s_suffix>.*)$"
)
```

- **Schemes are exactly four**: `http`, `https`, `tcp`, and `[PROTO:<option>]`. Nothing else passes
  the manifest schema, so **no non-HTTP scheme other than `tcp` is supported at all** — there is no
  DNS, exec, or script probe. A `dns://` watchdog is not expressible.
- **`[PROTO:<option>]`** resolves against the add-on's *merged options*: `https` if
  `self.options.get(<option>)` is truthy, otherwise `http`
  ([`app.py:846-849`](https://github.com/home-assistant/supervisor/blob/d8c87c4f2a1814b60688384f1c071e464947bbd0/supervisor/apps/app.py#L846-L849)).
  It is the one place an operator-owned option value feeds the watchdog.
- **`[HOST]` is never substituted from the string.** It is a literal token the regex *requires*; the
  address actually dialled is `self.ip_address` — the container's IP on the Supervisor's Docker
  network ([`app.py:365-367`](https://github.com/home-assistant/supervisor/blob/d8c87c4f2a1814b60688384f1c071e464947bbd0/supervisor/apps/app.py#L365-L367)).
  The watchdog always talks to the container directly, never via the host.
- **`[PORT:n]` (or a bare `n`) is the *container* port.** It is remapped through the add-on's `ports:`
  table **only when the add-on uses `host_network`**; otherwise the literal number is used
  ([`app.py:832-840`](https://github.com/home-assistant/supervisor/blob/d8c87c4f2a1814b60688384f1c071e464947bbd0/supervisor/apps/app.py#L832-L840)).
  This add-on does not set `host_network`, so `[PORT:4000]` dials container port 4000 and the
  `4000/tcp: 4000` host mapping is irrelevant to the watchdog. An operator who remaps the host port,
  or sets it to `null` to stop exposing the API, does not break the watchdog.
- **Everything after the port is the path**, appended verbatim. There is no query-string or
  header support, and no way to specify a method: it is always a GET.

## 6. What the documentation says

[developers.home-assistant.io/docs/add-ons/configuration](https://developers.home-assistant.io/docs/add-ons/configuration/)
describes `watchdog` as *"A URL for monitoring the app health. Like `http://[HOST]:[PORT:2839]/dashboard`,
the port needs the internal port, which will be replaced with the effective port"*, documents the
`[PROTO:option]` and `tcp://[HOST]:[PORT:80]` forms, and notes it "works for apps on the host or
internal network".

**It says nothing whatsoever about what happens when the check fails** — no mention of restarts, of
the two-failure threshold, of the 120-second interval, or of the toggle defaulting to off. Every
behavioural fact in this document is source-only. Anyone reasoning about the watchdog from the
documentation alone would have no way to know that declaring the field makes the Supervisor restart
the add-on, which is presumably how the field came to point at `/api/blocking/status` here in the
first place.

## Implications for this add-on

1. **Claim A is confirmed. #317's mechanism choice stands, and its reasoning can be strengthened.**
   A failing watchdog restarts the add-on; there is no "flag it unhealthy" alternative in the code.
   Repointing the watchdog at any upstream-truthful target — or serving one ourselves — would convert
   a transient upstream outage into a DNS-down restart, which is the outcome ADR-0012 rejects.
2. **The sticky counter is the sharpest form of the argument, and #317 does not make it.** Two
   failures need not be consecutive (§2.2). A single dropped poll arms the add-on indefinitely, so a
   truthful watchdog would restart DNS on the *first* real upstream blip after any earlier unrelated
   miss. Worth a sentence in ADR-0012.
3. **The ADR-0011 clarification is confirmed and can be written as fact.** Manifest fields sit in
   `data.system[slug]` and are replaced wholesale on install/update/restore; option values sit in
   `data.user[slug][ATTR_OPTIONS]` and are deliberately preserved across updates. `watchdog` is above
   `options:`, so it is a manifest field and default pinning does not apply. The precise reach is
   "the next add-on update", not "immediately" and not "restart".
4. **The status code is the only channel.** A watchdog target must express failure as a non-2xx HTTP
   status; body content is unreadable. This closes #313's open question from the other side.
5. **The watchdog is off by default, so the field we ship is inert for most installs** (§4). Two
   consequences: the current `/api/blocking/status` watchdog is doing less than it appears to, and
   any operator-facing documentation about add-on health should say the toggle exists and what
   enabling it means — the Supervisor will restart Blocky if the HTTP API stops answering, which is a
   liveness check, not a resolution check.
6. **We already have a second armed restart path**: our Docker `HEALTHCHECK` runs
   `blocky blocking status` and three failures mark the container `UNHEALTHY`, which the same toggle
   turns into a Supervisor restart (§2.3). It is upstream-blind for the same reason the watchdog URL
   is. Anything added to `services.d/` — including #317's `upstream-probe` — must not be able to take
   the container down, or it inherits this path.

## Open questions

- **Whether `/api/blocking/status` is the right liveness target even as a liveness check.** It is
  served by the same process as DNS, so it does catch a dead Blocky; but it is also the endpoint that
  #313 showed cannot fail. Whether a liveness watchdog on a DNS server is desirable at all — given
  that its only action is a restart — is a design question this research does not settle.
- **Whether the sticky-failure behaviour is intentional.** It reads like a bug (the success path
  plainly should reset the counter), but it is the behaviour of the current release either way. If it
  is fixed upstream, the "two scattered failures" argument weakens to "two consecutive failures"; the
  conclusion does not change, and ADR-0012 should not be written to depend on it alone.
- **Supervisor version drift.** Unlike Blocky, the Supervisor is not pinned by this repository, so
  these constants (120 s, 10 s, two failures) can change under us without any change on our side. The
  structural facts — restart-not-flag, status-code-only, manifest-snapshot-at-update — are stable
  across the lineage; the numbers are not.
