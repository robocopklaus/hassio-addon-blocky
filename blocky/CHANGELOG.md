# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [3.0.0] - 2025-11-04

### Added

- Complete query logging system with multiple backend options:
  - CSV file logging with daily rotation
  - CSV-per-client logging (separate file per client)
  - Console logging (to add-on logs)
  - MySQL/MariaDB database logging
  - PostgreSQL database logging
  - Timescale database logging
- Query logging configuration: retention days, selectable log fields, flush intervals
- Structured bootstrap DNS configuration with optional IP overrides for DoT/DoH
- Advanced caching controls:
  - `max_items_count`: Limit total cached entries
  - Prefetch tuning: expires window, threshold, max items
  - Domain exclusion patterns (regex)
- Enhanced default blocklists (disconnect.me, sysctl.org for ads/tracking/malware)
- Watchdog health check at `/api/blocking/status` endpoint
- Comprehensive documentation improvements (README, DOCS, translations)

### Changed

- Bootstrap DNS format now uses structured objects instead of simple strings
- Configuration template reorganized for better logical flow

### Removed

- Automatic v1.0.0 to v2.0.0 migration code (no longer needed)

### Breaking Changes

**Bootstrap DNS format change**:
- Old format: `bootstrap: {dns: ["1.1.1.1", "8.8.8.8"]}`
- New format: `bootstrap: {dns: [{upstream: "1.1.1.1"}, {upstream: "8.8.8.8"}]}`
- Users with custom bootstrap DNS configurations must update to structured object format

## [2.0.0] - 2025-11-04

### Added

- Nested configuration schema for better organization and alignment with Blocky upstream
- Upstream DNS groups with multiple resolution strategies (parallel_best, random, strict)
- Configurable upstream init strategy (blocking, failOnError, fast) and timeout
- Query filtering support (drop specific DNS query types like AAAA)
- FQDN-only mode to restrict resolution to fully qualified domain names
- Custom DNS with static hostname-to-IP mappings and domain rewriting
- Redis integration for distributed cache synchronization
- Allowlists (whitelist functionality) for blocking exceptions
- Enhanced logging controls (levels, timestamp, privacy mode)
- Prometheus endpoint controls (enable/disable, custom path)
- Configurable block type (zeroIp, nxDomain) and TTL
- Client lookup enhancements (name ordering, static mappings)
- Conditional DNS fallback behavior and rewriting support

### Changed

- Caching defaults changed to disabled (was enabled in v1.0.0)
  - **Migration**: v1.0.0 users' cache settings are automatically preserved
- Configuration option naming restructured to nested format

### Breaking Changes

**Automatic migration from v1.0.0**: The add-on automatically converts v1.0.0 configurations to v2.0.0 format during startup. No manual migration required.

Configuration changes (all automatically migrated):
- `upstream_dns` → `upstreams.groups` (nested structure)
- `bootstrap_dns` → `bootstrap.dns`
- `deny_lists` → `blocking.denylists` (nested under `blocking`)
- `deny_lists[].group` → `blocking.denylists[].name`
- `deny_lists[].entries` → `blocking.denylists[].sources`
- `client_groups_block` → `blocking.client_groups_block`
- `client_groups_block[].client` → `blocking.client_groups_block[].name`
- `client_groups_block[].groups` → `blocking.client_groups_block[].lists`
- `conditional_mapping` → `conditional.mapping`
- `client_lookup_upstream` → `client_lookup.upstream`

## [1.0.0] - 2025-11-02

### Added

- Custom configuration mode for direct Blocky YAML editing
- DNS caching enabled by default (5-30 minutes with prefetching)
- "tracking" deny list group in defaults
- Bootstrap DNS defaults (1.1.1.1, 8.8.8.8)
- Persistent configuration file at `/addon_config/<repo>_blocky/config.yml`
- Health checks for monitoring
- Complete English translations with detailed descriptions

### Changed

- Blocky upgraded to v0.27.0
- Expanded documentation with installation and troubleshooting

### Removed

- AppArmor profile (now runs with standard security)
- i386 architecture support
- Prometheus UI configuration options (metrics always enabled, external port configurable)

### Fixed

- License metadata corrected to MIT (was Apache License 2.0)

### Breaking Changes

Configuration schema changed from camelCase to snake_case (manual migration required):
- `router` → `client_lookup_upstream`
- `defaultUpstreamResolvers` → `upstream_dns`
- `bootstrapDns` → `bootstrap_dns` (structure changed: simple IP array)
- `conditionalMapping` → `conditional_mapping` (structure changed: `ip` → `resolvers` array)
- `blackLists` → `deny_lists`
- `clientGroupsBlock` → `client_groups_block`
- All caching options renamed to snake_case

Additional breaking changes:
- Configuration file location: `/etc/blocky.yaml` → `/etc/blocky/config.yml`
- Container image path: `ghcr.io/robocopklaus/hassio-addon-blocky-{arch}` → `ghcr.io/robocopklaus/hassio-addon-blocky/{arch}`
- i386 architecture no longer supported

## [0.3.0] and earlier

See [git history](https://github.com/robocopklaus/hassio-addon-blocky/commits) for previous releases.

[Unreleased]: https://github.com/robocopklaus/hassio-addon-blocky/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/robocopklaus/hassio-addon-blocky/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/robocopklaus/hassio-addon-blocky/compare/v0.3.0...v1.0.0
[0.3.0]: https://github.com/robocopklaus/hassio-addon-blocky/releases/tag/v0.3.0
