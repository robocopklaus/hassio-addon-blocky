# Where config validation lives, and how invalid combinations fail

Home Assistant's add-on options schema validates only **per-field** (types, `match(REGEX)`, `list(enum)` — no conditional or cross-field rules). It cannot express "`cert_file` is required when `https.enable` is true". So **field-level** correctness lives in `config.yaml`'s schema (enums, regex, ranges), and **cross-field** correctness can only live in the Tempio template (`blocky.gtpl`) and the `cont-init.d` guards, with `blocky validate` as the final backstop.

For inconsistent multi-field combinations we decide **per feature** using one test: **"Does Blocky still resolve DNS without this feature?"**

- **No → core → fail-fast.** `config.sh` logs a clear error and aborts (same pattern as the query-log path check). Covers `upstreams`, `bootstrap`, and any case that yields fundamentally invalid YAML.
- **Yes → side → degrade + warn.** The template/guard actively detects the broken combination, **omits that feature so the generated YAML stays valid**, and `bashio::log.warning` explains what was dropped. DNS keeps serving. Covers `https`/`http3`/DoH, `prometheus`, `redis`, `query_log`, `blocking`, `ecs`, `conditional`, `custom_dns`.

**Considered & rejected:** (1) *Schema-first hard enforcement* of dependencies — impossible, HA schema has no cross-field validation. (2) *Pure fail-fast for everything* (today's de-facto behavior, since any invalid YAML makes `blocky validate` abort the whole add-on) — rejected because a single misconfigured side feature (e.g. HTTPS enabled without a cert) should not take down DNS for the whole network. (3) *Pure degrade* — rejected because silently resolving with no upstreams is worse than a loud failure.

**Consequence:** Every new multi-field block must answer the DNS test and wire up the matching behavior. "Side" features are not free — degrade requires the template to emit valid YAML with the broken part removed *and* a guard that warns; relying on `blocky validate` alone gives fail-fast, not degrade.

**Guards validate the rendered config, not a re-derivation of the options.** A guard in `cont-init.d` must read what it checks from the already-rendered `/etc/blocky/config.yml` (the real contract with Blocky), never re-compute defaults from `options.json` in parallel. Parallel derivation invites drift: the original query-log path check duplicated the template's default paths (`/config/query_logs`, `/config/querylog.db`) in `config.sh`, so changing one silently broke the other. Reading the effective `target:` straight from the rendered YAML makes drift impossible by construction — the coupling to the template's output format is narrow, visible, and fails loudly (empty path → validation trips) rather than silently.
