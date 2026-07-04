# A version bump and its required adaptation land in the same PR

When an upstream Blocky (or Tempio) bump forces a change to our translation layer — a renamed/removed key the template emits, a new enum value we decide to expose, a changed default we must absorb via passive migration — that change rides in the **same PR that moves the version pin**. `main` must never hold a commit where `blocky/Dockerfile` points at a version the template has not been adapted for.

**Why this is not obvious.** The natural instinct is "bump now, adapt in a follow-up PR." That is exactly the state this ADR forbids, and the reason is a consequence of ADR-0003: the render harness reads `BLOCKY_VERSION` *out of the Dockerfile* as its single version pin. So a PR that bumps the pin without the needed adaptation is precisely the state `render-test` is built to fail — and splitting the two across separate PRs would leave `main` red (or, worse, silently mis-rendered) in the window between them. The pin and its adaptation are one atomic change because the harness treats them as one.

**Consequences.**

- A Renovate bump PR that needs no adaptation (the common case — see the bump-review runbook) merges as the bare one-line pin change once `render-test` is green.
- A bump that *does* need adaptation is not merged as the bare Renovate one-liner. The companion template/schema/golden change is added onto the same PR (push to the Renovate branch, or supersede it with a branch that carries both), so pin and adaptation land together.
- This forbids the reverse split too: never adapt the template "in advance" for a version the pin has not yet reached — the harness would validate the *old* binary against template output shaped for the *new* one.

**Considered & rejected.** (1) *Decoupling the render pin from the Dockerfile* (a separate version file the harness reads) would let bump and adaptation live in separate PRs, but reintroduces the second source of truth ADR-0003 deliberately removed. (2) *Allowing a follow-up adaptation PR* keeps each PR smaller but accepts a red/mis-rendered `main` in between — unacceptable for a DNS resolver users depend on for connectivity.
