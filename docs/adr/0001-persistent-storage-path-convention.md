# Persistent storage paths for generated artifacts

The add-on translates HA options into Blocky config and must place Blocky's runtime artifacts on persistent storage that survives container restarts and add-on updates. We route **user-facing data the operator may want to read or manage** (CSV/SQLite query logs) under `/config/` — the `addon_config:rw`-mapped, user-visible folder — with a hard `/config/`-containment check in `config.sh` to prevent path traversal. We route **purely internal, regenerable state** (the on-disk block-list download cache) under `/data/` — the add-on-private dir that persists across updates but is hidden from the user — so it never clutters the operator's visible config folder.

**Considered & rejected:** putting the list cache under `/config/` too (consistent single location). Rejected because the cache is regenerable noise the user should never see or edit, and `/data/` already exists for exactly this kind of private persistent state.

**Consequence:** new features follow this split — ask "would the operator ever want to look at this file?" `/config/` if yes, `/data/` if no.
