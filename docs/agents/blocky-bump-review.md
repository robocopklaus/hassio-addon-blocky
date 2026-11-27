# Reviewing a Blocky version bump

The concrete definition of what CLAUDE.md calls the *manual review* a Blocky bump requires. Renovate opens these as a one-line change to `BLOCKY_VERSION` in `blocky/Dockerfile` (Tempio bumps are the same shape via `TEMPIO_VERSION`). Most bumps merge as that bare one-liner — this runbook is how you earn that conclusion instead of assuming it.

## The two-signal model

A green render harness is **necessary but not sufficient**. It proves our rendered YAML still *parses* against the new binary; it is blind to behavioral changes on keys we emit and to new features we might want to expose. So the review layers two signals with complementary blind spots:

1. **Render harness (schema truth, automated).** The CI `render-test` job reads the new pin out of `blocky/Dockerfile`, downloads that exact binary, and runs `blocky validate` against our goldens (ADR-0003). It fails hard if a key the template emits was renamed or removed. **This is the gate of record** — the merge waits on `render-test` green on the PR, not on a local run.
2. **Directed changelog scan (semantic truth, human judgement).** Read the upstream release notes of **every** version between the old and new pin, but *directed* (dependency bumps cut, since they never touch a surface): `gh release view <tag> -R 0xERR0R/blocky --json body -q .body | sed '/^### Build and dependencies/,/^### Misc/{/^### Misc/!d;}'`. Cross each entry against the **three surfaces the add-on is coupled to**. An entry that touches none (e.g. an internal dnssec resolution fix) is out of our scope and passes without further work. An entry that touches one gets classified below — from its upstream PR description (`gh pr view <n> -R 0xERR0R/blocky`), not the one-line release note: the note names the change, the PR states who it hits and in which direction (0.35.0's "scope allowlist-only mode to the whole client" reads neutral; only the PR shows it *loosens* blocking).

   - **The config keys `blocky.gtpl` emits.** Derive the set from the template: `grep -nE '^[a-zA-Z].*:' blocky/rootfs/usr/share/tempio/blocky.gtpl`. Note which *sub*-keys a block emits too: `customDNS` without `zone`, for example, puts every zone-only change out of scope.
   - **The HTTP API endpoints and response shapes the add-on consumes.** Derive them: `grep -rn '/api/' blocky/config.yaml blocky/rootfs`. `render-test` cannot see these: it validates rendered YAML, and no golden contains an API response, so an endpoint that is removed, renamed, or changes its response shape passes the gate of record silently. What the grep does not show is that the probe (ADR-0012) reads `/api/query`'s `responseType`/`returnCode` fields *and* its 5xx-on-chain-error behaviour.
   - **The CLI subcommands the image runs.** Derive them: `grep -rnE '(^|[ "\[])blocky"?,? ' blocky/Dockerfile blocky/rootfs`. Also invisible to `render-test`, which only exercises `validate`. An upstream change to *another* subcommand (0.35.0's `healthcheck` fix, for example) passes.

   For the surfaces `render-test` cannot see, the scan has a live check: `scripts/bump-smoke.sh <old-tag> <new-tag>`, the **Bump smoke**. It runs both release binaries in a throwaway container against the defaults golden, the consumed API, the CLI and a dead resolver chain, and labels each failure with its disposition from this runbook. It needs Docker and internet access. Run it on every Blocky bump. It is evidence for this signal, never a third gate: the merge still waits on `render-test` alone.

## Classifying a changelog entry that touches a coupled surface

### Behavioral change (an exposed key behaves differently)

Classify on two axes:

- **Blast radius** — does it change a *default* that affects existing users, or only behavior when an opt-in is *actively enabled*?
- **Direction** — upstream *bugfix/correction*, or *regression / changed default*?

| | Bugfix / correction | Regression / changed default |
|---|---|---|
| **Opt-in / off-by-default** | Note in a PR comment, merge. No guard. | Hold: PR-comment note + release-note callout; guard/migration if warranted. |
| **Hits an existing default** | Note + release-note callout. | Hold: active mitigation before merge (passive migration per ADR-0005, or a guard per ADR-0002). |

Do **not** reach for a runtime guard on a mere behavioral shift — ADR-0002 reserves guards for *broken* features (fail-fast / degrade). A guard for "behavior moved" over-extends that semantics.

### New feature (new key or new enum value upstream)

**Default disposition: do not expose.** Standard Mode is curated (ADR-0006) — only options broadly useful in Home Assistant and workable without specialist downstream infrastructure. Exposing is a separate, deliberate feature decision (enum + template branch + translation + fixture/golden + contract check), never a bump side-effect. But the scan must *consciously reject*, not skip: record the non-exposition and its reason, so "deliberately not exposed" is distinguishable from "missed it." Whoever wants the feature uses Custom Config Mode.

Note that a closed enum (e.g. `query_log.type`) makes non-exposition zero-effort — the new value simply isn't in the list, and HA schema validation rejects it. A `match(...)`-gated string (e.g. `blocking.block_type`) counts as closed when its regex already rejects the new value — check the pattern in `blocky/config.yaml`. A truly free-form string field would need an explicit guard against the unhandled value.

### Consumed API change (an endpoint or response shape we read)

No table here — the axes above do not apply, because nothing about this is opt-in and no default is involved: we either still read the endpoint correctly or we do not. The coupled code is `blocky/rootfs/usr/lib/blocky/upstream_probe.sh` (verdict logic) and the `watchdog` URL in `blocky/config.yaml`, with the recorded responses pinned in `scripts/test-guards.sh`.

Split on what the change can do to the probe's *verdict*, because the two failure modes are not equally dangerous:

- **A changed response shape, a renamed field, a new response type — note it, merge, re-pin the recordings.** The probe degrades to `inconclusive` by construction: an unrecognised shape is never mistaken for proof. The cost is a signal that goes quiet, which is the same position we were in before ADR-0012 and is not worth blocking a security-relevant Blocky bump over. Re-pin `scripts/test-guards.sh` in the same PR (ADR-0009) or, if that needs real work, file it and merge the bump.
- **A change in how Blocky behaves when it cannot answer — Hold.** Whether a resolver-chain failure surfaces as a 5xx, as SERVFAIL, or as a held-open connection is what the probe *concludes from*, so a change here can make it warn on a healthy setup or stay silent through a real outage. That is the probe lying rather than going quiet, and it must be verified before merge with `scripts/bump-smoke.sh <old-tag> <new-tag>`: its chain-failure step runs both binaries against unreachable upstreams and fails if the HTTP status or the probe's verdict differs, or if the new verdict is not `failed`.

An endpoint that disappears entirely is the second kind: the watchdog URL in `blocky/config.yaml` would 404 and the Supervisor would restart the add-on in a loop. See ADR-0012.

A CLI subcommand we run that is renamed, removed, or changes its exit code is the same kind: Hold, and fix the call site in the same PR. `validate` failing aborts init; `blocking status` failing marks the container unhealthy.

## The merge gate

- **Go** when `render-test` is green on the PR **and** the directed scan produced no un-mitigated Hold. A bump needing no adaptation merges as the bare one-liner.
- **Hold** when the scan surfaces an un-absorbed behavioral change (see table), a change to how Blocky reports a resolver-chain failure or to an endpoint's existence, or `render-test` is red. A consumed response *shape* change is a note, not a Hold — see above for why the two differ.
- A red `render-test` means a key we emit broke upstream. The fix is a companion template/schema/golden change — and it rides in the **same PR** as the pin bump, never a follow-up (ADR-0009). `blocky-dev/` is CI-generated post-merge; it is not part of the bump PR.

## Working on the Renovate PR

Renovate regenerates the PR body on every rebase, so the scan's record — each classified entry, every deliberate non-exposition, and the Bump smoke's summary — goes in a **PR comment**, where it survives.

Any companion commit (adaptation, changelog lines) lands on Renovate's branch, which may trail `main` by weeks. Merge `origin/main` into it first, then commit and push normally — never rebase or force-push a branch Renovate owns. After a foreign commit Renovate stops rebasing the PR, so it now merges on your schedule, not Renovate's.

## Changelog and release

A bump touches the user-facing changelog, but does not complete it. `blocky/CHANGELOG.md` is hand-curated and finalized manually at release (ADR-0010). The release writes no content: it only checks the section's structure and stamps the date and the compare link.

- Add the bump's lines under the **concrete next-version heading** (e.g. `## [5.1.0]`), never `[Unreleased]` — nothing renames it at release. The next version follows from the conventional commits already merged since the last tag (`feat(deps):` is a minor).
- The upgrade line goes under `### Changed` ("Blocky upgraded from vX to vY"), and any behavioral note the classification produced (e.g. the ecs ordering note) rides with it — the changelog is the durable user-facing home for that note, not a PR comment.
- Every behavioral note claims a **delta** ("X now works"), so verify both ends before writing it:
  - **Old end:** confirm the old behaviour in the previous pin's source (`gh api 'repos/0xERR0R/blocky/contents/<file>?ref=<old tag>' -q .content | base64 -d`), not in the PR's framing. 0.37.0's draft claimed Unicode list entries "now block"; 0.35.0 already converted plain ones.
  - **Add-on end:** translate upstream behaviour through the add-on's runtime: the defaults in `blocky/config.yaml`, port 4000 published on the host, and the Supervisor's 10 s stop timeout with s6's 3 s grace period. 0.37.0's draft promised Blocky's 10 s shutdown flush, which the add-on's stop sequence probably cuts short.
  - **Counts and scope:** take them from the advisory or PR text itself (0.37.0 has seven DNSSEC advisories, of which six affect released versions).
- Assembling the full section (every user-facing change since the last tag) is a manual step at release-cut time, not part of the bump PR. Leave the heading undated and add no `[V]:` link for it: the release stamps both, and its gate aborts if `## [V]` is missing, already dated, empty, or named differently from the computed version, or if `[V]:` already exists (ADR-0010).

## Worked example — Blocky 0.33.0 (PR #266)

- **dnssec: Indeterminate not Bogus** — internal resolution behavior; we emit no `dnssec`. Out of scope, passes.
- **ecs `useAsClient` applied above cache/client-name lookup** — touches `ecs.useAsClient`, which we emit. Off by default (`use_as_client: false`), opt-in, and an upstream *bugfix*. → top-left cell: note in a PR comment, merge, no guard.
- **`dnstap` as a new `queryLog.type`** — touches `queryLog`, which we curate. New feature, and `query_log.type` is a closed enum that already excludes it. → default disposition: not exposed, recorded here as the deliberate rejection. Belongs in Custom Config Mode.
- `render-test` green against the 0.33.0 binary → no schema break. **Merge decision: go, bare one-liner.**
