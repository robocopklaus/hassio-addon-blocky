# Every option declares who owns its value, and the choice is made at introduction

Home Assistant's config UI submits **the entire displayed options object**, not a diff ([`_saveTapped`](https://github.com/home-assistant/frontend/blob/f71a938d023065aa6f4b7254c703ef2cde5516f5/src/panels/config/apps/app-view/config/supervisor-app-config.ts#L482-L515)). An operator's first Save therefore copies every value they can see — including defaults they never touched — into their persisted dict, where it wins the merge forever. Changing a value in `blocky/config.yaml`'s `options:` block after that is a **no-op** for them; only a key that did not exist at their last Save picks up its new default. See `docs/research/home-assistant-addon-options.md` §4.

The practical reading is not "avoid changing defaults" — it is that **the default is the last chance to decide who owns the value**. Three owners are possible, and all three already exist in this repo; the pattern was being chosen unconsciously.

| Owner | Shape in `options:` | Shape in the template | Reference | After the first Save |
|---|---|---|---|---|
| **Operator** | a real value | emitted unconditionally | `log.privacy: true` → `privacy: {{ .log.privacy }}` | frozen — we can never change it again |
| **Blocky** | `""` / `0` / `[]` | key **omitted** when empty | `caching.min_time: ""` → `{{ if $caching.min_time }}` | immune — "empty" persists, and empty still means *defer upstream* |
| **Add-on** | `""` / `0` / `[]` | template **substitutes** our value when empty | `query_log.target: ""` → `{{ else }}"/config/query_logs"{{ end }}` | immune — we can change our value any time and it reaches everyone |

**Decision.** When an option is **introduced**, its owner is chosen deliberately and the choice is recorded by the shape it ships in. Operator-owned means the shipped value is final: it is a starting point we are content to leave with every existing install indefinitely. If we might want to steer the value later, the option ships empty and either the template supplies the value (Add-on-owned) or omits the key (Blocky-owned).

For an **already-shipped** option the choice cannot be revisited: converting an Operator-owned default to a sentinel does not help anyone who already saved, because what they persisted is the concrete old value, not the sentinel. Sentinels are prophylaxis, never therapy. Changing an existing default is still permitted — it is correct for new installs — but the changelog line must say that it reaches new installations only. Silently shipping a default change as if it were a fix is the failure mode this ADR exists to prevent (`77f72ed` flipped `log.privacy` to `true` as a `fix:` in v3.2.0 and reached nobody who had ever pressed Save).

**The heavy lever.** A behaviour change that genuinely must reach existing operators has exactly one mechanism: introduce a **new key** and retain the old one under ADR-0005, because a key absent at the operator's last Save does pick up its default. This is ADR-0005's machinery run backwards, it doubles a key permanently, and it overrides operators who chose the old value deliberately. It is **justification-bearing**: the bar is a defect that makes the add-on wrong for everyone, not a preference we have changed our mind about. Deviating further from Blocky's own default does not clear it.

**Considered & rejected.**

1. *"Behaviour changes belong in the template, not in a changed default"* — the phrasing this ADR replaces. The template cannot distinguish a pinned default from a deliberate operator choice; both arrive as the same value in `/data/options.json`. "Solve it in the template" therefore means *ignore the option*, taking it away from the operators who set it on purpose. Sound as prophylaxis (that is Add-on-owned above), wrong as a repair.
2. *Sentinel defaults as a blanket policy* — every new option ships empty unless justified. Maximum future freedom, but the HA form would show blanks where real values belong, contradicting ADR-0006's curated, comprehensible surface. Owner choice stays per-option.
3. *A CI check that fails when an existing default changes* — expressible (report modified keys, not added ones), but `scripts/check-config-contract.mjs` is a static three-file parity check with no git baseline, and diff-awareness is a new capability with an awkward local story. Two behaviour-relevant default changes in the repo's history do not justify the machinery. Revisit if it happens again.
4. *A reminder hook in ADR-0010's release-finalize step* — deferred, not rejected. It is unverified whether the HA UI surfaces `blocky/CHANGELOG.md` or the GitHub release notes on update; putting an obligation into a channel of unknown reach is false assurance.

**Consequences.**

- Adding an option now carries a question the schema cannot express: who owns this value? The answer lives in the template's shape, so a reviewer reads `{{ if … }}` / `{{ else }}` as a statement of ownership, not just as gating.
- Blocky-owned is not free: the effective value then moves with every Blocky version bump, silently (see ADR-0009 on atomic pin-and-adapt). It is the right choice only where following upstream *is* the intent.
- Immunity holds only while the operator leaves the field empty. The moment they set a value it is theirs — which is correct, and is the point.
- Operator-owned defaults that depend on **external reality** are frozen liabilities: dead blocklist URLs, retired resolvers, changed endpoints cannot be corrected for existing installs. Lists make this worse, since HA's merger overrides a list wholesale rather than merging elements. Identifying that set is tracked separately.
