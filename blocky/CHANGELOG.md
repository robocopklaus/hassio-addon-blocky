## 1.0.0 (2025-11-02)

### ⚠ BREAKING CHANGES

* Complete configuration schema overhaul for 1.0.0 release

Configuration Changes:
  - Rename all options to snake_case (router → client_lookup_upstream, etc.)
  - Simplify bootstrap_dns structure (object format → simple IP list)
  - Restructure conditional_mapping (ip field → resolvers array)
  - Remove Prometheus config from UI (hardcoded to port 4000)
  - Move config file location (/etc/blocky.yaml → /etc/blocky/config.yml)

Features:
  - Add custom_config mode for direct Blocky configuration editing
  - Add configuration persistence at /addon_config/ for user access
  - Add pre-flight validation and health checks
  - Add comprehensive English translations with detailed descriptions
  - Add caching enabled by default (min: 5m, max: 30m)
  - Add "tracking" deny list group to defaults

Technical Improvements:
  - Change Blocky installation from Alpine APK to GitHub release binary
  - Upgrade Blocky to v0.27.0 with SHA256 verification
  - Replace Dependabot with Renovate Bot for dependency management
  - Add semantic-release workflow for automated versioning
  - Add multi-arch builds with proper manifest creation
  - Add health check using blocky blocking status
  - Remove i386 architecture support
  - Remove AppArmor profile

Documentation:
  - Add comprehensive CHANGELOG.md with migration guide
  - Add RELEASE_NOTES_1.0.0.md for GitHub Release
  - Add CLAUDE.md for AI assistant project guidance
  - Add LICENSE file (MIT)
  - Expand README.md (79 → 183 lines) with installation and troubleshooting
  - Simplify DOCS.md (187 → 35 lines) focusing on essentials

CI/CD:
  - Replace builder.yaml, lint.yaml with release.yml workflow
  - Add semantic-release integration
  - Add manual workflow dispatch with dry-run support

See CHANGELOG.md for complete migration guide from 0.3.0 to 1.0.0.

### Features

