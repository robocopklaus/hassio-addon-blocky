# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Home Assistant Add-on wrapping [Blocky](https://github.com/0xERR0R/blocky), a DNS proxy and ad-blocker in Go. The add-on is a containerized integration layer: shell scripts + Tempio templates that translate Home Assistant config into Blocky's native YAML. No Go compilation — pre-built binaries are downloaded during Docker build.

Blocky version is pinned via `BLOCKY_VERSION` ARG in `blocky/Dockerfile`.

## Development Commands

```bash
# Build (from repo root)
docker build --build-arg BUILD_ARCH=amd64 -t blocky-addon blocky

# Lint (matches CI)
hadolint blocky/Dockerfile
shellcheck blocky/rootfs/etc/cont-init.d/*.sh blocky/rootfs/etc/services.d/blocky/*

# Release (semantic-release via pnpm)
pnpm release:dry-run    # preview what would be released
pnpm release            # create release (CI runs this via workflow_dispatch)

# Inside a running container — test template rendering
tempio -conf /data/options.json -template /usr/share/tempio/blocky.gtpl -out /etc/blocky/config.yml
blocky validate --config /etc/blocky/config.yml
curl http://localhost:4000/api/blocking/status
```

## Architecture

```
User configures in HA UI
        ↓
blocky/config.yaml          — schema, defaults, validation rules
blocky/translations/en.yaml — UI field descriptions
        ↓
blocky/rootfs/usr/share/tempio/blocky.gtpl  — Go/Tempio template: HA options → Blocky YAML
        ↓
blocky/rootfs/etc/cont-init.d/config.sh     — runs template (or copies custom config)
blocky/rootfs/etc/services.d/blocky/run     — starts Blocky with generated config
blocky/rootfs/etc/services.d/blocky/finish  — handles crashes, prevents restart loops
        ↓
Blocky binary (DNS on :53, HTTP API on :4000)
```

### Two Configuration Modes

1. **Standard Mode**: HA UI options (defined in `blocky/config.yaml`) are rendered through `blocky.gtpl` into Blocky YAML at `/etc/blocky/config.yml`.
2. **Custom Config Mode**: User places a complete Blocky YAML at `/addon_config/<repo>_blocky/config.yml` (maps to `/config/config.yml` inside container). Template rendering is bypassed entirely.

### Configuration Translation (the core complexity)

The Tempio template (`blocky/rootfs/usr/share/tempio/blocky.gtpl`) is the bridge between HA's structured config and Blocky's YAML. When modifying config options, you must update three files in lockstep:

1. `blocky/config.yaml` — add/modify the schema field
2. `blocky/rootfs/usr/share/tempio/blocky.gtpl` — add template logic to emit the corresponding Blocky YAML
3. `blocky/translations/en.yaml` — add UI description

The template handles groups (upstreams, blocklists, clients), strategy enums, conditionals for optional features, and type conversions (string-to-int, booleans, structured data).

### Runtime File Locations (inside container)

- `/etc/blocky/config.yml` — runtime config (Blocky reads this)
- `/config/config.yml` — persistent custom config
- `/data/options.json` — HA injects add-on options here at startup

### Dev Addon (`blocky-dev/`)

`blocky-dev/` is **CI-generated** — do not edit manually. The `Deploy Dev` workflow (`.github/workflows/deploy-dev.yml`) syncs `blocky/` into `blocky-dev/` on every push to main that touches `blocky/**`. It patches `config.yaml` to use a different slug (`blocky_dev`), name (`Blocky (Dev)`), version (`dev-<SHA>`), and removes the `image` field so HA builds locally from the Dockerfile. Ports are the same as stable (53, 4000) — only one addon can run at a time.

### Shell Script Conventions

- Shebang: `#!/usr/bin/with-contenv bashio`
- Use `bashio` library for logging (`bashio::log.info`) and config access
- Validate file existence, readability, and non-empty content before using

## CI/CD & Release Pipeline

- **Linting** (`.github/workflows/lint.yml`): Hadolint on `blocky/Dockerfile`, ShellCheck on `blocky/rootfs/` — runs on push/PR to main
- **Release** (`.github/workflows/release.yml`): manual trigger (`workflow_dispatch`) → semantic-release → multi-arch Docker build (amd64, aarch64, armv7, armhf) → push to GHCR
- **Versioning**: `scripts/update-addon-version.mjs` is called by semantic-release to stamp the version into `blocky/config.yaml`
- **Commits**: conventional commits (`feat:` → minor, `fix:` → patch, `feat(deps):` for Blocky updates, `fix(deps):` for Tempio)
- **Dev Deploy** (`.github/workflows/deploy-dev.yml`): push to main touching `blocky/**` → syncs `blocky-dev/` with patched config → commits back to main with `[skip ci]`
- **Renovate** (`renovate.json`): auto-updates Blocky, Tempio, base images, and semantic-release packages. Patches auto-merge; Blocky bumps require manual review.

## Testing

No automated tests. Testing is manual: install in Home Assistant, configure, check logs, verify DNS resolution, test API at `http://[HOST]:4000/api/blocking/status`.

## External Documentation

Always consult upstream Blocky docs as the source of truth for config options:

- **Blocky Configuration Reference**: https://0xerr0r.github.io/blocky/latest/configuration/ (permitted for WebFetch)
- **Blocky Official Docs**: https://0xerr0r.github.io/blocky/
- **Home Assistant Add-on Development**: https://developers.home-assistant.io/docs/add-ons/
