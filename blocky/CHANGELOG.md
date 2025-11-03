# Changelog

## 2.0.0 (2025-11-04)

### 🎉 Automatic Migration from v1.0.0

**Good news!** If you're upgrading from v1.0.0, your configuration will be **automatically converted** to the new format. No manual migration required!

- ✅ **Zero downtime** - Add-on will start successfully with your existing settings
- ✅ **Zero configuration loss** - All your settings are preserved
- ✅ **Zero manual work** - Migration happens automatically during startup
- ⚠️ **Temporary compatibility** - Old configuration format will be supported for a transition period

When you upgrade:
1. The add-on detects your v1.0.0 configuration format
2. Automatically converts it to v2.0.0 format during startup
3. DNS service continues working with all your existing settings
4. You'll see a warning in logs: "Detected v1.0.0 configuration format - Automatically converting..."

**Recommendation**: When convenient, reconfigure via the Home Assistant UI to access new v2.0.0 features and remove the compatibility layer.

### Added

#### Enhanced Configuration Structure

The configuration schema has been restructured to a cleaner, more organized nested format that better aligns with Blocky's upstream configuration:

**Upstream DNS** - Now organized in groups with advanced strategies:
```yaml
# v2.0.0 format
upstreams:
  groups:
    - name: default
      resolvers:
        - tcp-tls:one.one.one.one
  init_strategy: blocking  # NEW: blocking|failOnError|fast
  strategy: parallel_best   # NEW: parallel_best|random|strict
  timeout: 2s               # NEW: configurable timeout
```

**Blocking & Filtering** - Consolidated under `blocking` namespace:
```yaml
# v2.0.0 format
blocking:
  denylists:             # Renamed from deny_lists
    - name: ads          # Renamed from group
      sources:           # Renamed from entries
        - https://...
  allowlists:            # NEW: whitelist functionality
    - name: exceptions
      sources: []
  client_groups_block:   # Nested under blocking
    - name: default      # Renamed from client
      lists:             # Renamed from groups
        - ads
  block_type: zeroIp     # NEW: zeroIp or nxDomain
  block_ttl: 6h          # NEW: configurable TTL
```

**Client Lookup** - Enhanced with name ordering and static mappings:
```yaml
# v2.0.0 format
client_lookup:
  upstream: "192.168.1.1"       # Was client_lookup_upstream
  single_name_order: []         # NEW: priority for multiple names
  clients: []                   # NEW: static client name mappings
```

**Conditional DNS** - Nested with rewriting support:
```yaml
# v2.0.0 format
conditional:
  mapping:                      # Was conditional_mapping
    - domain: fritz.box
      resolvers: ["192.168.178.1"]
  rewrite: []                   # NEW: domain rewriting
  fallback_upstream: false      # NEW: fallback behavior
```

**Bootstrap DNS** - Cleaner nested structure:
```yaml
# v2.0.0 format
bootstrap:
  dns:                          # Was bootstrap_dns
    - 1.1.1.1
```

#### New Features

**Query Filtering**
- Drop specific DNS query types (e.g., AAAA for IPv6)
- Useful for forcing IPv4 or filtering unwanted query types

**FQDN-Only Mode**
- Restrict resolution to fully qualified domain names only
- Prevents single-label hostname queries

**Custom DNS**
- Static hostname-to-IP mappings for local network
- Domain rewriting rules
- Configurable TTL for custom entries
- Filter unmapped query types

**Redis Integration**
- Distributed cache synchronization across multiple instances
- Configurable connection parameters
- Optional or required operation modes

**Enhanced Logging**
- Configurable log levels: trace, debug, info, warn, error
- Timestamp control
- Privacy mode to obfuscate sensitive data

**Prometheus Controls**
- Enable/disable metrics endpoint
- Custom metrics path configuration

**Upstream Enhancements**
- Multiple resolution strategies (parallel_best, random, strict)
- Configurable init strategy (blocking, failOnError, fast)
- Timeout configuration
- Custom User-Agent for DoH requests

### Changed

#### Default Values

⚠️ **IMPORTANT**: Caching defaults have changed in v2.0.0:

| Setting | v1.0.0 Default | v2.0.0 Default | Migration Behavior |
|---------|----------------|----------------|-------------------|
| `min_time` | `5m` | `0m` | **Preserved** as `5m` for v1.0.0 users |
| `max_time` | `30m` | `0m` | **Preserved** as `30m` for v1.0.0 users |
| `prefetching` | `true` | `false` | **Preserved** as `true` for v1.0.0 users |

**For v1.0.0 users upgrading**: Your caching settings are automatically preserved to maintain performance.

**For new v2.0.0 installations**: Caching is disabled by default (requires explicit configuration).

### BREAKING CHANGES (Automatically Handled)

#### Configuration Option Renaming

The following changes are **automatically migrated** for v1.0.0 users:

| v1.0.0 Option | v2.0.0 Option | Migration |
|---------------|---------------|-----------|
| `upstream_dns` (array) | `upstreams.groups` (nested) | ✅ Automatic |
| `bootstrap_dns` (array) | `bootstrap.dns` (nested) | ✅ Automatic |
| `deny_lists[].group` | `blocking.denylists[].name` | ✅ Automatic |
| `deny_lists[].entries` | `blocking.denylists[].sources` | ✅ Automatic |
| `client_groups_block[].client` | `blocking.client_groups_block[].name` | ✅ Automatic |
| `client_groups_block[].groups` | `blocking.client_groups_block[].lists` | ✅ Automatic |
| `conditional_mapping` | `conditional.mapping` | ✅ Automatic |
| `client_lookup_upstream` | `client_lookup.upstream` | ✅ Automatic |

#### Configuration Mapping Reference

For users who want to manually reconfigure in the UI (recommended when convenient):