* add caching configuration support ([ac3cf6e](https://github.com/robocopklaus/hassio-addon-blocky/commit/ac3cf6e1f0347b823173671003fedc278b05636f))
* add Prometheus metrics support and update version to 0.3.0 ([#43](https://github.com/robocopklaus/hassio-addon-blocky/issues/43)) ([cf9f5d3](https://github.com/robocopklaus/hassio-addon-blocky/commit/cf9f5d3c41dc8ba6d5c206da506693f724ba04c8))
* add script to update Blocky configuration version ([#46](https://github.com/robocopklaus/hassio-addon-blocky/issues/46)) ([a417032](https://github.com/robocopklaus/hassio-addon-blocky/commit/a41703294cf8d8585a0cce732a698b08b5ce5c83))
* release v1.0.0 with custom config mode and breaking changes ([#45](https://github.com/robocopklaus/hassio-addon-blocky/issues/45)) ([c974cf7](https://github.com/robocopklaus/hassio-addon-blocky/commit/c974cf7cf0e892b0a1955cf6c76a764be423e485))

### Bug Fixes

* update blocky to 0.24 ([c388284](https://github.com/robocopklaus/hassio-addon-blocky/commit/c3882848876ac8c2852b7a71e47d3c52da113742))
* update regex in renovate.json for blocky dependency matching ([#40](https://github.com/robocopklaus/hassio-addon-blocky/issues/40)) ([583a09e](https://github.com/robocopklaus/hassio-addon-blocky/commit/583a09e98bb8a01ade3eb54cf6b107c5909a2624))

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - Unreleased

### BREAKING CHANGES

#### Configuration Schema Overhaul

All configuration options have been renamed to follow snake_case convention. **Existing configurations will not work and must be migrated.**

| Old Option (0.3.0) | New Option (1.0.0) |
|--------------------|--------------------|
| `router` | `client_lookup_upstream` |
| `defaultUpstreamResolvers` | `upstream_dns` |
| `bootstrapDns` | `bootstrap_dns` |
| `conditionalMapping` | `conditional_mapping` |
| `blackLists` | `deny_lists` |
| `clientGroupsBlock` | `client_groups_block` |
| `caching.minTime` | `caching.min_time` |
| `caching.maxTime` | `caching.max_time` |
| `caching.maxItemsCount` | `caching.max_items_count` |
| `caching.cacheTimeNegative` | `caching.cache_time_negative` |

#### Bootstrap DNS Structure Changed

- **Old format**: Array of objects with `upstream` and `ips` fields
  ```yaml
  bootstrapDns:
    - upstream: "tcp+udp:1.1.1.1"
      ips: ["1.1.1.1", "1.0.0.1"]
  ```

- **New format**: Simple array of IP addresses
  ```yaml
  bootstrap_dns:
    - "1.1.1.1"
    - "8.8.8.8"
  ```

#### Conditional Mapping Structure Changed

- **Old format**: `domain` and `ip` fields
  ```yaml
  conditionalMapping:
    - domain: "example.com"
      ip: "192.168.1.1"
  ```

- **New format**: `domain` and `resolvers` (array) fields
  ```yaml
  conditional_mapping:
    - domain: "example.com"
      resolvers:
        - "192.168.1.1"
        - "192.168.1.2"
  ```

#### Prometheus Configuration Changes

- Prometheus configuration options removed from Home Assistant UI
- HTTP API port hardcoded to `4000` and always exposed
- Metrics endpoint: `http://<addon-ip>:4000/metrics`
- **Impact**: Users who customized Prometheus port or path must use custom configuration mode

#### Architecture Support Changes

- **Removed**: i386 architecture support
- **Changed**: Container image naming scheme
  - Old: `ghcr.io/robocopklaus/hassio-addon-blocky-{arch}`
  - New: `ghcr.io/robocopklaus/hassio-addon-blocky/{arch}`
- **Impact**: Users on i386 systems cannot upgrade

#### Configuration File Location Changed

- **Old path**: `/etc/blocky.yaml`
- **New path**: `/etc/blocky/config.yml`
- Configuration now persisted at `/addon_config/<repository>_blocky/config.yml`
- **Impact**: Custom mounted configurations at old path will not work

#### AppArmor Profile Removed

- `apparmor.txt` deleted - container now runs without AppArmor confinement
- **Impact**: Different security profile (less restrictive)

### Added

#### Custom Configuration Mode

- New `custom_config` boolean option in add-on configuration
- When enabled, allows direct editing of Blocky configuration file
- Configuration file location: `/addon_config/<repository>_blocky/config.yml`
- Enables access to advanced Blocky features not exposed in the UI
- UI configuration options ignored when custom mode is active

#### Enhanced Configuration Management

- Configuration file persisted for user editing and inspection
- Automatic mode detection (custom vs. managed)
- Pre-flight validation checks on service startup
- Configuration logged on startup for debugging purposes
- Health check added to Dockerfile using `blocky blocking status`

#### Default Configuration Improvements

- DNS caching enabled by default:
  - `min_time`: 5 minutes
  - `max_time`: 30 minutes
  - `prefetching`: enabled
- New "tracking" deny list group added to defaults
- HTTP API port (4000) always exposed for health checks and Prometheus metrics
- Sensible bootstrap DNS defaults (1.1.1.1, 8.8.8.8)

#### Comprehensive Translations

- Complete English translations with detailed descriptions
- Multi-line help text for each configuration option
- Clear warnings about custom config mode behavior

### Changed

#### Blocky Installation Method

- **Changed**: Installation method from Alpine APK package to direct GitHub release binary
- Blocky version upgraded to v0.27.0
- SHA256 checksum verification for downloaded binaries
- Support for exact version pinning via Renovate Bot
- Automatic architecture detection and binary download

#### Service Management Improvements

- Enhanced exit code handling in finish script
- Distinguishes between clean shutdown and crash scenarios
- Pre-flight configuration checks before starting Blocky
- Better error messages and logging
- Configuration validation on startup

#### CI/CD Pipeline Modernization

- Replaced GitHub Dependabot with Renovate Bot for dependency management
- New semantic-release integration for automated versioning and releases
- Multi-architecture image builds with proper manifest creation
- Manual workflow dispatch for controlled releases
- Dry-run support for testing release process
- Image scanning workflow for security

#### Documentation Overhaul

- `DOCS.md` simplified and focused (187 lines → 35 lines)
- `README.md` significantly expanded with comprehensive information (79 lines → 183 lines)
- Added installation instructions, troubleshooting guide, API usage examples
- Added `CLAUDE.md` for AI assistant project guidance

#### Build Process Improvements

- Dockerfile downloads Blocky binary directly from GitHub releases
- Checksum verification for security
- Added OCI labels for container metadata
- Health check using `blocky blocking status`
- Explicit Tempio version tracking with Renovate

#### Dependency Management

- Configured Renovate Bot for automated dependency updates:
  - Alpine APK packages tracking (via Repology datasource)
  - GitHub Actions auto-updates with patch auto-merge
  - Home Assistant base images and builder updates
  - Tempio version tracking
- Automatic PR creation for dependency updates
- Scheduled checks (evenings/weekends)

### Removed

- **Workflows**: Deleted `builder.yaml`, `lint.yaml`, and `dependabot.yaml`
- **AppArmor**: Removed `apparmor.txt` security profile
- **Architecture**: Dropped i386 support
- **UI Options**: Prometheus configuration removed from Home Assistant UI
- **Incomplete Documentation**: Removed partial Prometheus/Grafana integration section from DOCS.md

### Fixed

- License metadata corrected from "Apache License 2.0" to "MIT" (matching LICENSE file)

---

## Migration Guide: 0.3.0 → 1.0.0

### Prerequisites

1. **Backup your current configuration** via Home Assistant UI or by copying `/addon_config/` directory
2. **Note your current settings** - you'll need to re-enter them
3. **Check architecture compatibility** - i386 users cannot upgrade

### Migration Steps

#### Step 1: Update Configuration Options

After upgrading, you'll need to reconfigure the add-on. Use this mapping table to translate your old settings:

**Basic DNS Settings:**
- `router` → `client_lookup_upstream` (same value)
- `defaultUpstreamResolvers` → `upstream_dns` (same array format)

**Bootstrap DNS:**
- Extract IP addresses from your old `bootstrapDns` configuration
- Enter as simple list in `bootstrap_dns`

**Example:**
```yaml
# OLD (0.3.0)
bootstrapDns:
  - upstream: "tcp+udp:1.1.1.1"
    ips: ["1.1.1.1", "1.0.0.1"]

# NEW (1.0.0)
bootstrap_dns:
  - "1.1.1.1"
  - "1.0.0.1"
```

**Conditional Mapping:**
- Rename `conditionalMapping` → `conditional_mapping`
- Change structure: `ip` field becomes `resolvers` array

**Example:**
```yaml
# OLD (0.3.0)
conditionalMapping:
  - domain: "home.local"
    ip: "192.168.1.1"

# NEW (1.0.0)
conditional_mapping:
  - domain: "home.local"
    resolvers:
      - "192.168.1.1"
```

**Deny Lists (Block Lists):**
- Rename `blackLists` → `deny_lists`
- Group names remain the same
- URLs remain the same

**Client Groups:**
- Rename `clientGroupsBlock` → `client_groups_block`
- Format remains the same

**Caching:**
- Rename all caching options using snake_case (see table above)
- Values remain the same

#### Step 2: Handle Prometheus Configuration

If you previously configured Prometheus settings:

- Prometheus endpoint is now **always available** at port 4000
- Default path: `/metrics`
- URL: `http://<addon-ip>:4000/metrics`

If you need custom Prometheus configuration:
1. Enable `custom_config` option in add-on settings
2. Edit `/addon_config/<repository>_blocky/config.yml` directly
3. Add custom `prometheus` section following [Blocky documentation](https://0xerr0r.github.io/blocky/latest/configuration/)

#### Step 3: Verify Architecture Compatibility

Check your Home Assistant system architecture:
```bash
ha host info
```

**Supported architectures in 1.0.0:**
- ✅ armhf
- ✅ armv7
- ✅ aarch64
- ✅ amd64
- ❌ i386 (removed)

If you're on i386, you cannot upgrade to 1.0.0.

#### Step 4: Upgrade Add-on

1. Navigate to Supervisor → Add-on Store → Blocky
2. Click "Update"
3. Wait for image download and installation
4. **Do not start yet** - reconfigure first

#### Step 5: Reconfigure Add-on

1. Go to Configuration tab
2. Enter your settings using the new option names (see Step 1 mapping)
3. Review all settings carefully
4. Save configuration

#### Step 6: Start and Verify

1. Start the add-on
2. Check logs for any errors: `Logs` tab or `ha addons logs blocky`
3. Verify DNS resolution: `nslookup google.com <addon-ip>`
4. Check Prometheus metrics: `curl http://<addon-ip>:4000/metrics`

#### Step 7: Update Client DNS Settings (if needed)

Due to potential container recreation, verify your clients are still pointing to the correct add-on IP address.

### Alternative: Custom Configuration Mode

If you prefer to maintain full control or use advanced Blocky features:

1. Enable `custom_config` option in add-on settings
2. Edit configuration file at `/addon_config/<repository>_blocky/config.yml`
3. Use [official Blocky configuration documentation](https://0xerr0r.github.io/blocky/latest/configuration/)
4. All UI options will be ignored in this mode

### Troubleshooting

**Add-on won't start after upgrade:**
- Check logs for configuration errors
- Verify all required options are filled
- Ensure no old configuration file exists at `/etc/blocky.yaml`

**DNS not resolving:**
- Verify upstream DNS servers are reachable
- Check bootstrap DNS is configured correctly
- Review logs for upstream connection errors

**Metrics endpoint not accessible:**
- Verify port 4000 is exposed (should be automatic)
- Check firewall rules
- Ensure add-on is running

**Need old configuration format:**
- Downgrade to 0.3.0 (not recommended)
- Or use custom config mode with manual migration

### Rollback Plan

If you need to rollback:

1. Stop the add-on
2. Go to Add-on Store → Blocky → version dropdown
3. Select version 0.3.0
4. Restore your old configuration from backup
5. Start the add-on

**Note**: After rollback, you'll need to reconfigure if you've already entered new settings.

---

## [0.3.0] - Previous Release

See git history for previous release notes.
