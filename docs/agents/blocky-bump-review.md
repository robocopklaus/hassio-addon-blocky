# Reviewing a Blocky version bump

The concrete definition of what CLAUDE.md calls the *manual review* a Blocky bump requires. Renovate opens these as a one-line change to `BLOCKY_VERSION` in `blocky/Dockerfile` (Tempio bumps are the same shape via `TEMPIO_VERSION`). Most bumps merge as that bare one-liner — this runbook is how you earn that conclusion instead of assuming it.

## The two-signal model

A green render harness is **necessary but not sufficient**. It proves our rendered YAML still *parses* against the new binary; it is blind to behavioral changes on keys we emit and to new features we might want to expose. So the review layers two signals with complementary blind spots:

1. **Render harness (schema truth, automated).** The CI `render-test` job reads the new pin out of `blocky/Dockerfile`, downloads that exact binary, and runs `blocky validate` against our goldens (ADR-0003). It fails hard if a key the template emits was renamed or removed. **This is the gate of record** — the merge waits on `render-test` green on the PR, not on a local run.
2. **Directed changelog scan (semantic truth, human judgement).** Read the upstream release notes, but *directed*: cross each entry against the top-level Blocky keys `blocky.gtpl` actually emits. As of this writing that set is `upstreams`, `bootstrapDns`, `filtering`, `fqdnOnly`, `customDNS`, `conditional`, `ecs`, `dns64`, `rebindingProtection`, `clientLookup`, `blocking`, `caching`, `redis`, `prometheus`, `queryLog`, `ports`, `http3`, `log`, and the TLS/cert fields — but the template is the authoritative source (`grep -nE '^[a-zA-Z].*:' blocky/rootfs/usr/share/tempio/blocky.gtpl`), so re-derive it rather than trusting this list. An entry that touches none of these keys (e.g. an internal dnssec resolution fix) is out of our translation scope and passes without further work. An entry that touches one gets classified below.

## Classifying a changelog entry that touches an emitted key

### Behavioral change (an exposed key behaves differently)

Classify on two axes:

- **Blast radius** — does it change a *default* that affects existing users, or only behavior when an opt-in is *actively enabled*?
- **Direction** — upstream *bugfix/correction*, or *regression / changed default*?

| | Bugfix / correction | Regression / changed default |
|---|---|---|
| **Opt-in / off-by-default** | Note in the PR body, merge. No guard. | Hold: PR-body note + release-note callout; guard/migration if warranted. |
| **Hits an existing default** | Note + release-note callout. | Hold: active mitigation before merge (passive migration per ADR-0005, or a guard per ADR-0002). |

Do **not** reach for a runtime guard on a mere behavioral shift — ADR-0002 reserves guards for *broken* features (fail-fast / degrade). A guard for "behavior moved" over-extends that semantics.

### New feature (new key or new enum value upstream)

**Default disposition: do not expose.** Standard Mode is curated (ADR-0006) — only options broadly useful in Home Assistant and workable without specialist downstream infrastructure. Exposing is a separate, deliberate feature decision (enum + template branch + translation + fixture/golden + contract check), never a bump side-effect. But the scan must *consciously reject*, not skip: record the non-exposition and its reason, so "deliberately not exposed" is distinguishable from "missed it." Whoever wants the feature uses Custom Config Mode.

Note that a closed enum (e.g. `query_log.type`) makes non-exposition zero-effort — the new value simply isn't in the list, and HA schema validation rejects it. A free-form string field would need an explicit guard against the unhandled value.

## The merge gate

- **Go** when `render-test` is green on the PR **and** the directed scan produced no un-mitigated Hold. A bump needing no adaptation merges as the bare one-liner.
- **Hold** when the scan surfaces an un-absorbed behavioral change (see table), or `render-test` is red.
- A red `render-test` means a key we emit broke upstream. The fix is a companion template/schema/golden change — and it rides in the **same PR** as the pin bump, never a follow-up (ADR-0009). `blocky-dev/` is CI-generated post-merge; it is not part of the bump PR.

## Changelog and release

A bump touches the user-facing changelog, but does not complete it. `blocky/CHANGELOG.md` is hand-curated and finalized manually at release (ADR-0010) — semantic-release stamps only `blocky/config.yaml`'s `version:`, never the changelog.

- Add the bump's lines under the **concrete next-version heading** (e.g. `## [5.1.0]`), never `[Unreleased]` — nothing renames it at release. The next version follows from the conventional commits already merged since the last tag (`feat(deps):` is a minor).
- The upgrade line goes under `### Changed` ("Blocky upgraded from vX to vY"), and any behavioral note the classification produced (e.g. the ecs ordering note) rides with it — the changelog is the durable user-facing home for that note, not a PR comment.
- Assembling the full section (every user-facing change since the last tag) and setting the release date is a manual step at release-cut time, not part of the bump PR.

## Worked example — Blocky 0.33.0 (PR #266)

- **dnssec: Indeterminate not Bogus** — internal resolution behavior; we emit no `dnssec`. Out of scope, passes.
- **ecs `useAsClient` applied above cache/client-name lookup** — touches `ecs.useAsClient`, which we emit. Off by default (`use_as_client: false`), opt-in, and an upstream *bugfix*. → top-left cell: note in PR body, merge, no guard.
- **`dnstap` as a new `queryLog.type`** — touches `queryLog`, which we curate. New feature, and `query_log.type` is a closed enum that already excludes it. → default disposition: not exposed, recorded here as the deliberate rejection. Belongs in Custom Config Mode.
- `render-test` green against the 0.33.0 binary → no schema break. **Merge decision: go, bare one-liner.**
