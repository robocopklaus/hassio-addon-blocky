# What a Home Assistant operator can already get for Blocky today

Primary-source research into whether anything outside this add-on already turns a Blocky instance
into Home Assistant entities — a HACS or custom integration, a shared YAML recipe, or a core
integration — and, if not, what the surrounding DNS add-on ecosystem does instead.

Written to settle [#324](https://github.com/robocopklaus/hassio-addon-blocky/issues/324) of map
[#322](https://github.com/robocopklaus/hassio-addon-blocky/issues/322), which asks what an operator
gets for free before this add-on changes anything.

Everything below is read from source code, machine-readable registries, or the official developer
documentation's own Markdown source. Negative results are stated with the exact queries that
produced them, because a large part of what this ticket establishes is *absence*.

## Sources and how to read the links

Links are permalinked to the commit that was current at the time of writing:

- `home-assistant/core` @ [`e8864d5`](https://github.com/home-assistant/core/tree/e8864d5eef4868530d0dd53b3d02fae2a710a5cb) (branch `dev`)
- `home-assistant/supervisor` @ [`3dea234`](https://github.com/home-assistant/supervisor/tree/3dea234189bc9fc910729fa502be2e1024462103) (branch `main`)
- `home-assistant/addons` @ [`e030c15`](https://github.com/home-assistant/addons/tree/e030c153bcd43f9aa56d0352df980f99df9451a3) (branch `master`) — the *official* add-ons
- `home-assistant/developers.home-assistant` @ [`99f1b9c`](https://github.com/home-assistant/developers.home-assistant/tree/99f1b9c8cd8d7fa1c373c89b0cce78039b593288) — docs source, cited in preference to the rendered site because the site has been restructured (see §4.1)
- `hassio-addons/app-adguard-home` @ [`e8d6167`](https://github.com/hassio-addons/app-adguard-home/tree/e8d616767433487f6136085766b4dee7cc07a134) — note the repo was renamed from `addon-adguard-home` to `app-adguard-home`
- `hacs/default` @ [`d97dc85`](https://github.com/hacs/default/tree/d97dc8503dea620736bab19ebe48d3599e62faba)

GitHub searches were run with the authenticated `gh` CLI against the code, repo, and issue search
APIs. Forum searches were run against Discourse's own JSON search endpoint at
`https://community.home-assistant.io/search.json?q=…`, which returns the same result set as the
site's search box.

---

## 0. The answer, in one paragraph

**Nothing exists.** There is no Blocky integration in HACS, no working custom component anywhere on
GitHub, no shared REST/`command_line`/template recipe, and not one Home Assistant thread — on the
official forum or in Blocky's own 161 discussions and issue tracker — asking for a Blocky sensor.
The single repository that looks like a hit, [`LuloDev/blocky_dns`](https://github.com/LuloDev/blocky_dns),
is a one-commit December-2023 scaffold whose entire component is `async_setup` returning `True`; it
has zero entities, zero stars, no release, and is not in HACS. The only Blocky-and-Home-Assistant
artifacts that exist are requests for the *add-on itself* ([blocky#500](https://github.com/0xERR0R/blocky/issues/500),
[blocky#1683](https://github.com/0xERR0R/blocky/issues/1683)) — both satisfied by this repository —
and one request here for Prometheus/Grafana ([#36](https://github.com/robocopklaus/hassio-addon-blocky/issues/36)).
Meanwhile the ecosystem norm for DNS add-ons is unambiguous and it is **not** "the add-on publishes
entities": for AdGuard Home, the add-on publishes *nothing* and a separate **core integration** polls
it, auto-configured because the add-on posts one JSON blob to the Supervisor's `/discovery` API
([`adguard/config.yaml:23`](https://github.com/hassio-addons/app-adguard-home/blob/e8d616767433487f6136085766b4dee7cc07a134/adguard/config.yaml#L23)
plus a 20-line s6 script); Pi-hole's core integration does the same polling but has no discovery hook
at all, so users type a host. Add-ons publishing their *own* entities via MQTT discovery is a real and
widespread pattern — 360+ third-party add-on `config.yaml` files declare `mqtt:need` — but it appears
**zero times** in the two blessed repositories (`home-assistant/addons`, `hassio-addons`), where the
four add-ons that integrate with HA all use Supervisor discovery instead. **Supervisor discovery is
the mechanism nobody in #322 has named yet, and it is the one AdGuard actually uses.**

---

## 1. No existing integration

### 1.1 HACS: not listed, in any category

HACS's default repository list is a set of plain JSON files, one per category. Fetching each and
grepping case-insensitively for `blocky`:

| Category file | `blocky` matches |
|---|---|
| [`integration`](https://github.com/hacs/default/blob/d97dc8503dea620736bab19ebe48d3599e62faba/integration) (3105 entries) | **0** |
| `plugin` | 0 |
| `theme` | 1 — [`PixNyb/hass-theme-blocky`](https://github.com/PixNyb/hass-theme-blocky), an unrelated *visual theme* |
| `appdaemon` | 0 |
| `python_script` | 0 |
| `template` | 0 |
| `netdaemon` | 0 |

**There is no Blocky integration in HACS.** The only match in the entire HACS registry is a Lovelace
colour theme that happens to be called "Blocky".

### 1.2 GitHub: one repository, and it is an empty scaffold

Code search `blocky path:custom_components` returns 7 files across 3 repositories; two
([`enoch85/ovms-home-assistant`](https://github.com/enoch85/ovms-home-assistant),
[`tiejiang29/state_grid`](https://github.com/tiejiang29/state_grid)) match on unrelated substrings.
The only real hit is **[`LuloDev/blocky_dns`](https://github.com/LuloDev/blocky_dns)**.

Its complete component implementation, at
[`custom_components/blocky_dns/__init__.py`](https://github.com/LuloDev/blocky_dns/blob/947e876f/custom_components/blocky_dns/__init__.py):

```python
from homeassistant import core


async def async_setup(hass: core.HomeAssistant, config: dict) -> bool:
    """Set up the Blocky DNS component."""
    # @TODO: Add setup code.
    return True
```

`const.py` is one line (`DOMAIN = "blocky_dns"`). There is no `sensor.py`, no `switch.py`, no
`config_flow.py`, no API client. The manifest declares `"config_flow": false`, `"requirements": []`,
and points its documentation URL at `SeniorByteDev/blocky_dns`, a repository that **404s**.

Repository metadata from `gh api repos/LuloDev/blocky_dns`:

- 1 commit total — `947e876` "Initial base proyect :beers:", **2023-12-24**
- 0 stars, 0 forks, 0 releases, 0 open issues, no license
- `pushed_at: 2023-12-24T23:17:01Z` — untouched for over two and a half years

So: **it exposes no entities, calls no Blocky API endpoint, is unmaintained, and is not HACS-listed.**
The question of whether it depends on this add-on or talks to any Blocky instance does not arise —
it talks to nothing.

### 1.3 Everything else searched, and found empty

| Query | Surface | Result |
|---|---|---|
| `blocky home assistant` | repo search | `[]` — no repositories |
| `hass blocky` | repo search | `[]` |
| `blocky dns` | repo search, 40 results | Helm charts, Ansible roles, two web UIs ([blocky-ui](https://github.com/GabeDuarteM/blocky-ui), [blocky-visor](https://github.com/jchheilmann/blocky-visor)), a Rust TUI, a Chrome extension. **No HA integration.** |
| `blocky path:custom_components` | code search | see §1.2 |
| `topic:home-assistant blocky` | repo search | this repo, plus the unrelated theme |
| `"api/blocking/status" "platform: rest"` | code search | **0 results** |
| `"127.0.0.1:4000/api/blocking/status"` | code search | **0 results** |
| `"blocking/status" homeassistant` | code search | 8 results, of which 6 are this repository's own docs; the other two are a Rust homelab dashboard and a Gatus uptime config |

One other Blocky **add-on** exists — [`robinvalk/home-assistant-addons`](https://github.com/robinvalk/home-assistant-addons/blob/main/blocky/config.yaml),
`version: 2022.46.0`, `stage: experimental`. It has no `discovery:` key, no `services:` key, and its
`watchdog:` line is commented out. It publishes no entities either.

## 2. No community recipes, and no one is asking

### 2.1 The Home Assistant forum

Discourse search for `blocky` returns 50 topics, none about Blocky the DNS proxy — the top hits are
"History graph card **blockiness** issue", "**Blocky** Theme" (the Lovelace theme), and
"**Blocking**/unblocking the user by time". Search for `blocky dns` returns Pi-hole threads and a
VLAN scheduling thread. Search for `0xERR0R` (Blocky's author, and a term that would appear in any
config paste) returns **zero topics**.

**There is no Blocky thread on community.home-assistant.io.** Not a recipe, not a question, not a
feature request.

For contrast, the generic ask does exist for other resolvers — e.g.
["DNS sensor"](https://community.home-assistant.io/t/dns-sensor/303277) in Feature Requests asks for
Pi-hole/AdGuard/Cloudflare-for-Teams as sensors. Blocky is absent from it.

### 2.2 Blocky's own repository

`repo:0xERR0R/blocky "home assistant"` across issues and PRs returns **5** results, and only three
are about Home Assistant at all:

- **[#500](https://github.com/0xERR0R/blocky/issues/500)** (2022-04-21), *"[Feature request] Package
  blocky as an addon for Home Assistant"* — "It would be very useful to have blocky packaged as an
  addon for Home Assistant. […] I think the addon feature is actually just a 'template' for how home
  assistant should run a docker container."
- **[#1683](https://github.com/0xERR0R/blocky/issues/1683)** (2025-01-09), *"[Feature] Support
  Required as Home Assistant OS Addon"* — "I would like to request support for integrating Blocky as
  an Home Assistant OS (HAOS) add-on. […] It would be great if an addon can be released for HAOS".
- **[#8](https://github.com/0xERR0R/blocky/issues/8)** (2020-02-09), *"Temporary deactivation of
  blocking"* — the issue that created the enable/disable API, listing as a use case: "Calling REST
  API from external tool (OpenHAB, **Home Assistant**, …)".

The remaining two (#2158, #2201) mention "home assistant" only incidentally in DNSSEC/EDNS bug
reports.

Blocky's **161 GitHub Discussions** contain no Home Assistant thread. Grepping every discussion title
for `assist|home|sensor|api|prometheus|grafana` surfaces only Grafana/Prometheus and API-client
topics (#1803 "How to setup Prometheus & Grafana for Blocky?", #1100 "Webapp for API interaction.",
#1047 "Made a go app for querying api endpoints.", #1528/#976 on Grafana blocking-status panels).

### 2.3 What people actually ask for

Because no one has asked for "a Blocky sensor" in those words, the honest answer to the sub-question
is: **nobody has asked.** The closest real asks, quoted:

- The only feature request in *this* repository touching observability is
  [#36](https://github.com/robocopklaus/hassio-addon-blocky/issues/36) (2025-10-10),
  *"Feature Request: Update Blocky Add-on to Latest Version & Add Prometheus/Grafana Support"*:
  "**Enable Blocky's built-in Prometheus endpoint for metrics collection (/metrics).** Expose the
  Prometheus port (default: 4000) through the add-on's configuration. **Add a toggle in the add-on
  configuration to enable/disable metrics collection.** […] Provide a ready-to-use Grafana dashboard
  JSON file". Note the shape: the requester wants *metrics scraped externally into Grafana*, not HA
  entities.
- Blocky #8's original framing — an external tool toggling blocking over REST — is the only
  "blocking on/off from Home Assistant" statement that exists anywhere, and it is from 2020, written
  by the maintainer, and lists Home Assistant as an example rather than a requirement.

No one has asked for query counts, and no one has asked for is-DNS-up. The interest that does exist
is Grafana-shaped, not entity-shaped.

## 3. The ecosystem precedent for DNS add-ons

### 3.1 AdGuard Home — the add-on publishes nothing; a core integration polls it

This is the clearest precedent and it separates the two roles completely.

**The add-on** ([`hassio-addons/app-adguard-home`](https://github.com/hassio-addons/app-adguard-home/blob/e8d616767433487f6136085766b4dee7cc07a134/adguard/config.yaml))
contains no entity code of any kind. Its entire Home Assistant integration surface is three lines of
manifest —

```yaml
discovery:
  - adguard
```

([`adguard/config.yaml:23-24`](https://github.com/hassio-addons/app-adguard-home/blob/e8d616767433487f6136085766b4dee7cc07a134/adguard/config.yaml#L23-L24),
alongside `hassio_api: true` and `hassio_role: manager` on lines 27-28)

— and one s6 oneshot service, reproduced in full from
[`discovery/run`](https://github.com/hassio-addons/app-adguard-home/blob/e8d616767433487f6136085766b4dee7cc07a134/adguard/rootfs/etc/s6-overlay/s6-rc.d/discovery/run):

```bash
#!/command/with-contenv bashio
declare config

# Wait for AdGuard Home to become available
bashio::net.wait_for 45158 127.0.0.1 300

config=$(\
    bashio::var.json \
        host "127.0.0.1" \
        port "^45158" \
)

if bashio::discovery "adguard" "${config}" > /dev/null; then
    bashio::log.info "Successfully send discovery information to Home Assistant."
else
    bashio::log.error "Discovery message to Home Assistant failed!"
fi
```

That is the whole thing: wait for the port, POST `{"host": "...", "port": ...}` to the Supervisor.

**The core integration** ([`homeassistant/components/adguard`](https://github.com/home-assistant/core/tree/e8864d5eef4868530d0dd53b3d02fae2a710a5cb/homeassistant/components/adguard))
owns every entity. It is `"integration_type": "service"`, `"iot_class": "local_polling"`, and depends
on the external `adguardhome==0.8.1` client library
([`manifest.json`](https://github.com/home-assistant/core/blob/e8864d5eef4868530d0dd53b3d02fae2a710a5cb/homeassistant/components/adguard/manifest.json)).
It publishes:

- **8 sensors** at `SCAN_INTERVAL = timedelta(seconds=300)`
  ([`sensor.py`](https://github.com/home-assistant/core/blob/e8864d5eef4868530d0dd53b3d02fae2a710a5cb/homeassistant/components/adguard/sensor.py)):
  `dns_queries`, `blocked_filtering`, `blocked_percentage`, `blocked_parental`,
  `blocked_safebrowsing`, `enforced_safesearch`, `average_speed`, `rules_count`
- **6 switches** ([`switch.py:34-70`](https://github.com/home-assistant/core/blob/e8864d5eef4868530d0dd53b3d02fae2a710a5cb/homeassistant/components/adguard/switch.py#L34-L70)):
  `protection`, `parental`, `safesearch`, `safebrowsing`, `filtering`, `querylog`
- an **update** entity (`update.py`)

And it auto-configures from the add-on's discovery message via
[`async_step_hassio`](https://github.com/home-assistant/core/blob/e8864d5eef4868530d0dd53b3d02fae2a710a5cb/homeassistant/components/adguard/config_flow.py#L107-L155),
which reads `discovery_info.config[CONF_HOST]` / `[CONF_PORT]` straight out of the add-on's payload,
verifies reachability with `await adguard.version()`, and creates the config entry titled with the
add-on's name. The user's entire setup experience is confirming one dialog.

**Answer to the sub-question: the add-on does not publish entities. A separate core integration
polls the add-on's API, and yes, it uses Supervisor add-on discovery to auto-configure.**

### 3.2 Pi-hole — core integration polls, no discovery at all

[`homeassistant/components/pi_hole`](https://github.com/home-assistant/core/tree/e8864d5eef4868530d0dd53b3d02fae2a710a5cb/homeassistant/components/pi_hole)
is `local_polling` on the `hole==0.9.2` library and publishes:

- **sensors** ([`sensor.py`](https://github.com/home-assistant/core/blob/e8864d5eef4868530d0dd53b3d02fae2a710a5cb/homeassistant/components/pi_hole/sensor.py)):
  ads blocked, ads percentage, clients ever seen, DNS queries, domains being blocked, queries cached,
  queries forwarded, unique clients, unique domains (two description sets, v5 and v6 API shapes)
- **one binary sensor** `status`, whose state is literally
  [`lambda api: bool(api.status == "enabled")`](https://github.com/home-assistant/core/blob/e8864d5eef4868530d0dd53b3d02fae2a710a5cb/homeassistant/components/pi_hole/binary_sensor.py#L32)
- **one switch** that calls `api.enable()` / `api.disable(duration_seconds)`
  ([`switch.py:76-106`](https://github.com/home-assistant/core/blob/e8864d5eef4868530d0dd53b3d02fae2a710a5cb/homeassistant/components/pi_hole/switch.py#L76-L106))
- an **update** entity

Grepping the whole component for `hassio` or `discovery` returns **nothing** — there is no
`async_step_hassio`. Pi-hole users type a host and API key by hand.

The community add-on [`hassio-addons/addon-pi-hole`](https://github.com/hassio-addons/addon-pi-hole)
is **archived**, last pushed **2020-03-30**. It is not a live counter-example either way.

Same answer: **the integration owns entity publishing; the add-on never did.**

### 3.3 Does any add-on publish its own entities via MQTT discovery?

**In the two blessed repositories: no, not one.** Searching `org:hassio-addons` for
`"homeassistant/sensor"` → 0 results; for `"discovery_prefix"` → 0 results. The only MQTT usage in
that org is *consuming* the broker service (`mqtt:want` in
[`app-ssh`](https://github.com/hassio-addons/app-ssh), `addon-vscode`, and
[`app-zwave-js-ui`](https://github.com/hassio-addons/app-zwave-js-ui/blob/main/zwave-js-ui/config.yaml)).

**In the wider third-party ecosystem: yes, extremely commonly.** Code search for `"mqtt:need"
filename:config.yaml` returns **360** results — add-ons like
[`wez/govee2mqtt`](https://github.com/wez/govee2mqtt/blob/main/addon/config.yaml),
[`tsightler/ring-mqtt-ha-addon`](https://github.com/tsightler/ring-mqtt-ha-addon),
[`fl4p/batmon-ha`](https://github.com/fl4p/batmon-ha),
[`FunkeyFlo/ps5-mqtt`](https://github.com/FunkeyFlo/ps5-mqtt),
[`pergolafabio/Hikvision-Addons`](https://github.com/pergolafabio/Hikvision-Addons). A representative
minimal example is [`mkohns/hassio-addons` `s3backup/mqtt_discovery.sh`](https://github.com/mkohns/hassio-addons/blob/main/s3backup/mqtt_discovery.sh),
which is a bash script that `mosquitto_pub -r`s a JSON payload to
`homeassistant/binary_sensor/s3backup/active/config`:

```bash
MQTT_DISCOVERY_TOPIC='homeassistant/binary_sensor/s3backup/active/config'
sendDiscovery
```

So the pattern is **normal, but sharply stratified**: it is what *bridge* add-ons do — add-ons whose
whole reason to exist is translating some protocol into MQTT. It is not what the official or
community-blessed *service* add-ons do. Note also the declaration difference: `mqtt:need` (govee2mqtt)
makes the broker a hard dependency; `mqtt:want` (zwave-js-ui) does not. Both keys are the
add-on-config `services:` list, documented as `provide` / `want` / `need`
([`configuration.md:186`](https://github.com/home-assistant/developers.home-assistant/blob/99f1b9c8cd8d7fa1c373c89b0cce78039b593288/docs/apps/configuration.md#L186)).
The consequence of `want` with no broker present is [#325](https://github.com/robocopklaus/hassio-addon-blocky/issues/325)'s
question, not this one's.

Notably, `app-zwave-js-ui` declares **both** `discovery: [zwave_js]` and `services: [mqtt:want]` —
they are orthogonal mechanisms, and it uses Supervisor discovery for the HA-facing part.

## 4. Supervisor add-on discovery, in detail

### 4.1 The documentation

The URL cited in the ticket, `developers.home-assistant.io/docs/add-ons/communication#services-discovery`,
**no longer resolves to that anchor** — the docs were restructured and "add-ons" renamed to "apps"
(`docs/apps/communication.md`). In the current source there is **no "Services discovery" section**;
what survives is:

- the `/discovery*` Supervisor endpoint listed among those callable without `hassio_api: true`
  ([`communication.md:39`](https://github.com/home-assistant/developers.home-assistant/blob/99f1b9c8cd8d7fa1c373c89b0cce78039b593288/docs/apps/communication.md#L39))
- the config key itself, one table row:
  > `discovery` | list | | A list of services that this app provides for Home Assistant.
  >
  > — [`configuration.md:185`](https://github.com/home-assistant/developers.home-assistant/blob/99f1b9c8cd8d7fa1c373c89b0cce78039b593288/docs/apps/configuration.md#L185)
- the REST shape at [`api/supervisor/endpoints.md:1360`](https://github.com/home-assistant/developers.home-assistant/blob/99f1b9c8cd8d7fa1c373c89b0cce78039b593288/docs/api/supervisor/endpoints.md#L1360)

**The mechanism is barely documented.** One table row is the entire prose specification. This is
worth recording: it is officially supported and load-bearing for the official add-ons, but a reader
of the docs would struggle to discover it.

### 4.2 What actually happens, from source

1. The add-on declares `discovery: [<service>]` in `config.yaml`; the Supervisor validates it as a
   bare list of strings
   ([`apps/validate.py:525`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/apps/validate.py#L525)).
2. At runtime the add-on POSTs `{"service": ..., "config": {...}}` to the Supervisor's `/discovery`.
   `bashio::discovery` is a 20-line wrapper around exactly that
   ([`bashio/lib/discovery.sh`](https://github.com/hassio-addons/bashio/blob/main/lib/discovery.sh)).
3. The Supervisor stores the message and pushes it to Home Assistant at
   `api/hassio_push/discovery/{uuid}`
   ([`discovery/__init__.py:117-136`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/discovery/__init__.py#L117-L136)).
   Duplicate messages are deduplicated; a changed `config` updates in place
   ([lines 79-103](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/discovery/__init__.py#L79-L103)).
4. HA's `hassio` integration receives it and starts a config flow — and this is the load-bearing
   line: the service string **is used directly as the integration domain**
   ([`hassio/discovery.py:125-140`](https://github.com/home-assistant/core/blob/e8864d5eef4868530d0dd53b3d02fae2a710a5cb/homeassistant/components/hassio/discovery.py#L125-L140)):

   ```python
   discovery_flow.async_create_flow(
       self.hass,
       data.service,
       context={"source": config_entries.SOURCE_HASSIO},
       data=HassioServiceInfo(config=data.config, name=addon_info.name, ...),
   )
   ```

   Removing the discovery message removes the matching config entry
   ([lines 142-161](https://github.com/home-assistant/core/blob/e8864d5eef4868530d0dd53b3d02fae2a710a5cb/homeassistant/components/hassio/discovery.py#L142-L161)).

**The consequence: Supervisor discovery only does anything if an integration with that exact domain
exists and implements `async_step_hassio`.** It is a pointer, not a payload — it carries a host and
port to an integration that already knows how to poll. There is no `blocky` domain in HA core, so a
`discovery: [blocky]` key on this add-on today would produce a flow for a nonexistent integration.

### 4.3 How rare it is

Across `home-assistant/addons` (the official set, 23 add-ons), **13** declare a `discovery:` key —
`vlc`, `samba`, `deconz`, `whisper`, `zwave_js`, `mosquitto`, `openwakeword`, `matter_server`,
`speech_to_phrase`, `assist_microphone`, `silabs-multiprotocol`, `openthread_border_router`, `piper`.
Each maps 1:1 to a core integration domain (`mosquitto` → `discovery: [mqtt]`, `matter_server` →
`discovery: [matter]`, `deconz` → `discovery: [deconz]`).

Across the entire `hassio-addons` community org (~90 repositories), `bashio::discovery` appears in
exactly **four** add-ons: `app-adguard-home` (`adguard`), `app-zwave-js-ui` (`zwave_js`),
`app-uptime-kuma` (`uptime_kuma`), `addon-motioneye` (`motioneye`) — plus bashio itself. Every one of
those four names an integration that exists in core.

---

## What this means for the open decision

Facts relevant to [#322](https://github.com/robocopklaus/hassio-addon-blocky/issues/322), without
recommendation:

1. **The field is empty.** No HACS integration, no working custom component, no forum thread, no
   shared YAML recipe, no gist. An operator installing this add-on today gets zero Home Assistant
   entities from any source, and nothing outside this repository is on a path to change that.
2. **There is no measured demand for entities specifically.** The three real asks that exist wanted
   (a) the add-on to exist at all — done; (b) Prometheus/Grafana; (c) in 2020, REST toggling of
   blocking from an external tool. Nobody has asked for query-count sensors or an is-DNS-up entity.
3. **The ecosystem norm for DNS service add-ons is the two-part split**: add-on posts host+port to
   Supervisor discovery, core integration owns the polling and the entities. AdGuard does exactly
   this; Pi-hole does the integration half without the discovery half. In neither case does the
   add-on publish entities.
4. **"Add-on publishes MQTT entities" is a real pattern with 360+ instances, but it lives in a
   different stratum** — protocol-bridge add-ons, none of them in the official or community-blessed
   repositories. Adopting it would put this add-on in the bridge category rather than the service
   category its peers occupy.
5. **Supervisor discovery is a named, officially supported mechanism that #322 has not yet
   considered — and it is inert on its own.** It only fires a config flow for an integration domain
   that already exists in core. Using it would require a `blocky` integration to exist somewhere
   (core or custom) for the discovery message to land in. It is not an alternative to writing an
   integration; it is the thing that makes an integration configure itself without the user typing
   an IP.
6. **The relevant docs are thin.** The `discovery:` key's entire official specification is one row of
   a table, and the anchor previously used to cite it (`/docs/add-ons/communication#services-discovery`)
   is dead after the add-ons→apps restructure. Any decision resting on this mechanism should cite
   source, not docs.

## Open questions

- Whether a `blocky` domain could be accepted into HA core (which would make `discovery: [blocky]`
  immediately useful) — this is a core-review question, not answerable from the artifacts searched
  here.
- What happens to a `discovery:` message whose service name matches no integration: the Supervisor
  stores and pushes it regardless, and `discovery_flow.async_create_flow` is called with an unknown
  domain. The failure mode was not traced to the point of knowing whether it logs, no-ops, or
  surfaces to the user.
- Whether `mqtt:want` with no broker installed produces a clean degradation — deferred to
  [#325](https://github.com/robocopklaus/hassio-addon-blocky/issues/325).
