# Blocky Home Assistant Add-on

A containerized integration layer that translates Home Assistant add-on options into Blocky's native YAML. The domain language here is about *that translation* — modes, rendering, and how invalid input is handled — not about DNS resolution itself (that's Blocky's domain, see the upstream Blocky docs).

## Language

### Configuration modes

**Standard Mode**:
The default, curated HA-facing configuration surface: HA UI options are rendered through the Tempio template into the runtime config on every restart. It intentionally exposes only Blocky options that are understandable and broadly useful in Home Assistant; specialist Blocky settings belong in Custom Config Mode.
_Avoid_: default mode, UI mode, full Blocky coverage

**Custom Config Mode**:
The operator supplies a complete Blocky YAML; template rendering is bypassed entirely and UI options are ignored. Generated once on first run, then preserved.
_Avoid_: manual mode, advanced mode, expert mode

### Translation pipeline

**Rendered config**:
The generated `/etc/blocky/config.yml` — the single source of truth and the actual contract with the Blocky binary. Guards validate *this*, never a re-derivation of the options.
_Avoid_: output config, generated YAML (when precision matters)

**Guard**:
A check in a `cont-init.d` script that inspects the rendered config (or prepares its on-disk dependencies) before Blocky starts, and either aborts or degrades on a problem. Distinct from the template's own conditional gating. A guard that *text-parses* the rendered config (e.g. the upstreams core guard, the query-log path guard) is **format-coupled** and runs in Standard Mode only — never against a hand-written custom config (see ADR-0004). Format-coupled detection lives in `usr/lib/blocky/guards.sh` as pure functions, single-sourced between the runtime guard and its test.
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

### Config migration

**Passive migration**:
The only migration lever this add-on has. Home Assistant does not auto-migrate add-on options: on a schema change it keeps persisted values for keys still in the schema and silently drops the rest. So an old config is "migrated" not by rewriting the user's stored `options.json` (HA owns that file and would clobber any rewrite) but by the schema **retaining** the deprecated key and the template **translating** its old shape into the new Rendered config on every render. The `start_verify` → `init_strategy` mapping is the reference example.
_Avoid_: config upgrade, options rewrite

**Deprecated key**:
An add-on option kept in the schema past its replacement purely so HA does not strip a user's persisted value, and translated by the template into its current equivalent. Removing it from the schema is a breaking change that silently deletes that setting for existing users.
_Avoid_: legacy option, old key

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
