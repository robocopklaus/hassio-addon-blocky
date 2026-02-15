# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Home Assistant Add-on** that wraps [Blocky](https://github.com/0xERR0R/blocky), a DNS proxy and ad-blocker written in Go. The add-on provides a containerized integration layer that makes Blocky easy to deploy and configure within the Home Assistant ecosystem.

- **Type**: Docker-based Home Assistant Add-on
- **Purpose**: Network-wide DNS-based ad blocking and privacy enhancement
- **Language**: Shell scripts (Bash) for integration; wraps a pre-built Go binary
- **Blocky Version**: Defined by `BLOCKY_VERSION` ARG in `Dockerfile`

## Development Commands

### Building the Add-on

```bash
# Build for specific architectures
docker build --build-arg BUILD_ARCH=amd64 -t blocky-addon .
docker build --build-arg BUILD_ARCH=aarch64 -t blocky-addon .
docker build --build-arg BUILD_ARCH=armv7 -t blocky-addon .
docker build --build-arg BUILD_ARCH=armhf -t blocky-addon .
```

### Testing Configuration Generation

```bash
# Test Tempio template rendering
tempio -conf /data/options.json -template rootfs/usr/share/tempio/blocky.gtpl -out config.yml

# Validate generated Blocky configuration
blocky --config config.yml validate

# Check Blocky version
blocky version

# Test blocking status API
curl http://localhost:4000/api/blocking/status
```

### Development Workflow

1. Edit add-on schema in `config.yaml`
2. Modify Tempio template in `rootfs/usr/share/tempio/blocky.gtpl`
3. Update init/service scripts in `rootfs/etc/cont-init.d/` or `rootfs/etc/services.d/blocky/`
4. Test locally with Docker or install in Home Assistant development environment
5. View logs: `docker logs <container_id>`

**Note**: This project has no traditional build system (no Makefile, npm, or Go compilation). It downloads pre-built Blocky binaries during Docker image build.

## Architecture

### Multi-Layer Design

```
┌─────────────────────────────────────────────────────────┐
│          Home Assistant Add-on Layer                    │
│  - config.yaml: Schema & UI definition                 │
│  - translations/en.yaml: UI text                       │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│         Configuration Translation Layer                 │
│  - blocky.gtpl: Tempio template                        │
│  - Converts HA config → Blocky YAML                    │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│         Initialization & Lifecycle Layer                │
│  - config.sh: Generate config on startup               │
│  - run: Start Blocky process                           │
│  - finish: Handle shutdown/crashes                     │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│              Blocky DNS Proxy (Go binary)               │
│  - DNS resolution with blocking                        │
│  - HTTP API (port 4000)                                │
└─────────────────────────────────────────────────────────┘
```

### Configuration System

The add-on supports **two modes**:

1. **Standard Mode**: User configures via Home Assistant UI. Options defined in `config.yaml` schema are transformed via Tempio template into Blocky YAML.

2. **Custom Config Mode**: User provides complete Blocky YAML in `/addon_config/<repo>_blocky/config.yml`. Template rendering is bypassed.

**Key insight**: The Tempio template (`blocky.gtpl`) is the bridge between HA's structured config and Blocky's YAML format. Understanding both config.yaml schema and Blocky's config structure is essential for modifications.

### File Locations

- `/etc/blocky/config.yml` - Runtime config location (where Blocky reads from)
- `/config/config.yml` - Persistent custom config (maps to `/addon_config/<repo>_blocky/`)
- `/data/options.json` - Home Assistant injects current add-on options here at startup
- `rootfs/usr/share/tempio/blocky.gtpl` - Template for config generation

## Key Files & Components

### Add-on Definition
- **`config.yaml`**: Defines add-on schema, defaults, validation rules, and Home Assistant integration
- **`translations/en.yaml`**: Rich descriptions for every config option shown in HA UI

### Configuration Generation
- **`rootfs/usr/share/tempio/blocky.gtpl`**: Go template that transforms Home Assistant config into Blocky YAML format

### Initialization Scripts (s6-overlay)
- **`rootfs/etc/cont-init.d/config.sh`**: Runs at container startup; generates Blocky config from template or validates custom config
- **`rootfs/etc/services.d/blocky/run`**: Starts Blocky process with generated config
- **`rootfs/etc/services.d/blocky/finish`**: Handles crashes and prevents restart loops

### Container
- **`Dockerfile`**: Multi-arch build that downloads Blocky binary with checksum verification

## Important Patterns

### Configuration Translation Pattern

The add-on translates Home Assistant's user-friendly config format into Blocky's native YAML:

- **Groups**: Upstreams, blocklists, and clients are organized into named groups
- **Strategies**: Users select strategies (e.g., "parallel_best", "strict") via dropdowns; template maps to Blocky enums
- **Conditional Logic**: Template includes extensive conditionals to handle optional features
- **Type Conversions**: Template handles string→int, boolean flags, and structured data transformations

### Shell Script Conventions

- Use `bashio` library for logging and config access
- All scripts use `#!/usr/bin/with-contenv bashio` shebang
- Extensive validation before starting services (check file existence, readability, non-empty content)
- Defensive programming throughout

### Security Patterns

- Passwords marked as `password` type in schema (encrypted in HA UI)
- Passwords written to Blocky config in plaintext (required by Blocky)
- Container isolation provides file system protection
- No internet-facing exposure required

## Blocky DNS Concepts

Understanding Blocky's layered DNS resolution architecture is crucial:

1. **Client Lookup**: Identifies requesting client
2. **Custom DNS**: Local domain name resolution
3. **Conditional Resolution**: Per-domain upstream routing
4. **Blocking/Allowlist**: Ad-blocking and whitelist evaluation
5. **Upstream Forwarding**: Query upstream DNS servers (with DoT/DoH support)

Blocky supports:
- Multiple upstream strategies (parallel, random, strict)
- Redis integration for multi-instance clustering
- Query logging to CSV, MySQL, PostgreSQL
- Prometheus metrics at `/metrics`

## Testing

**No automated testing infrastructure exists.** Testing is manual:

1. Install add-on in Home Assistant (dev or production)
2. Configure via UI or custom YAML
3. Check logs for errors
4. Verify DNS resolution works
5. Test blocking via API: `curl http://[HOST]:4000/api/blocking/status`

## External Documentation

**This add-on is a wrapper around Blocky.** Always consult the upstream Blocky configuration reference as the primary source of truth:

- **Blocky Configuration Reference**: https://0xerr0r.github.io/blocky/latest/configuration/ (permitted for WebFetch)
- **Blocky Official Docs**: https://0xerr0r.github.io/blocky/
- **Home Assistant Add-on Development**: https://developers.home-assistant.io/docs/add-ons/

Since this add-on translates Home Assistant config into Blocky's native YAML format, understanding Blocky's configuration structure is essential for modifications to `config.yaml` or `blocky.gtpl`.
