# The user-facing changelog is curated and finalized manually at release

`blocky/CHANGELOG.md` is a **hand-curated, user-facing** changelog (Keep a Changelog format). semantic-release deliberately never touches it: its `@semantic-release/git` asset list is only `blocky/config.yaml`, there is no `@semantic-release/changelog` plugin, and the machine-generated release notes go to the GitHub release and the release commit message instead. So the changelog's content, its version headings, and the release date are all a human's responsibility.

**Decision.** Entries are written by hand under a **concrete next-version heading** (e.g. `## [5.1.0]`), never a `[Unreleased]` staging heading — because nothing renames `[Unreleased]` to the real version at release, so it would ship stale. The next version number is determined, not guessed: it follows from the conventional commits already merged since the last tag (`feat`/`feat(deps)` → minor, `fix` → patch, `feat!` → major). Before dispatching `release.yml`, someone **assembles and finalizes** the section: aggregate every user-facing change since the last tag under one heading, and set the release date (mirroring `## [5.0.0] - 2026-06-25`).

**Considered & rejected.** `@semantic-release/changelog` would populate the file automatically from the commit-analyzer's release notes — i.e. exactly the raw, per-commit, machine-derived content the curated changelog exists to *avoid*. The value of this file is a small, legible set of user-facing lines (an upgrade, a new option, a behavioral note), not a dump of every `chore(deps)` and `refactor`. Automating it would defeat its purpose. The GitHub release notes already serve the machine-generated audience.

**Consequences.**

- Cutting a release includes a manual changelog-finalize step (assemble the `## [X.Y.Z]` section + date). This step has no automation to fall back on; if skipped, the release ships with a missing or mis-headed changelog.
- A feature or bump PR *contributes* its lines to the pending section but does not complete it — the section is assembled across PRs and finalized at release-cut time. (`[5.0.0]` "bundles all changes since 4.1.1" is the reference example; intermediate versions were consolidated by hand.)
- The version heading is a human's call and can drift from semantic-release's computed version if a higher-impact commit (e.g. a `feat!`) lands before the release is cut. The finalize step reconciles the two — the computed version wins, the heading is corrected to match.
- `blocky-dev/CHANGELOG.md` is a CI-generated mirror (`deploy-dev` rsyncs `blocky/` post-merge); never edit it by hand.
