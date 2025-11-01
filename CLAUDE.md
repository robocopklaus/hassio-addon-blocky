# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Home Assistant add-on repository that packages [Blocky](https://github.com/0xERR0R/blocky) as a containerized add-on. Blocky is a DNS proxy and ad-blocker that provides network-wide ad blocking, custom DNS resolution, and support for modern DNS protocols (DoH/DoT).

## Repository Structure

- **blocky/**: The add-on itself (Dockerfile, config, rootfs, templates)
- **scripts/**: Automation scripts for version management
- **.github/workflows/**: CI/CD workflow for releases
- **Root-level files**: Package.json, semantic-release configuration, and Renovate configuration

## Common Commands

### Development & Testing

```bash
# Install dependencies (for semantic-release)
pnpm install

# Test semantic-release (dry-run)
pnpm run release:dry-run

# Build Docker image locally (replace amd64 with target architecture)
docker build --build-arg BUILD_FROM="ghcr.io/home-assistant/amd64-base:3.20" \
             --build-arg BUILD_ARCH="amd64" \
             --file blocky/Dockerfile \
             -t local/blocky-addon blocky

# Run container locally for testing
docker run --rm \
  -p 53:53/tcp -p 53:53/udp -p 4000:4000 \
  -v $(pwd)/test-options.json:/data/options.json \
  local/blocky-addon

# Check health endpoint
curl http://localhost:4000/api/health
```

### Release Process

Releases are managed by **semantic-release** using conventional commits:

```bash
# Trigger release via GitHub Actions (manual workflow)
# Go to Actions → Release Blocky → Run workflow

# Dry-run locally
pnpm run release:dry-run
```

**Conventional Commit Types:**
- `feat:` → Minor version bump (new features)
- `fix:` → Patch version bump (bug fixes)
- `BREAKING CHANGE:` → Major version bump
- `chore:`, `docs:`, `refactor:` → No version bump

## Architecture

### Release & Version Management

The repository uses **semantic-release** to automate versioning and releases:

1. **Commit Analysis**: Analyzes commits since last release using conventional commits
2. **Version Update**: `scripts/update-addon-version.mjs` updates `blocky/config.yaml`
3. **Changelog Generation**: Updates `blocky/CHANGELOG.md`
4. **Git Commit**: Commits version changes with `[skip ci]` tag
5. **GitHub Release**: Creates GitHub release with notes
6. **Docker Build**: Workflow builds and pushes multi-arch images to GHCR

**Configuration**: `.releaserc.json` defines the semantic-release pipeline.

### Docker Image Building

The GitHub workflow (`.github/workflows/manual-release.yml`) builds images for all supported architectures:

- **Architectures**: amd64, aarch64, armv7, armhf
- **Registry**: GitHub Container Registry (ghcr.io)
- **Tagging**: Each release creates both versioned (`v1.0.0`) and `latest` tags
- **Multi-arch manifest**: Published after individual arch images are built

### Add-on Architecture

The add-on itself (in `blocky/`) follows Home Assistant add-on conventions:

**Configuration Flow:**
1. User sets options in Home Assistant UI (stored in `/data/options.json`)
2. `rootfs/etc/cont-init.d/config.sh` runs at container start
3. Tempio template (`rootfs/usr/share/tempio/blocky.gtpl`) generates Blocky config
4. Generated config saved to `/config/config.yml` and `/etc/blocky/config.yml`
5. S6-overlay starts Blocky service (`rootfs/etc/services.d/blocky/run`)

**Custom Configuration Mode:**
- When `custom_config: true` in options, users can manually edit `/config/config.yml`
- Template generation is skipped, preserving manual edits
- Useful for advanced Blocky features not exposed in the UI

**Service Management:**
- Uses **s6-overlay** for process supervision
- Init scripts in `rootfs/etc/cont-init.d/` run before services
- Service definitions in `rootfs/etc/services.d/`
- Finish script (`blocky/finish`) handles service failures

## Key Files

### Repository-Level
- **package.json**: Node.js dependencies (semantic-release)
- **.releaserc.json**: Semantic-release configuration
- **renovate.json**: Renovate configuration for automated dependency updates
- **scripts/update-addon-version.mjs**: Updates version in `blocky/config.yaml` during release

### Add-on Level (blocky/)
- **config.yaml**: Add-on metadata, version, options schema, and defaults
- **Dockerfile**: Multi-arch container build (downloads Blocky binary from upstream)
- **build.yaml**: Defines base images for different architectures
- **rootfs/etc/cont-init.d/config.sh**: Configuration generation script
- **rootfs/etc/services.d/blocky/run**: Service start script
- **rootfs/usr/share/tempio/blocky.gtpl**: Jinja2-style template for Blocky config
- **translations/en.yaml**: UI text and option descriptions (i18n)
- **DOCS.md**: User-facing documentation for the add-on

## Dependency Management with Renovate

This repository uses **Renovate** for automated dependency updates. Renovate is configured via `renovate.json` and monitors:

- **Blocky version** (from GitHub releases)
- **Tempio version** (from GitHub releases)
- **Home Assistant base images** (from Docker registry)
- **npm packages** (semantic-release and plugins)
- **GitHub Actions** (workflow dependencies)

### How Renovate Works

**Automatic Updates (Auto-merged):**
- Patch and minor updates to npm packages, base images, and GitHub Actions
- Auto-merged after 3-day stability period
- Uses `chore(deps):` commit prefix (no version bump)

**Manual Review (PRs Created):**
- **Blocky updates**: Creates PR with `feat(deps):` prefix → triggers minor version bump
- **Tempio updates**: Creates PR with `fix(deps):` prefix → triggers patch version bump
- **Major updates**: Requires manual review and approval

### Updating Blocky Version (Automated)

Renovate automatically creates a PR when a new Blocky version is released:

1. Renovate detects new Blocky release on GitHub
2. Creates PR updating `BLOCKY_VERSION` in `blocky/Dockerfile`
3. PR uses `feat(deps): update Blocky to vX.Y.Z` commit message
4. Review and merge the PR
5. Trigger the manual release workflow in GitHub Actions
6. Semantic-release creates a minor version bump

### Updating Blocky Version (Manual)

If you need to update Blocky manually (e.g., testing a pre-release):

1. Edit `blocky/Dockerfile` and update the `BLOCKY_VERSION` ARG:
   ```dockerfile
   ARG BLOCKY_VERSION=v0.27.0  # Change this
   ```
2. Commit with `feat: update Blocky to vX.Y.Z`
3. Trigger release workflow

### Renovate Configuration

The Dockerfile uses inline comments to tell Renovate what to track:

```dockerfile
# renovate: datasource=github-releases depName=0xERR0R/blocky
ARG BLOCKY_VERSION=v0.27.0
```

See `renovate.json` for complete configuration including automerge rules, grouping, and schedules.

## Configuration Template Guidelines

When modifying `rootfs/usr/share/tempio/blocky.gtpl`:

- Use Jinja2/tempio syntax for dynamic values (e.g., `{{ .upstream_dns }}`)
- Reference add-on options defined in `blocky/config.yaml`
- **Always consult official Blocky docs**: https://0xerr0r.github.io/blocky/latest/configuration/
  - This is for Blocky's `config.yml` (the DNS proxy config)
  - NOT to be confused with add-on's `config.yaml` (add-on metadata)

## Translations

**Always use `blocky/translations/` for UI text**:
- Add-on option labels and descriptions belong in `translations/en.yaml`
- Do NOT embed user-facing text in the `schema` section of `config.yaml`
- Schema should only contain validation rules (regex patterns, types)

## Port Mappings

- **53/tcp & 53/udp**: DNS service (standard DNS port)
- **4000/tcp**: Blocky HTTP API and metrics (health check at `/api/health`)

## Important References

- **Blocky Configuration Docs**: https://0xerr0r.github.io/blocky/latest/configuration/
- **Blocky GitHub**: https://github.com/0xERR0R/blocky
- **Home Assistant Add-on Docs**: https://developers.home-assistant.io/docs/add-ons/
- **Tempio Template Engine**: https://github.com/home-assistant/tempio
