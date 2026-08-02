# What #317's probe verdict is, and what it would take to consume it

A reading of shipped code, not a design. [#317](https://github.com/robocopklaus/hassio-addon-blocky/pull/317)
merged the upstream resolution probe; map
[#322](https://github.com/robocopklaus/hassio-addon-blocky/issues/322) commits to *building on it
rather than adding a second probe*, and
[#323](https://github.com/robocopklaus/hassio-addon-blocky/issues/323) settled that the add-on's
obligation is to make its **Runtime facts readable** and stops there. This document establishes what
the probe's verdict physically is today, what timing contract it comes with, and what each candidate
way of making it readable would cost.

It deliberately chooses nothing. Which surface carries the fact is
[#327](https://github.com/robocopklaus/hassio-addon-blocky/issues/327).

## Sources

- This repo @ [`57fa9e4`](https://github.com/robocopklaus/hassio-addon-blocky/commit/57fa9e41135531bbc9a3df16a78d4d1dcae325ce)
  — the merge of #317. All line references below are to that tree.
- [`docs/adr/0012-upstream-reachability-is-observed-not-enforced.md`](../adr/0012-upstream-reachability-is-observed-not-enforced.md)
  — the probe's own ADR, including the alternatives already rejected.
- [`docs/adr/0001-persistent-storage-path-convention.md`](../adr/0001-persistent-storage-path-convention.md)
  — the `/config` vs `/data` rule any status file must answer to.
- Home Assistant [add-on configuration reference](https://developers.home-assistant.io/docs/add-ons/configuration/)
  for the `map` vocabulary, and the [`file`](https://www.home-assistant.io/integrations/file/)
  integration page for what core can read.

---

## 1. Where the verdict lives: nowhere but the log, and only as edges

The probe is three files: `etc/services.d/upstream-probe/run` (the loop),
`etc/services.d/upstream-probe/finish` (restart throttling), and
`usr/lib/blocky/upstream_probe.sh` (pure classifier helpers). Searched end to end, the loop writes
**no file, sets no exit code, and touches nothing outside its own process**. Every output is a
`bashio::log.*` call.

The verdict exists in exactly two forms, neither consumable:

**a. Three shell variables inside `run`.** `state` (`unknown` | `healthy` | `failing`),
`consecutive_failures`, and `failed_probes_since_warning` are plain locals in the service's own
process. `state` is the *debounced* verdict — the thing an operator would actually want as an
entity — and no other process can see it.

**b. Log lines, on transitions only.** The loop logs on *changes*, not on every probe:

| Condition | Line |
| --- | --- |
| first `resolved` after start | `Upstream DNS resolution verified.` (info) |
| `failing` → `resolved` | `Upstream DNS resolution recovered.` (info) |
| 2nd consecutive `failed` | three-line warning block |
| 12 further `failed` probes | the same warning block again |
| every other probe | *nothing* |

So the log carries **edges, not level**. A consumer cannot ask "is DNS working right now"; it can
only replay every line since container start and reconstruct the state machine — and silence is the
healthy signal, indistinguishable from a probe that died. The warning text is prose with no stable
machine token, and the Supervisor's log buffer is bounded, so a replay is not even guaranteed to
reach the last transition.

**Nothing else carries it either**, and each of these is worth stating because each looks like it
might:

- **s6 service state.** `upstream-probe` is "up" regardless of verdict. In Custom Config Mode the
  service parks in `while true; do sleep 86400; done` — so "up" is true even when the probe is
  disabled and will never report anything.
- **Exit code.** The loop never exits by design. `finish` only ever sees a crash, and its reaction
  is a log warning plus `sleep 60` before s6 restarts it — the exit code communicates nothing about
  upstreams.
- **The watchdog.** `config.yaml` points it at `http://[HOST]:[PORT:4000]/api/blocking/status`.
  ADR-0012 §rejected-1 already ruled out pointing it at truth: an unhealthy watchdog makes the
  Supervisor **restart the add-on**, turning a transient upstream outage into a restart loop that
  takes DNS down for the whole network.
- **Blocky's own API.** [#318](https://github.com/robocopklaus/hassio-addon-blocky/issues/318)
  established v0.34.0 exposes no GET-able upstream-health signal, and the add-on does not build
  Blocky. There is no field to add.

## 2. The timing contract

Read off the constants in `run` (`PROBE_INTERVAL=300`, `FAILURE_THRESHOLD=2`,
`REWARN_AFTER_FAILED_PROBES=12`, `PROBE_TIMEOUT=30`, `WARMUP_INTERVAL=5`, `WARMUP_ATTEMPTS=24`):

- **Warm-up before the first probe.** The loop polls `/api/blocking/status` with `curl -m 5`, then
  `sleep 5`, up to 24 times. A responsive API exits on the first iteration; a Blocky that never
  comes up costs up to **240 s** (24 × (5 s timeout + 5 s sleep)) before the first real probe runs
  anyway. The warm-up cannot fail — it falls through.
- **Cadence is 300 s *plus* the probe.** The interval `sleep` runs *after* the probe, so a cycle is
  300–330 s depending on how long the query takes. Cadence drifts under failure, which matters for
  any freshness threshold a consumer sets: "stale after 6 minutes" is wrong when the healthy cycle
  can be 5.5 minutes.
- **Before any verdict exists, there is nothing.** `state=unknown` and the loop logs *nothing* until
  the first classified probe. The unknown window is roughly 0–4 minutes after start.
- **Transient vs sustained.** One `failed` never warns. Two consecutive `failed` verdicts set
  `state=failing` and warn — first warning lands roughly **5.5–11 minutes** after onset, depending
  where in the cycle the outage began and how much of the 30 s budget each probe burns. Re-warning
  needs 12 further failed probes, so **≈ 60–66 minutes** apart.
- **Recovery is undebounced.** A single `resolved` flips `state` to `healthy` and logs immediately —
  asymmetric with the two-strike rule for failure, deliberately.
- **`inconclusive` freezes the level.** This is the sharpest hazard for a consumer. When Blocky
  itself is down or still starting, the probe classifies `inconclusive`, resets the failure run, and
  **leaves `state` untouched**. So while Blocky is dead, the debounced state reads whatever it last
  was — typically `healthy`. ADR-0012 defends this as correct (Blocky's own logging owns that
  failure), but it means a naive entity fed from `state` would report healthy DNS during a total
  Blocky outage.
- **A probe crash silently resets the level.** `finish` warns, sleeps 60 s, s6 restarts `run` — and
  `state` returns to `unknown`, the warm-up repeats, and `Upstream DNS resolution verified.` prints
  again. Level is not durable across probe restarts.

### What the verdict actually means

The three per-probe verdicts from `probe_classify` are `resolved` | `failed` | `inconclusive`, and
the fact they support is narrower than the map's shorthand "DNS resolution works":

- It is specifically about **the `default` upstream group as seen by a local client**. Per-client
  groups no local query reaches are outside its view, and `CONDITIONAL` is excluded on purpose.
- Anything Blocky answers by itself — cache, blocking, filtering, custom DNS, hosts, special-use
  names — is `inconclusive`, never proof.
- It says nothing when Blocky is down.

Any entity derived from it must therefore be named for **upstream reachability**, not for DNS
working. Naming it "DNS working" would make it lie in exactly the case an operator most wants
covered (Blocky dead), and the wrong name is not fixable later once it is in someone's automations.

## 3. Mode boundary: Standard Mode only, and the surface must say so

`run` short-circuits before the loop:

```sh
if bashio::config.true 'custom_config'; then
    bashio::log.info "Upstream resolution probe is disabled in Custom Config Mode."
    while true; do sleep 86400; done
fi
```

ADR-0012 grounds this in ADR-0004's rule — the probe's fixed `127.0.0.1:4000` is a fact of the
config *we render*; in Custom Config Mode the operator decides whether there is an HTTP listener at
all and on which port. This is settled and not reopened here.

The consequence for #327 is concrete: **in Custom Config Mode there is no verdict, ever.** A surface
must distinguish "disabled by design" from "not reported yet" from "reported failing". That is
three non-failure states, and the distinction is not cosmetic — an operator in Custom Config Mode
whose sensor sat at `unknown` forever would reasonably file a bug.

## 4. What a consumer would need

Derived from §1–§3, stated as requirements rather than as a design:

1. **Level, not edges.** The current debounced state, readable at any moment without replaying
   history.
2. **A timestamp.** Because silence is the healthy signal, freshness is the only way to tell a
   healthy probe from a dead one. Without it, stale reads as healthy.
3. **Three distinguishable non-failure states**: `healthy`, `unknown` (startup or post-crash), and
   `disabled` (Custom Config Mode).
4. **The debounced state, not the raw verdict.** If only the per-probe verdict were exposed, every
   consumer would have to re-implement the two-strike rule and the `inconclusive`-resets-the-run
   rule to match what `DOCS.md` promises. Exposing raw *as well* is harmless; exposing raw *instead*
   pushes the state machine onto the operator.
5. **Honest availability.** A consumer needs to tell "the add-on is running and says healthy" from
   "the add-on is not running". #325 established this is exactly where MQTT retained state fails
   (available and stale); a pull surface gets it for free only if absence is observable.
6. **Readable from outside this container** — by Home Assistant core, or by a future integration.
   This is the requirement that eliminates most of §5.

## 5. The candidate changes, and what each costs

### The decisive external constraint

**Home Assistant core cannot read an add-on's `addon_config` directory.** Add-on configs live under
`/addon_configs/<slug>/` on the host; that path is not mounted into the core container, so
`allowlist_external_dirs` rejects it as "Not a directory" and the `file` integration cannot reach
it. The only documented workaround is mounting `/addon_configs` back in over Samba as network
storage — an operator-side setup step involving a second add-on.

This is what makes the cheapest-looking option not the cheapest, and it is why the options below
split by *which mount* rather than by *which format*.

| Option | Code cost | Operator cost | Readable by core? |
| --- | --- | --- | --- |
| **A.** Status file under `/config/` | ~10 lines; mount already present | none | **No** (needs Samba workaround) |
| **B.** Status file under `/data/` | ~10 lines; mount always present | n/a | **No** — invisible to everyone |
| **C.** Status file under `/share/` | ~10 lines + new `share:rw` mount | `allowlist_external_dirs` edit + core restart | Yes, after that edit |
| **D.** Status file into core's `www/` | ~10 lines + `homeassistant_config:rw` | none | Yes, no edit at all |
| **E.** Own HTTP endpoint | a listener process + new port | add a `rest` sensor | Yes |
| **F.** Extend Blocky's API | impossible (#318) | — | — |
| **G.** Supervisor `discovery:` | one manifest key | install an integration | inert alone (#324) |

Detail on each, since the table flattens the parts that matter:

**A. Status file under `/config/` (`addon_config:rw`, already mapped).** ADR-0001's test — "would
the operator ever want to look at this file?" — says yes, so `/config/` is the right side of that
split, and the mount already exists. Writing it is a handful of lines in `run` plus a pure writer
helper that `scripts/test-guards.sh` can pin the way it already pins `probe_classify`. It needs an
atomic write (temp file + `mv`) so a reader never sees a half-written file — cheap, but it has to be
deliberate. It satisfies every requirement in §4 *except* the last one for core: the operator can see
it, another add-on with `all_addon_configs` can see it, HA core cannot.

**B. Status file under `/data/`.** ADR-0001 routes internal regenerable state here, and a status
file is arguably that. But `/data/` is add-on-private and hidden from the user, so it fails §4.6
completely. Recorded only to close it off.

**C. Status file under `/share/` (needs `share:rw` added to `map`).** `/share` *is* mounted into the
core container, so this is the cheapest path to a core-readable file. The cost is not code: the
operator must add `/share` to `allowlist_external_dirs` in `configuration.yaml` and restart core
before a `file` sensor works, and `/share` is a flat shared namespace across all add-ons, so it
needs a `blocky/` subdirectory and is collision-prone by nature. It also stretches ADR-0001, which
knows only `/config` and `/data`.

**D. Status file into core's config dir under `www/` (needs `homeassistant_config:rw`).** The
default allowlist already covers the `www` folder inside the config directory, so this is the only
file option needing **zero** operator YAML. It is also the worst boundary violation on the list: the
add-on would write into another component's directory, and anything under `www/` is served over
HTTP at `/local/…` to anyone who can reach the HA frontend. Cheap for the user, and squarely against
the ownership instinct ADR-0001 and ADR-0011 both encode. On the record so the ADR can reject it
with a reason rather than by omission.

**E. Own HTTP endpoint in the add-on.** Naturally satisfies all six requirements: level, freshness,
three states, and honest availability for free (connection refused when the add-on is down — the
exact property #325 found MQTT retained state cannot give). A core `rest` sensor consumes it with no
`configuration.yaml` edit. The costs are real: something must listen — a `socat`/BusyBox httpd or a
bashio accept loop — which is a **second long-running process**, and while #323's rule is about
*outward* connections rather than inbound listeners, this is the option closest to the line it drew.
It also needs a port declared in `config.yaml` and `ports_description`, which puts another listener
on the LAN in a repo whose `DOCS.md` already carries a section on not exposing ports. Whether the
verdict could instead ride on the existing `:4000` is worth noting as false hope: that port is
Blocky's own listener, not ours.

**F. Extend Blocky's own API.** Not available (§1). Listed so the ADR does not have to re-derive it.

**G. Supervisor `discovery:`.** #324 found this is how AdGuard and Pi-hole do it — but it is inert
without a companion integration to receive it, and there is nothing to discover unless one of A–E
exists first. It is a *complement* to a chosen surface, not a surface.

One more non-option worth recording: **core reading the add-on log through the Supervisor.** The
Supervisor exposes add-on logs over its API and core holds a supervisor token, but no core
integration surfaces add-on logs as sensor state, and a template cannot read the token from the
environment. Combined with §1's edges-not-level problem, log scraping is not a path.

## 6. What this leaves open for #327

- **A or E** are the two live candidates; **C** is the compromise that buys core-readability for an
  operator-side YAML edit. **B, D, F, G** are closed or complementary.
- The decision turns on a trade #327 has to make explicitly: a file the add-on already has a mount
  for but core cannot read (A), versus a surface core reads natively at the cost of a listener
  process and a port (E).
- Whichever wins, the entity must be named for **upstream reachability**, must expose the debounced
  state with a timestamp, and must distinguish `disabled` from `unknown`.
- Whether the blocking switch travels on the same surface is untouched here. Blocking status *is*
  GET-able on `:4000` already, so it has a core-readable path that the probe verdict does not — the
  two needs may not want the same answer.
