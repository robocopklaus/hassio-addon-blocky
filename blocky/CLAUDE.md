# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Home Assistant Add-on** that packages [Blocky](https://github.com/0xERR0R/blocky) (v0.27.0) - a fast and lightweight DNS proxy with ad-blocking capabilities. The add-on provides a user-friendly interface for configuring Blocky within Home Assistant.

## Documentation References

When working on this project, always use the following resources:

- **Blocky Documentation**: Use the context7 MCP to fetch up-to-date Blocky reference documentation
- **Home Assistant Add-on Development**: Reference the official guide at https://developers.home-assistant.io/docs/add-ons/

## Key Architecture Components

### Configuration System

The add-on uses a dual-configuration approach:

1. **Standard Mode** (default): Configuration is generated from Home Assistant add-on options via Tempio templating
2. **Custom Config Mode**: Users can directly edit the Blocky configuration file

**Flow:**
- Home Assistant add-on options → `/data/options.json`
- Tempio template (`rootfs/usr/share/tempio/blocky.gtpl`) processes options
- Output: `/config/config.yml` (persistent, user-accessible)
- Copied to: `/etc/blocky/config.yml` (runtime location)
- Blocky reads from `/etc/blocky/config.yml`

**Init script:** `rootfs/etc/cont-init.d/config.sh`
- Checks `custom_config` flag
- In custom mode: preserves existing config if present, generates initial config on first run
- In standard mode: always regenerates from add-on options

### Startup Process

The add-on uses s6-overlay service management:

1. **Init phase** (`rootfs/etc/cont-init.d/config.sh`): Generates configuration
2. **Service phase** (`rootfs/etc/services.d/blocky/run`): Starts Blocky with pre-flight checks

### Container Architecture

- Base images: Home Assistant official base images (Alpine Linux 3.20)
- Multi-architecture support: amd64, armv7, aarch64, armhf
- Blocky binary downloaded from upstream releases with checksum verification
- Architecture mapping: `amd64→x86_64`, `armv7→armv7`, `aarch64→arm64`, `armhf→armv6`

## Configuration Schema

Key add-on options (defined in `config.yaml`):
- `upstream_dns`: Array of upstream DNS servers (supports tcp-tls, https)
- `bootstrap_dns`: Simple IP array for resolving DoH/DoT hostnames
- `deny_lists`: Array of objects with `group` and `entries` (URLs)
- `client_groups_block`: Array mapping clients to block groups
- `conditional_mapping`: Array with `domain` and `resolvers` fields
- `client_lookup`: Object controlling reverse DNS (`upstream`), name preference (`single_name_order`), and static mappings (`clients`)
- `caching`: Object with `min_time`, `max_time`, `prefetching`
- `custom_config`: Boolean to enable direct config file editing

## Development Commands

### Building the Add-on

```bash
# Build for local architecture (during development)
docker build --build-arg BUILD_ARCH=amd64 -t local/blocky .

# Test the container
docker run --rm -v $(pwd)/rootfs/usr/share/tempio:/usr/share/tempio local/blocky blocky version
```

### Testing Configuration Generation

```bash
# Test tempio template locally (requires tempio binary)
tempio -conf config.yaml -template rootfs/usr/share/tempio/blocky.gtpl -out test-config.yml
```

### Validating Configuration

The add-on has built-in validation in the service startup script. Configuration issues will appear in logs.

## Important Implementation Notes

### Tempio Template (`blocky.gtpl`)

- Uses Go template syntax
- Iterates over arrays with `{{- range .field_name }}`
- Conditional rendering with `{{- if .field }}`
- Whitespace control with `-` in template tags
- **Special handling**: `conditional_mapping` formats resolvers as comma-separated inline list

### bashio Integration

Scripts use `bashio` library for:
- Logging: `bashio::log.info`, `bashio::log.warning`, `bashio::log.fatal`
- Config access: `bashio::config.true 'field_name'`
- Shebang: `#!/usr/bin/with-contenv bashio`

### Port Configuration

- DNS: Port 53 TCP/UDP (exposed to host)
- HTTP API & Metrics: Port 4000 TCP (always enabled, used for health checks)
- Health check: `blocky blocking status` (30s interval)

### File Locations

- Add-on options: `/data/options.json` (Home Assistant managed)
- Persistent config: `/config/config.yml` (visible to users, maps to `/addon_config/<repository>_blocky/`)
- Runtime config: `/etc/blocky/config.yml` (Blocky reads from here)
- Data directory: `/data/blocky` (query logs, cache)
- Template: `/usr/share/tempio/blocky.gtpl`

## Version Management

- Blocky version: Defined in `Dockerfile` ARG `BLOCKY_VERSION` (currently v0.27.0)
- Tempio version: Defined in `Dockerfile` ARG `TEMPIO_VERSION` (currently 2024.11.2)
- Both use renovate bot comments for automated updates

## Breaking Changes from v0.3.0

Version 1.0.0 introduced major breaking changes:
- All config options renamed to snake_case convention
- Bootstrap DNS structure simplified (array of IPs instead of objects)
- Conditional mapping changed (`ip` → `resolvers` array)
- Configuration file location moved
- Prometheus always enabled (UI controls removed)
- i386 architecture support dropped

See `CHANGELOG.md` for complete migration guide.

## Security Considerations

- Checksum verification for all downloaded binaries (Blocky)
- No checksum for Tempio (from official Home Assistant org)
- AppArmor profile removed in v1.0.0 (standard container security)
- No secrets should be committed to repository
