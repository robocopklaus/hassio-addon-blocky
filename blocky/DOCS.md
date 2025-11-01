# Home Assistant Add-on: Blocky

Blocky is a fast DNS proxy and ad blocker. The add-on ships sensible defaults while letting you override any Blocky configuration value.

## Installation

1. Add `https://github.com/robocopklaus/hassio-addon-blocky` as a custom repository via *Settings → Add-ons → Add-on Store*.
2. Install **Blocky**, review the permissions, and click **Install**.
3. Start the add-on and (optionally) enable “Start on boot” and “Watchdog”.

## Configuration

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `upstream_dns` | list[str] | Cloudflare + Google | Upstream resolvers. Supports `tcp-tls:` and `https://` URIs. |
| `bootstrap_dns` | list[str] | `["1.1.1.1","8.8.8.8"]` | Plain DNS servers used before DoT/DoH upstreams are reachable. |
| `deny_lists` | list[object] | ads + tracking | URL collections Blocky downloads and combines. |
| `client_groups_block` | list[object] | default → ads/tracking | Defines which deny list groups apply to which client labels. |
| `conditional_mapping` | list[object] | empty | Per-domain overrides that forward requests to dedicated resolvers. |
| `client_lookup_upstream` | string | `""` | Optional resolver used to reverse-lookup client IPs. |
| `caching` | object | see `config.yaml` | Controls cache TTLs and prefetching. |
| `custom_config` | bool | `false` | When true, mount your own `/config/blocky/config.yml`. |

All schema details live in `blocky/config.yaml`; every change documented there automatically propagates via the changelog.

## Updating

- Track user-facing changes under `blocky/CHANGELOG.md`. Releases are tagged `v<semver>`.
- When a new version appears, update add-ons from *Settings → Add-ons → Blocky → Reinstall* or wait for Supervisor to update automatically.

## Troubleshooting

- Use “Open web UI” or connect to `http://<host>:4000` for health metrics.
- Enable “Watchdog” so Home Assistant restarts the add-on if the container exits.
- Check `/config/blocky/` for any custom configuration you mounted if Blocky refuses to start.
