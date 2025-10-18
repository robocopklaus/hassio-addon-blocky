# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Home Assistant add-on for Blocky, a DNS proxy and ad-blocker. The add-on wraps the upstream Blocky project (0xERR0R/blocky) and provides integration with Home Assistant's supervisor architecture.

## Architecture

### Directory Structure

- `blocky/` - The main add-on directory
  - `config.yaml` - Home Assistant add-on configuration (metadata, default options, schema)
  - `build.yaml` - Multi-architecture build configuration
  - `Dockerfile` - Container build instructions
  - `rootfs/` - Files copied into the container filesystem
    - `etc/cont-init.d/config.sh` - Initialization script that generates Blocky config using tempio
    - `etc/services.d/blocky/run` - Service startup script
    - `etc/services.d/blocky/finish` - Service cleanup/restart handler
    - `usr/share/tempio/blocky.gtpl` - Go template for Blocky configuration
  - `translations/` - i18n files for Home Assistant UI

### Configuration Flow

1. User configures add-on via Home Assistant UI (settings defined in `config.yaml`)
2. On startup, `/etc/cont-init.d/config.sh` runs and uses tempio to render `blocky.gtpl` template with user options from `/data/options.json`
3. Generated config is written to `/etc/blocky.yaml`
4. Blocky binary starts via `/etc/services.d/blocky/run` using the generated config

### Key Technical Details

- Uses s6-overlay for process supervision (Home Assistant standard)
- Configuration is dynamically generated from a Go template (`blocky.gtpl`), not static
- The add-on installs Blocky v0.25 from Alpine edge/community repository
- Supports 5 architectures: armhf, armv7, aarch64, amd64, i386

## Development Commands

### Linting

```bash
# Lint add-on configuration (requires Home Assistant action-addon-linter)
# This is normally run in CI via .github/workflows/lint.yaml
```

Note: Linting typically requires the `frenck/action-addon-linter` GitHub Action and is run automatically in CI.

### Building

The add-on uses Home Assistant Builder for multi-architecture builds:

```bash
# Build for specific architecture (normally done in CI)
# Uses home-assistant/builder@2025.09.0 GitHub Action
# Example for local testing:
docker build --build-arg BUILD_FROM="ghcr.io/home-assistant/amd64-base:3.20" -f blocky/Dockerfile blocky/
```

### Testing Locally

To test the add-on locally in Home Assistant:

1. Add this repository URL to Home Assistant: Supervisor → Add-on Store → ⋮ → Repositories
2. Install the add-on from the store
3. Configure via the Configuration tab
4. Start the add-on and check logs

### CI/CD

- `.github/workflows/lint.yaml` - Runs Home Assistant add-on linter on push/PR
- `.github/workflows/builder.yaml` - Builds multi-arch images and pushes to ghcr.io
  - Only builds add-ons where monitored files changed: `build.yaml`, `config.yaml`, `Dockerfile`, `rootfs`
  - Builds test images on PRs, production images on main branch pushes

## Configuration Schema

The add-on configuration is defined in `blocky/config.yaml`:

- `router` - IP address of router for client lookups (reverse DNS)
- `defaultUpstreamResolvers` - List of upstream DNS servers (supports DoH/DoT)
- `bootstrapDns` - DNS servers to resolve upstream DoH/DoT hostnames
- `conditionalMapping` - Domain-specific DNS routing
- `blackLists` - Block lists organized by groups (ads, malware, etc.)
- `clientGroupsBlock` - Maps client IPs to blocking groups
- `caching` - DNS cache settings (TTL, prefetching, etc.)

## Dependency Management

### Renovate Bot

This repository uses Renovate Bot for automated dependency updates. Renovate is configured via `renovate.json` and handles:

- **Alpine APK packages** - Tracks blocky package version in Dockerfile using Repology datasource
- **GitHub Actions** - Auto-updates workflow actions (patch updates auto-merge)
- **Home Assistant components** - Groups base images and builder updates
- **Tempio version** - Tracks releases from home-assistant/tempio

**How it works:**
1. Renovate runs on schedule (evenings/weekends)
2. Detects new versions via configured datasources
3. Creates PRs automatically with version bumps
4. CI runs tests on the PR
5. Review and merge (or auto-merge for patches)

**To manually trigger a check:** Re-run the Renovate workflow in GitHub Actions

### Updating Configuration Options

1. Modify `blocky/config.yaml` - update `options`, `schema`, or both
2. Update `blocky/rootfs/usr/share/tempio/blocky.gtpl` to use new options
3. Test configuration generation by installing add-on locally

### Updating Blocky Version

**Automated (Recommended):** Renovate will create a PR when a new version is available in Alpine edge/community.

**Manual:** Edit `blocky/Dockerfile` line 13 to change the version:
```dockerfile
# renovate: datasource=repology depName=alpine_edge/blocky versioning=loose
RUN apk add --no-cache --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community blocky=X.XX-rX
```

**Important:** Keep the `# renovate:` comment on line 12 for automated tracking to work.

### Modifying Startup/Init Scripts

- Edit files in `blocky/rootfs/etc/`
- Scripts use bashio for Home Assistant integration (logging, config access)
- Must be executable and use shebang `#!/usr/bin/with-contenv bashio`

## Important Notes

- The add-on version in `config.yaml` should be updated when making changes
- CI automatically builds and pushes images to `ghcr.io/robocopklaus/hassio-addon-blocky-{arch}`
- The tempio template syntax is Go template format
- DNS port 53 (TCP/UDP) is exposed and mapped by default
