# Blocky Home Assistant Add-on

A containerized integration layer that translates Home Assistant add-on options into Blocky's native YAML. The domain language here is about *that translation* — modes, rendering, and how invalid input is handled — not about DNS resolution itself (that's Blocky's domain, see the upstream Blocky docs).

## Language

### Configuration modes

**Standard Mode**:
The default. HA UI options are rendered through the Tempio template into the runtime config on every restart.
_Avoid_: default mode, UI mode

**Custom Config Mode**:
The operator supplies a complete Blocky YAML; template rendering is bypassed entirely and UI options are ignored. Generated once on first run, then preserved.
_Avoid_: manual mode, advanced mode, expert mode

### Translation pipeline

**Rendered config**:
The generated `/etc/blocky/config.yml` — the single source of truth and the actual contract with the Blocky binary. Guards validate *this*, never a re-derivation of the options.
_Avoid_: output config, generated YAML (when precision matters)

**Guard**:
A check in a `cont-init.d` script that inspects the rendered config (or prepares its on-disk dependencies) before Blocky starts, and either aborts or degrades on a problem. Distinct from the template's own conditional gating.
_Avoid_: validator, check

### Testing the translation (see ADR-0003)

**Render harness**:
`scripts/render-test/run.mjs` — runs the real pinned `tempio` + `blocky` binaries to render fixtures and assert the result. Crosses the same seam the add-on does at runtime (`options.json` → Rendered config → `blocky validate`). Additive to the contract checker, which guards three-file parity but never renders.
_Avoid_: test script, renderer

**Fixture**:
A test case under `scripts/render-test/fixtures/<name>/`: a tiny `override.json` deep-merged onto the defaults read live from `config.yaml`, optionally an `expect-invalid` marker. Mirrors how Home Assistant composes options (defaults + user overrides).
_Avoid_: test case, sample, scenario

**Golden**:
The committed `expected.yml` snapshot of a fixture's Rendered config. The byte-for-byte contract; regenerated only via `--update`, never by CI.
_Avoid_: snapshot, expected output, baseline

### Failure policy (see ADR-0002)

**Core feature**:
A feature without which Blocky cannot resolve DNS at all (e.g. `upstreams`, `bootstrap`). A broken core feature is fail-fast: the add-on logs a clear error and aborts.
_Avoid_: required feature, essential feature

**Side feature**:
A feature DNS resolution survives without (e.g. `https`/DoH, `prometheus`, `redis`, `query_log`, `blocking`). A broken side feature degrades: the template omits it so the rendered YAML stays valid, and a guard warns.
_Avoid_: optional feature, secondary feature

### Blocking vocabulary

**Denylist** / **Allowlist**:
Named groups of block/exception sources. The add-on standardizes on these terms throughout schema, UI, and template.
_Avoid_: blacklist, whitelist, blocklist
