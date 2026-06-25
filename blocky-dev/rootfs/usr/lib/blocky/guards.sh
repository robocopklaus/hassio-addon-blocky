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
# communicates via exit status — so it can be tested outside the container
# (scripts/test-guards.sh asserts it against the render-test goldens).
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
