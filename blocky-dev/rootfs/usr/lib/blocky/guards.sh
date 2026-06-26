# shellcheck shell=bash
# ==============================================================================
# Guard helpers that inspect the RENDERED Blocky config (/etc/blocky/config.yml).
#
# These functions text-parse template-generated YAML, so they are coupled to the
# template's deterministic output format and are safe ONLY in Standard Mode.
# Never run them against a hand-written custom config. See ADR-0002 (guards read
# the rendered config) and ADR-0004 (format-coupled guards are Standard-Mode-only).
#
# Each function is pure: it takes the config path as $1, reads nothing else, and
# communicates via exit status or stdout — so it can be tested outside the
# container (scripts/test-guards.sh asserts them against the render-test goldens).
# ==============================================================================

# upstreams is a CORE feature: Blocky needs a "default" group with at least one
# resolver, or it starts but cannot resolve DNS (and `blocky validate` does not
# catch this). Succeeds (0) when the rendered config has such a group; fails (1)
# otherwise.
upstreams_default_has_resolver() {
    awk '
        /^upstreams:/                       { in_up = 1; next }
        in_up && /^[^[:space:]]/            { in_up = 0 }            # left the upstreams block
        in_up && /^    "default":[[:space:]]*$/ { in_def = 1; next } # entered the default group
        in_def && /^      - /               { found = 1; in_def = 0; next } # a resolver under default
        in_def && /^(  [^ ]|    [^ ])/      { in_def = 0 }          # default ended without a resolver
        END                                  { exit(found ? 0 : 1) }
    ' "$1"
}

# Read a single scalar field from the queryLog block of the rendered config.
# Scopes to the "queryLog:" block (header at column 0) and prints the unquoted
# value of "  <key>:" within it; prints nothing if the block or key is absent.
# Internal helper, single-sourced between query_log_target and query_log_dir.
_query_log_field() {
    awk -v key="$2" '
        BEGIN                        { pat = "^  " key ":[[:space:]]*" }
        /^queryLog:/                 { in_q = 1; next }
        in_q && /^[^[:space:]]/      { in_q = 0 }          # left the queryLog block
        in_q && $0 ~ pat {
            val = $0
            sub(pat, "", val)                              # strip "  key:   "
            sub(/^"/, "", val); sub(/"[[:space:]]*$/, "", val)  # strip surrounding quotes
            print val
            exit
        }
    ' "$1"
}

# query_log.type is csv/csv-client/sqlite -> "target:" is a filesystem PATH that
# config.sh must create on disk. For mysql/postgresql/timescale "target:" is a
# DSN connection string (NOT a path), and console/none/"" have no target at all.
# This recognises the three path-bearing types by allowlist (so a future Blocky
# db-type can never be mistaken for a path) and prints the target only for them;
# prints nothing otherwise. The type is read from the rendered config, not from
# options.json, so config.sh keeps no re-derivation of it (ADR-0002).
query_log_target() {
    case "$(_query_log_field "$1" type)" in
        csv | csv-client | sqlite) _query_log_field "$1" target ;;
    esac
}

# The directory config.sh must ensure exists for the query log. A sqlite target
# is a FILE, so its parent directory is created; a csv/csv-client target IS the
# directory. Prints nothing when there is no path-bearing target. Encapsulates
# the file-vs-directory knowledge so config.sh never needs the type.
query_log_dir() {
    local target
    case "$(_query_log_field "$1" type)" in
        sqlite)
            target="$(_query_log_field "$1" target)"
            [ -n "${target}" ] && dirname "${target}"
            ;;
        csv | csv-client)
            _query_log_field "$1" target
            ;;
    esac
}

# Pure string check on a query log target: succeeds (0) when the path is /config
# or sits under /config/ and contains no ".." traversal; fails (1) otherwise.
# The caller (config.sh) owns the fatal message. Takes the target string as $1.
query_log_target_is_safe() {
    case "$1" in
        *..*) return 1 ;;
    esac
    case "$1" in
        /config | /config/*) return 0 ;;
        *) return 1 ;;
    esac
}

# OUTCOME half of the HTTPS/DoH degrade-warn guard (ADR-0007). HTTPS is a side
# feature (ADR-0002): when enabled without a cert+key the template DROPS it and
# emits no top-level "certFile:" rather than open :443 with no certificate.
# Succeeds (0) when TLS survived into the rendered config, fails (1) when it was
# dropped. config.sh pairs this with the operator's INTENT (https.enable from
# options) — the intent cannot be recovered from a config the feature was just
# dropped from, so it is NOT re-derived here; this only observes what rendered.
https_cert_rendered() {
    grep -qE '^certFile:' "$1"
}

# OUTCOME half of the single_name_order degrade-warn guard (ADR-0007).
# client_lookup.single_name_order only survives into the rendered config when an
# upstream is also set (the template drops it otherwise, an ADR-0002 degrade).
# Succeeds (0) when the rendered clientLookup carries "singleNameOrder:", fails
# (1) when it was dropped. Paired with options intent in config.sh.
single_name_order_rendered() {
    grep -qE '^  singleNameOrder:' "$1"
}