**Upstream DNS**
```yaml
# v1.0.0
upstream_dns:
  - tcp-tls:one.one.one.one

# v2.0.0
upstreams:
  groups:
    - name: default
      resolvers:
        - tcp-tls:one.one.one.one
  init_strategy: blocking
  strategy: parallel_best
```

**Bootstrap DNS**
```yaml
# v1.0.0
bootstrap_dns:
  - 1.1.1.1

# v2.0.0
bootstrap:
  dns:
    - 1.1.1.1
```

**Deny Lists**
```yaml
# v1.0.0
deny_lists:
  - group: ads
    entries:
      - https://example.com/hosts

# v2.0.0
blocking:
  denylists:
    - name: ads
      sources:
        - https://example.com/hosts
  allowlists: []
  client_groups_block:
    - name: default
      lists:
        - ads
  block_type: zeroIp
  block_ttl: 6h
```

**Client Groups**
```yaml
# v1.0.0
client_groups_block:
  - client: default
    groups:
      - ads

# v2.0.0 (nested under blocking)
blocking:
  client_groups_block:
    - name: default
      lists:
        - ads
```

**Conditional Mapping**
```yaml
# v1.0.0
conditional_mapping:
  - domain: fritz.box
    resolvers:
      - 192.168.178.1

# v2.0.0
conditional:
  mapping:
    - domain: fritz.box
      resolvers:
        - 192.168.178.1
  rewrite: []
  fallback_upstream: false
```

**Client Lookup**
```yaml
# v1.0.0
client_lookup_upstream: "192.168.1.1"

# v2.0.0
client_lookup:
  upstream: "192.168.1.1"
  single_name_order: []
  clients: []
```

### Migration Verification

After upgrading to v2.0.0:

1. **Check logs** for the migration message:
   ```
   ════════════════════════════════════════════════════════
   Detected v1.0.0 configuration format
   Automatically converting to v2.0.0 format...
   Please reconfigure via UI when convenient to access new features
   ════════════════════════════════════════════════════════
   ```

2. **Verify DNS is working**:
   ```bash
   nslookup google.com <addon-ip>
   ```

3. **Check metrics** (if using Prometheus):
   ```bash
   curl http://<addon-ip>:4000/metrics
   ```

4. **When ready**, reconfigure via Home Assistant UI:
   - Open the Blocky add-on configuration
   - You'll see the new v2.0.0 schema with defaults
   - Re-enter your settings using the new format
   - Save and restart

### Troubleshooting

**Add-on fails to start after upgrade**
- Check logs for specific error messages
- Verify your v1.0.0 configuration was valid
- Report issue at https://github.com/robocopklaus/hassio-addon-blocky/issues

**DNS queries not being blocked**
- Verify your deny lists migrated correctly in logs
- Check that client group mappings are preserved
- Review configuration file at `/addon_config/<repository>_blocky/config.yml`

**Performance degradation**
- Check caching settings were preserved (should show `min_time: 5m`, `max_time: 30m`)
- If caching is disabled, re-enable in configuration

### Rollback Procedure

If you encounter issues, you can rollback to v1.0.0:

1. Stop the Blocky add-on
2. Go to Add-on Store → Blocky → version dropdown (⋮ menu)
3. Select version `1.0.0`
4. Start the add-on

Your v1.0.0 configuration will still be present and will work.

## 1.0.0 (2025-11-02)

### Added

#### Custom Configuration Mode

- New `custom_config` boolean option in add-on configuration
- When enabled, allows direct editing of Blocky configuration file at `/addon_config/<repository>_blocky/config.yml`
- Enables access to advanced Blocky features not exposed in the UI
- UI configuration options are ignored when custom mode is active

#### Default Configuration Improvements

- DNS caching now enabled by default (min: 5 minutes, max: 30 minutes, with prefetching)
- New "tracking" deny list group added to defaults
- Sensible bootstrap DNS defaults (1.1.1.1, 8.8.8.8)

#### Improved User Experience

- Configuration file now persisted and accessible for inspection
- Better error messages and logging for easier troubleshooting
- Complete English translations with detailed descriptions for all settings
- Health checks for monitoring addon status

### Changed

- **Blocky upgraded** to v0.27.0
- **Documentation expanded** with installation instructions and troubleshooting guide

### Removed

- **AppArmor profile** - container now runs with standard security
- **i386 architecture support** - no longer available
- **Prometheus UI configuration options** - metrics now always enabled (external port still configurable)

### Fixed

- License metadata corrected from "Apache License 2.0" to "MIT" (matching LICENSE file)

### BREAKING CHANGES

#### Configuration Schema Overhaul

All configuration options have been renamed to follow snake_case convention. **Existing configurations will not work and must be migrated.**

| Old Option (0.3.0) | New Option (1.0.0) |
|--------------------|-----------------------|
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

- Prometheus metrics now always enabled (cannot be disabled via UI)
- Internal container port is `4000` (external port mapping still configurable via Home Assistant UI)
- Default metrics endpoint: `http://<addon-ip>:4000/metrics`
- **Impact**: Users who need custom Prometheus configuration (path, settings) must use custom configuration mode

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

- Prometheus metrics are now **always enabled** (cannot be disabled)
- Internal container port: `4000` (external port mapping configurable via Home Assistant UI, defaults to `4000`)
- Default path: `/metrics`
- Default URL: `http://<addon-ip>:4000/metrics`
- You can change the external port mapping in Configuration → Network (e.g., map to `4001`)

If you need custom Prometheus configuration (custom path, settings):
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
- Verify port 4000 is exposed in addon configuration (Network section)
- Check firewall rules on your network
- Ensure add-on is running
- If you changed the external port mapping, use that port instead of 4000

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

## 0.3.0

See git history for previous release notes.
