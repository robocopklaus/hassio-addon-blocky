# What MQTT push would have cost this add-on

An appendix, not a survey. [#323](https://github.com/robocopklaus/hassio-addon-blocky/issues/323)
already ruled push out *in principle* — the add-on exposes, others consume; it holds no outward
connection. This document exists so the ADR that map
[#322](https://github.com/robocopklaus/hassio-addon-blocky/issues/322) produces can reject MQTT
**with measured facts** rather than by assertion.

Nothing here is a design. Discovery topic layout and config payload shapes are deliberately absent —
nothing is being built. What is recorded is only what MQTT push would have *cost*: what the manifest
declaration buys, how credentials are obtained and what happens when there is no broker, what would
have to run, and who would be left holding the entities afterwards.

## Sources

Links are permalinked to the commit current at the time of writing. Where a fact is an *absence*,
the exact grep that established it is given, because absence is the load-bearing part of §1.

- `home-assistant/supervisor` @ [`3dea234`](https://github.com/home-assistant/supervisor/tree/3dea234189bc9fc910729fa502be2e1024462103) (branch `main`)
- `hassio-addons/bashio` @ [`ac3781c`](https://github.com/hassio-addons/bashio/tree/ac3781c227b2fd1de71f1f9240cbbfb8f27aa3cb) (branch `main`)
- `home-assistant/developers.home-assistant` @ [`99f1b9c`](https://github.com/home-assistant/developers.home-assistant/tree/99f1b9c8cd8d7fa1c373c89b0cce78039b593288) — note the docs tree renamed `docs/add-ons/` to `docs/apps/`
- `home-assistant/home-assistant.io` @ [`c278f75`](https://github.com/home-assistant/home-assistant.io/tree/c278f7555b7f464107a1a4b9940fbb738afbe214) — the MQTT integration page is the normative statement of discovery lifecycle
- `home-assistant/addons` @ [`e030c15`](https://github.com/home-assistant/addons/tree/e030c153bcd43f9aa56d0352df980f99df9451a3) — the official Mosquitto add-on
- Alpine package sizes from `pkgs.alpinelinux.org` (branch `edge`, repo `main`, `x86_64`)

The Supervisor has been renaming "addon" to "app" internally; paths below are as they exist at
`3dea234`, and the user-facing manifest keys are unchanged.

---

## 0. The answer, in one paragraph

The manifest declaration is nearly free and nearly meaningless: `mqtt:want` and `mqtt:need` are
**behaviourally identical** — the Supervisor defines both constants and then never reads either, so
`need` blocks no install, gates no startup, and warns nobody. What the declaration actually buys is
one thing: permission to `GET /services/mqtt`, and that endpoint is populated **only by an add-on
that declares `mqtt:provide`** — in practice the Mosquitto add-on. An operator running an external
broker, or one who set up MQTT purely through the Home Assistant integration, leaves the endpoint
empty, and `bashio::services mqtt` returns nothing with a logged error; the add-on would then have
to either degrade silently or grow its own broker host/credential options, re-opening exactly the
option-surface question ADR-0006 exists to keep shut. The runtime footprint is genuinely small — PR
[#317](https://github.com/robocopklaus/hassio-addon-blocky/pull/317) already runs a long-lived
`services.d` loop with the verdict in hand, so publishing would be a call inside an existing loop,
not a new process, at the price of ~324 KiB of `mosquitto-clients` plus its library. The real cost
is the **lifecycle**, and it is not small: a one-shot publisher can never keep an availability
signal alive (a clean disconnect suppresses the Last Will by protocol), so availability needs either
a persistent connection — a second daemon, which #323 forbids — or retained messages, which the
Home Assistant docs warn create "ghost entities that keep coming back". And on uninstall the
Supervisor removes the container **before** any cleanup, tidies its own discovery and services
records, and touches the broker not at all: the entities outlive the add-on, and removing them is
nobody's job but the operator's, by hand.

---

## 1. The manifest declaration: `want` versus `need`

### 1.1 What is accepted

The manifest key is validated by one regular expression
([`apps/validate.py:139`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/apps/validate.py#L139)):

```python
RE_SERVICE = re.compile(r"^(?P<service>mqtt|mysql):(?P<rights>provide|want|need)$")
```

Two services exist in the whole mechanism, `mqtt` and `mysql`, with three rights. The documented
meaning ([`docs/apps/configuration.md:186`](https://github.com/home-assistant/developers.home-assistant/blob/99f1b9c8cd8d7fa1c373c89b0cce78039b593288/docs/apps/configuration.md#L186)):

> `provide` (this app can provide this service), `want` (this app can use this service) or `need`
> (this app needs this service to work correctly).

### 1.2 What `need` enforces: nothing

The three rights become constants at
[`const.py:404-406`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/const.py#L404-L406):

```python
PROVIDE_SERVICE = "provide"
NEED_SERVICE = "need"
WANT_SERVICE = "want"
```

Only `PROVIDE_SERVICE` is ever read. A full-tree grep of the checked-out repository at `3dea234`:

```
$ grep -rn "NEED_SERVICE\|WANT_SERVICE" supervisor/ tests/
supervisor/const.py:405:NEED_SERVICE = "need"
supervisor/const.py:406:WANT_SERVICE = "want"
```

Definitions and no uses — not in the installer, not in the start path, not in a test. So, concretely:

- **Installability**: unaffected. Nothing consults the value before or during install.
- **Startup**: unaffected. Declaring `mqtt:need` with no broker installed starts the add-on normally.
- **User warning**: none. The Supervisor never tells the operator a needed service is missing.
- **Ordering**: unaffected by the rights value. Start order comes from the unrelated `startup` key.

The only place the value matters is the access check on the services API
([`api/services.py:95-102`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/api/services.py#L95-L102)):

```python
def _check_access(request, service, provide=False):
    app = request[REQUEST_FROM]
    if not app.services_role.get(service):
        raise APIForbidden(f"No access to {service} service!")
    if provide and app.services_role.get(service) != PROVIDE_SERVICE:
        raise APIForbidden(f"No access to write {service} service!")
```

`want` and `need` are indistinguishable here — both are merely truthy. Writing requires `provide`.

**Cost recorded:** the declaration is one manifest line, and choosing `need` over `want` would have
communicated a requirement to human readers of `config.yaml` and to nothing else.

### 1.3 What the Supervisor does when no broker is installed

`GET /services/mqtt` returns the stored service data only if a provider has published it
([`api/services.py:65-67`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/api/services.py#L65-L67)):

```python
if not service.enabled:
    raise APIError("Service not enabled")
```

`enabled` is simply "is the stored dict non-empty"
([`services/interface.py:50-52`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/services/interface.py#L50-L52)), and the dict is
filled only by an add-on `POST`ing to the endpoint with `mqtt:provide` rights. Exactly one provider
may hold it at a time — a second attempt raises `ServiceAlreadyProvidedError`
([`services/modules/mqtt.py:73-78`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/services/modules/mqtt.py#L73-L78)).

In practice the provider is the official Mosquitto add-on, which declares `services: - mqtt:provide`
([`mosquitto/config.yaml`](https://github.com/home-assistant/addons/blob/e030c153bcd43f9aa56d0352df980f99df9451a3/mosquitto/config.yaml)) and publishes host, port, `addons` username and password from its
`services.d/mosquitto/discovery` script.

**This is the load-bearing constraint.** The Supervisor service is a *Mosquitto-add-on* channel, not
a *Home Assistant MQTT* channel. An operator whose broker runs on a NAS, in another container, or as
a cloud service has a perfectly working MQTT setup in Home Assistant and an **empty** `/services/mqtt`.
For those installs, an MQTT-publishing Blocky add-on would either quietly do nothing or need its own
broker host / port / username / password options — the curated-surface growth ADR-0006 rejects.

## 2. Obtaining broker credentials at runtime

`bashio::services` is a thin wrapper over that endpoint
([`lib/services.sh:17-70`](https://github.com/hassio-addons/bashio/blob/ac3781c227b2fd1de71f1f9240cbbfb8f27aa3cb/lib/services.sh#L17-L70)):

```bash
config=$(bashio::api.supervisor GET "/services/${service}" false)
if [ "$?" -ne "${__BASHIO_EXIT_OK}" ]; then
    bashio::log.error "Failed to get services from Supervisor API"
    return "${__BASHIO_EXIT_NOK}"
fi
```

The documented usage is a field at a time
([`docs/apps/communication.md:58-60`](https://github.com/home-assistant/developers.home-assistant/blob/99f1b9c8cd8d7fa1c373c89b0cce78039b593288/docs/apps/communication.md#L58-L60)):

```bash
MQTT_HOST=$(bashio::services mqtt "host")
MQTT_USER=$(bashio::services mqtt "username")
MQTT_PASSWORD=$(bashio::services mqtt "password")
```

The payload schema is host, port, and optional username, password, ssl, protocol
([`services/modules/mqtt.py:27-38`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/services/modules/mqtt.py#L27-L38)).

**When the service is absent**, per §1.3 the endpoint 400s and:

- `bashio::services mqtt "host"` logs `Failed to get services from Supervisor API` and returns
  non-zero, printing nothing. Under `set -e` this is fatal; without it, an empty host silently
  propagates — a failure mode the add-on would have to handle explicitly.
- `bashio::services.available mqtt` ([`lib/services.sh:78-88`](https://github.com/hassio-addons/bashio/blob/ac3781c227b2fd1de71f1f9240cbbfb8f27aa3cb/lib/services.sh#L78-L88)) is the intended guard: it
  swallows output and returns non-zero. Any correct implementation must branch on it first.
- Results are cached per process (`service.info.${service}`), so a broker installed *after* the
  add-on started is not noticed until restart. Publishing would therefore need a restart-to-adopt
  caveat in `DOCS.md`, or its own re-check loop.

**Cost recorded:** credential acquisition itself is three lines. The branch for "no provider", the
operator-facing explanation of why a working external broker still yields no entities, and the
restart-to-adopt caveat are the actual expense.

## 3. Runtime footprint

Smaller than expected, and this is the one place where MQTT push scored well.

**No new process would be needed.** PR #317 already adds a long-lived s6 service,
`services.d/upstream-probe/run`, whose loop holds the verdict in a shell variable and acts only on
transitions (`resolved` → `Upstream DNS resolution recovered.`). A publish would be one call at each
transition point inside that existing loop — no second daemon, no new supervision tree entry, no
extra idle process. The alternative framing considered for this ticket, a separate publishing
service, was never necessary.

**The binary is not in the image.** `blocky/Dockerfile` installs `ca-certificates`, `curl`, `tzdata`
and nothing else; there is no MQTT client. Adding one costs, on Alpine `edge/main/x86_64`:

| Package | Download | Installed |
| --- | --- | --- |
| `mosquitto-clients` | 69.8 KiB | 168.1 KiB |
| `mosquitto-libs` | 67.3 KiB | 155.6 KiB |

≈324 KiB installed, plus `libcjson`; the TLS libraries it links (`libssl`, `libcrypto`) are already
present via `curl`. Two more packages under Renovate, on an image that currently pins three things.

**Cost recorded:** ~324 KiB, two new tracked dependencies, and roughly a dozen lines inside an
existing loop. On footprint alone MQTT push would have been defensible.

## 4. Availability, lifecycle, and who cleans up

This is where the cost stops being small, and none of it is avoidable by writing better code.

### 4.1 A one-shot publisher cannot express availability

Home Assistant models availability as a Birth message plus a broker-held Last Will
([mqtt.markdown:1076-1078](https://github.com/home-assistant/home-assistant.io/blob/c278f7555b7f464107a1a4b9940fbb738afbe214/source/_integrations/mqtt.markdown#L1076-L1078)):

> A device or service can announce its availability by publishing a Birth message and set a Will
> message at the broker. When the device or service loses connection to the broker, the broker will
> publish the Will message.

A will fires when a connection is **lost**; MQTT suppresses it on a clean `DISCONNECT`. A shell loop
invoking a publisher per transition connects and cleanly disconnects each time, so its will never
fires and there is no held connection to lose. Such a publisher can set an entity's *state* but can
never mark it *unavailable* — which is precisely the signal an operator automating on "DNS is dead"
needs, since a stopped add-on and a failing probe must not look the same. Getting it requires a
process holding an open MQTT connection for the add-on's lifetime: a second daemon whose reason for
existing is the outward connection #323 ruled out.

### 4.2 Home Assistant restarts force a choice, and both options cost

On restart, entities are unavailable until discovery is re-received
([mqtt.markdown:265](https://github.com/home-assistant/home-assistant.io/blob/c278f7555b7f464107a1a4b9940fbb738afbe214/source/_integrations/mqtt.markdown#L265)):

> When MQTT starts up, all existing MQTT devices, entities, tags, and device triggers, will be
> unavailable until a discovery message is received and processed. A device or service that exposes
> the MQTT discovery should subscribe to the Birth message and use this as a trigger to send the
> discovery payload.

Two options, per the docs' own framing (§"Using Birth and Will messages" / "Using retained config
messages"):

1. **Subscribe to `homeassistant/status`** and republish on `online`. A subscriber is a blocking,
   long-running connection — the same second daemon as §4.1.
2. **Retain the discovery messages** so the broker replays them. No subscriber needed, and the docs
   attach an explicit warning ([mqtt.markdown:1063-1065](https://github.com/home-assistant/home-assistant.io/blob/c278f7555b7f464107a1a4b9940fbb738afbe214/source/_integrations/mqtt.markdown#L1063-L1065)):

   > A disadvantage of using retained messages is that these messages retain at the broker, even when
   > the device or service stops working. They are retained even after the system or broker has been
   > restarted. Retained messages can create ghost entities that keep coming back.

Option 2 is the only one compatible with #323's direction rule, and it is the one that produces
ghosts.

### 4.3 Stop, update, uninstall — the Supervisor cleans its own records and not the broker

Removal is by publishing an empty retained payload to the discovery topic
([mqtt.markdown:448](https://github.com/home-assistant/home-assistant.io/blob/c278f7555b7f464107a1a4b9940fbb738afbe214/source/_integrations/mqtt.markdown#L448)):

> To remove the components, publish an empty (retained) string payload to the discovery topic. This
> will remove the component and clear the published discovery payload. It will also remove the device
> entry if there are no further references to it.

Nothing in the add-on lifecycle ever does this. `App.uninstall`
([`apps/app.py`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/apps/app.py)) removes the container **first**, then cleans up:

```python
await self.instance.remove(remove_image=remove_image)
...
# Cleanup discovery data
for message in self.sys_discovery.list_messages: ...
# Cleanup services data
for service in self.sys_services.list_services: ...
```

Note what that list contains and what it does not. The Supervisor tidies its **own** discovery
records and services records — the `discovery:` mechanism is cleaned up for you — and issues no
broker traffic whatsoever. And because the container is destroyed before any of it, there is no hook
in which a departing add-on could publish its own tombstones; the add-on manifest has no
pre-uninstall script (grep for `uninstall` in `docs/apps/configuration.md` and
`docs/apps/communication.md`: no matches).

The resulting behaviour:

| Event | What happens to the entities |
| --- | --- |
| Add-on stopped | State freezes at its last value. No will fires (§4.1), so the entity reads *available* and stale — an automation on "DNS is dead" sees "DNS was fine". |
| Add-on updated | Container is replaced; retained discovery replays, state resumes. Benign. |
| Add-on uninstalled | Retained discovery survives on the broker. Entities reappear on every Home Assistant restart, forever. |
| Broker replaced/reset | Retained messages gone; entities vanish until the add-on republishes, which only happens on the next state transition — possibly hours. |

**Whose job is removal?** With no uninstall hook and no Supervisor involvement, the operator's — by
hand, with an MQTT client, against a topic they never chose and were never shown. That is the
sharpest single fact in this document: MQTT push would have made *uninstalling this add-on* a task
with manual cleanup, and this is exactly the class of obligation that Supervisor `discovery:` and a
polled read surface do not create.

---

## 5. Summary for the ADR

| Dimension | Measured cost |
| --- | --- |
| Manifest declaration | One line. `need` vs `want` is a no-op — both constants are defined and never read (§1.2). |
| Broker availability | Only via an add-on declaring `mqtt:provide`, i.e. Mosquitto. External brokers leave the endpoint empty and would force new add-on options (§1.3). |
| Credentials | Three bashio lines, plus a mandatory `services.available` branch, a silent-empty-value hazard, and a per-process cache making a later-installed broker invisible until restart (§2). |
| Runtime | No new process — #317's loop already exists. ~324 KiB for `mosquitto-clients` + `mosquitto-libs`, two more Renovate-tracked packages (§3). |
| Availability signal | Unobtainable without a persistent connection; a one-shot publisher's will never fires. A stopped add-on looks healthy (§4.1). |
| Restart survival | Retained discovery, which the HA docs warn creates ghost entities — or a subscriber daemon (§4.2). |
| Uninstall | Container removed before any hook; Supervisor cleans its own discovery/services records and never the broker. Entities persist; manual operator cleanup (§4.3). |
