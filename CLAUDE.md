# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Home Assistant Add-on repository for [Blocky](https://github.com/0xERR0R/blocky) (v0.27.0), a DNS proxy and ad-blocker. This wraps the pre-built Blocky Go binary in a Docker container with Home Assistant integration.

## Repository Structure

```
.
├── blocky/                   # Main add-on (see blocky/CLAUDE.md for details)
│   ├── config.yaml           # Add-on schema, defaults, HA integration
│   ├── Dockerfile            # Multi-arch container build
│   ├── rootfs/               # Container filesystem overlay
│   │   ├── etc/cont-init.d/config.sh      # Startup config generation
│   │   ├── etc/services.d/blocky/         # s6 service scripts (run, finish)
│   │   └── usr/share/tempio/blocky.gtpl   # Config template (~300 lines)
│   └── translations/en.yaml  # UI field descriptions
├── scripts/                  # Release utilities
└── .github/workflows/        # CI/CD (semantic release + Docker builds)
```

## Development Commands

### Local Docker Build

```bash
# Build for specific architecture (run from blocky/ directory)
docker build --build-arg BUILD_ARCH=amd64 -t blocky-addon ./blocky
docker build --build-arg BUILD_ARCH=aarch64 -t blocky-addon ./blocky
```

### Release (GitHub Actions)

Releases are triggered manually via GitHub Actions workflow dispatch:

```bash
# Dry run to preview version bump
pnpm run release:dry-run

# Actual release (use GitHub Actions, not locally)
# Workflow: .github/workflows/release.yml
```

The release workflow:
1. Runs semantic-release to determine version from conventional commits
2. Updates version in `blocky/config.yaml`
3. Builds and pushes multi-arch Docker images to GHCR
4. Creates GitHub release

### Testing Configuration

```bash
# Inside container: test template rendering
tempio -conf /data/options.json -template /usr/share/tempio/blocky.gtpl -out /tmp/config.yml

# Validate generated config
blocky --config /tmp/config.yml validate
```

## Key Development Patterns

### Commit Convention

Uses [Conventional Commits](https://www.conventionalcommits.org/) for automated versioning:
- `feat:` - Minor version bump
- `feat!:` or `BREAKING CHANGE:` - Major version bump
- `fix:` - Patch version bump
- `chore:`, `docs:`, `refactor:` - No version bump

### Configuration System

Two-mode configuration:
1. **Standard**: HA UI options → Tempio template (`blocky.gtpl`) → Blocky YAML
2. **Custom**: User provides complete YAML at `/addon_config/<repo>_blocky/config.yml`

When modifying configuration options:
1. Update schema in `blocky/config.yaml`
2. Update Tempio template in `blocky/rootfs/usr/share/tempio/blocky.gtpl`
3. Update UI descriptions in `blocky/translations/en.yaml`

### Shell Scripts

- Use `#!/usr/bin/with-contenv bashio` shebang
- Use `bashio::log.*` for logging
- Validate file existence before use

## External References

- **Blocky Config Reference**: https://0xerr0r.github.io/blocky/latest/configuration/
- **Home Assistant Add-on Dev**: https://developers.home-assistant.io/docs/add-ons/

## Detailed Add-on Documentation

See `blocky/CLAUDE.md` for:
- Multi-layer architecture diagram
- Configuration translation patterns
- File locations and runtime paths
- Security considerations
- Blocky DNS concepts
