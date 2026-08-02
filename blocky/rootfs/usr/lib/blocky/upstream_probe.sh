# shellcheck shell=bash
# ==============================================================================
# Helpers for the upstream resolution probe (etc/services.d/upstream-probe/run).
#
# The probe answers a question no guard can: do the upstreams still ANSWER?
# Guards read the rendered config, so they see a resolver that is present, never
# one that is dead (ADR-0002). See ADR-0012 for why this reports rather than
# enforces, and for the options that were rejected.
#
# These functions are pure: they take their whole input as arguments, touch no
# network and no files, and communicate on stdout — so scripts/test-guards.sh
# runs the exact functions the service runs, without a container or an upstream.
# ==============================================================================

# The suffix of every probe query. A nonexistent TLD, so the query is answered
# by the root servers with NXDOMAIN and never reaches anyone's real zone; two
# labels, so `fqdn_only` cannot reject it locally; and self-identifying, so an
# operator who finds it in their query log can tell what it is.
readonly PROBE_NAME_SUFFIX="blocky-addon-probe"

# Print a fresh probe query name. The random label matters for correctness, not
# for secrecy: a fixed name would be served from Blocky's cache on every probe
# after the first, and a cache hit proves nothing about the upstreams.
probe_query_name() {
    local rand
    # LC_ALL=C keeps tr byte-oriented on locales that would otherwise choke on
    # binary input. head closing the pipe early is the intended stop condition.
    rand="$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom 2>/dev/null | head -c 12)"
    # Degrade to the shell's own randomness rather than emit an empty label if
    # /dev/urandom is unreadable; an empty label would make the name invalid.
    [ -n "${rand}" ] || rand="${RANDOM}${RANDOM}"
    printf 'p%s.%s\n' "${rand}" "${PROBE_NAME_SUFFIX}"
}

# Read one string field out of a flat JSON object. `jq` is in the container and
# would be the obvious tool, but these functions are pure so the test suite can
# run the exact code the service runs, and that suite runs on a developer's host
# where only POSIX text tools are guaranteed. awk keeps the one-implementation
# property; jq would cost a host dependency to parse two enum strings.
#
# Deliberately narrow: it handles exactly the shape /api/query returns (a flat
# object of string values, no escaped quotes in returnCode/responseType) and
# prints nothing for anything else, which the caller reads as "inconclusive"
# rather than as a verdict.
_probe_field() {
    printf '%s' "$1" | awk -v key="$2" '
        {
            pat = "\"" key "\"[ \t]*:[ \t]*\""
            if (match($0, pat)) {
                rest = substr($0, RSTART + RLENGTH)
                q = index(rest, "\"")
                if (q > 0) print substr(rest, 1, q - 1)
            }
        }
    '
}

# Split what `curl -w '\n%{http_code}'` writes into "<status> <body>", so the
# response-shape coupling lives here with the rest of it and is covered by the
# same tests, rather than sitting untested inside the service loop. The body is
# single-line JSON, but taking the status after the LAST newline keeps that from
# being a requirement. curl writes 000 when it never got an HTTP response.
probe_split_response() {
    local response="$1" status body
    status="${response##*$'\n'}"
    body="${response%$'\n'*}"
    # No newline at all means curl produced nothing (not even a status): there
    # is no body, and the empty status classifies as unreachable.
    case "${response}" in
        *$'\n'*) printf '%s %s\n' "${status}" "${body}" ;;
        *) printf ' %s\n' "${response}" ;;
    esac
}

# probe_classify <http_status> <body> -> resolved | failed | inconclusive | unreachable
#
# Turns one /api/query exchange into a verdict about the UPSTREAMS. The four
# outcomes exist because only two of them are about upstream health at all:
#
#   resolved     an upstream answered (NXDOMAIN for the probe name is a healthy
#                answer — it proves the query reached a resolver that replied)
#   failed       the resolver chain could not get an answer. Blocky's API turns
#                a chain error into a 5xx; SERVFAIL/BOGUS is the same failure
#                arriving as a DNS return code
#   inconclusive Blocky answered locally (cache, blocking, filtering, custom
#                DNS, special-use names) or the response was not one we
#                understand — says nothing about upstreams, so never warn
#   unreachable  no HTTP response at all: Blocky is down or still starting,
#                which is Blocky's own logging to report, not the probe's
probe_classify() {
    local status="$1" body="$2" rtype rcode

    case "${status}" in
        "" | 000) echo unreachable; return ;;
        5??) echo failed; return ;;
        200) ;;
        *) echo inconclusive; return ;;
    esac

    rtype="$(_probe_field "${body}" responseType)"
    rcode="$(_probe_field "${body}" returnCode)"

    if [ "${rcode}" = "SERVFAIL" ] || [ "${rtype}" = "BOGUS" ]; then
        echo failed
        return
    fi

    # RESOLVED is the only response type that proves the group serving this
    # client answered. CONDITIONAL is deliberately excluded: a conditional
    # mapping that swallowed the probe name would prove a conditional upstream
    # is alive while saying nothing about the default group — the one the probe
    # exists to watch. Allowlisted, so a response type added by a future Blocky
    # version reads as inconclusive instead of being mistaken for proof.
    if [ "${rtype}" = "RESOLVED" ]; then
        case "${rcode}" in
            NOERROR | NXDOMAIN) echo resolved; return ;;
        esac
    fi

    echo inconclusive
}
