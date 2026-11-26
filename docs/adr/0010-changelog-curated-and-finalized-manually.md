# The user-facing changelog is curated and finalized manually at release

`blocky/CHANGELOG.md` is a **hand-curated, user-facing** changelog (Keep a Changelog format). semantic-release deliberately never touches it: its `@semantic-release/git` asset list is only `blocky/config.yaml`, there is no `@semantic-release/changelog` plugin, and the machine-generated release notes go to the GitHub release and the release commit message instead. So the changelog's content, its version headings, and the release date are all a human's responsibility.

**Decision.** Entries are written by hand under a **concrete next-version heading** (e.g. `## [5.1.0]`), never a `[Unreleased]` staging heading — because nothing renames `[Unreleased]` to the real version at release, so it would ship stale. The next version number is determined, not guessed: it follows from the conventional commits already merged since the last tag (`feat`/`feat(deps)` → minor, `fix` → patch, `feat!` → major). Before dispatching `release.yml`, someone **assembles and finalizes** the section: aggregate every user-facing change since the last tag under one heading, and set the release date (mirroring `## [5.0.0] - 2026-06-25`).

**Considered & rejected.** `@semantic-release/changelog` would populate the file automatically from the commit-analyzer's release notes — i.e. exactly the raw, per-commit, machine-derived content the curated changelog exists to *avoid*. The value of this file is a small, legible set of user-facing lines (an upgrade, a new option, a behavioral note), not a dump of every `chore(deps)` and `refactor`. Automating it would defeat its purpose. The GitHub release notes already serve the machine-generated audience.

**Consequences.**

- Cutting a release includes a manual changelog-finalize step (assemble the `## [X.Y.Z]` section + date). This step has no automation to fall back on; if skipped, the release ships with a missing or mis-headed changelog.
- A feature or bump PR *contributes* its lines to the pending section but does not complete it — the section is assembled across PRs and finalized at release-cut time. (`[5.0.0]` "bundles all changes since 4.1.1" is the reference example; intermediate versions were consolidated by hand.)
- The version heading is a human's call and can drift from semantic-release's computed version if a higher-impact commit (e.g. a `feat!`) lands before the release is cut. The finalize step reconciles the two — the computed version wins, the heading is corrected to match.
- `blocky-dev/CHANGELOG.md` is a CI-generated mirror (`deploy-dev` rsyncs `blocky/` post-merge); never edit it by hand.

## Amendment: the release gates the section and stamps the date

The finalize step failed once: v5.3.0 shipped with an undated `## [5.3.0]` heading, which is the failure the first consequence above predicted. Two parts of that step don't need judgement, so the release now does them:

- **Gate.** `@semantic-release/exec`'s `verifyReleaseCmd` runs `scripts/changelog-release.mjs verify <V>` once the version is computed and before anything is tagged or published. It aborts the release unless the topmost section is `## [V]` (the computed version, no date yet), there is no `## [Unreleased]`, the section holds at least one `### ` subsection with a `- ` entry, and every older section is dated. A heading that differs from the computed version fails with both versions named, so the reconciliation above happens before the release instead of after it. It runs under `--dry-run` too, so `pnpm release:dry-run` shows whether the changelog is ready.
- **Date.** The `prepareCmd` runs `scripts/changelog-release.mjs stamp <V>`, which turns `## [V]` into `## [V] - YYYY-MM-DD` (UTC). `blocky/CHANGELOG.md` joins `blocky/config.yaml` in the `@semantic-release/git` assets, so the release commit carries it.

The pipeline still writes no content, so `@semantic-release/changelog` stays rejected for the reasons above. Only structure is checked, never completeness: whether a change deserves a line is still a human's call, and a `chore(deps)` without one is correct. Choosing the entries, writing them and naming the heading remain manual. `pnpm check:changelog` tests the gate, and because it is release tooling it runs outside the `pnpm check` aggregate (ADR-0008).
