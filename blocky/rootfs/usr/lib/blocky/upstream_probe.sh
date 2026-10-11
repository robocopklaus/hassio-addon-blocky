# shellcheck shell=bash
# ==============================================================================
# Helpers for the upstream resolution probe (etc/services.d/upstream-probe/run).
#
# The probe answers a question no guard can: do the upstreams still ANSWER?
# Guards read the rendered config, so they see a resolver that is present, never
# one that is dead (ADR-0002). See ADR-0012 for why this reports rather than
# enforces, and for the options that were rejected.
#
# The service loop crosses three functions: probe_once makes one exchange and
# returns a verdict, probe_observe folds that verdict into the probe's level and
# says what to log, and probe_reset starts over. Everything else here is behind
# them. None of it logs or needs bashio, and the only outside dependency is
# curl, which a test can shadow with a shell function — so scripts/test-guards.sh
# runs the exact code the service runs, without a container or an upstream.
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

# Split what `curl -w '\n%{http_code}'` writes into "<status> <body>". The body
# is single-line JSON, but taking the status after the LAST newline keeps that
# from being a requirement. curl writes 000 when it never got an HTTP response.
_probe_split() {
    local response="$1" status body
    status="${response##*$'\n'}"
    body="${response%$'\n'*}"
    # No newline at all means curl produced nothing (not even a status): there
    # is no body, and the empty status classifies as inconclusive.
    case "${response}" in
        *$'\n'*) printf '%s %s\n' "${status}" "${body}" ;;
        *) printf ' %s\n' "${response}" ;;
    esac
}

# probe_classify <http_status> <body> [curl_exit] -> resolved | failed | inconclusive
#
# Turns one /api/query exchange into a verdict about the UPSTREAMS. Only two
# outcomes are statements about upstream health; everything else is one bucket,
# because the caller has exactly one thing to do with all of it — nothing:
#
#   resolved     an upstream answered (NXDOMAIN for the probe name is a healthy
#                answer — it proves the query reached a resolver that replied)
#   failed       the resolver chain could not get an answer. Blocky's API turns
#                a chain error into a 5xx; SERVFAIL/BOGUS is the same failure
#                arriving as a DNS return code; and a query the API accepted but
#                never answered is that failure with no return code to carry it
#   inconclusive says nothing about the upstreams, so never warn: Blocky
#                answered locally (cache, blocking, filtering, custom DNS,
#                special-use names), or Blocky is not answering at all because
#                it is down or still starting — its own logging owns that — or
#                the response was not one we understand
#
# curl_exit is curl's own exit code, and it is load-bearing for exactly one
# case. An upstream that swallows packets rather than refusing them — the
# failure #310 was raised about — leaves Blocky waiting until its own
# upstreams.timeout, so the probe hits its budget first and gets no HTTP status.
# Read from the status alone that is indistinguishable from Blocky being down,
# and calling it inconclusive would restore the very silence this probe exists
# to break. Against a listener on 127.0.0.1 a connection either succeeds or is
# refused immediately, so a timeout there means the query WAS accepted and went
# unanswered. Defaults to 0 so a caller with no exit code to offer keeps the
# quiet reading.
probe_classify() {
    local status="$1" body="$2" curl_exit="${3:-0}" rtype rcode

    # curl(1): 28 is "operation timeout". Checked before the status, but only
    # ever reached when there is no status — a completed exchange cannot time
    # out, so a real 2xx/4xx/5xx below is never overridden.
    case "${status}" in
        "" | 000)
            if [ "${curl_exit}" = "28" ]; then
                echo failed
            else
                echo inconclusive
            fi
            return
            ;;
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

# probe_once <api_base> <timeout> -> resolved | failed | inconclusive
#
# One probe: ask the Blocky API at <api_base> to resolve a fresh probe name, and
# classify the exchange. <timeout> is curl's whole budget in seconds.
probe_once() {
    local api_base="$1" timeout="$2" name response curl_exit split
    name="$(probe_query_name)"

    # -s (not -sS): a connection error every interval while Blocky is down is
    # noise, and the verdict already says so. -w appends the status code, which
    # _probe_split separates back out. curl is the only command in the
    # substitution, so curl_exit is its exit code — what tells a query Blocky
    # accepted and never answered apart from Blocky not being there at all (see
    # probe_classify). Captured with && || so a caller running under errexit
    # still gets a verdict rather than an abort.
    response="$(curl -s -m "${timeout}" -X POST \
        -H 'Content-Type: application/json' \
        -d "{\"query\":\"${name}\",\"type\":\"A\"}" \
        -w '\n%{http_code}' \
        "${api_base}/api/query")" && curl_exit=0 || curl_exit=$?

    split="$(_probe_split "${response}")"
    probe_classify "${split%% *}" "${split#* }" "${curl_exit}"
}

# Two consecutive failures before warning keeps a single dropped packet out of
# the log; re-warning after another twelve failed probes (an hour at the
# service's interval) means a log opened at any point during a long outage still
# explains itself. ADR-0012.
readonly PROBE_FAILURE_THRESHOLD=2
readonly PROBE_REWARN_AFTER_FAILED_PROBES=12

# probe_reset: start over, as before the first probe.
#
# The probe's state lives in these globals, which probe_observe advances in the
# calling shell (so call it directly, never in a $(...) subshell):
#
#   PROBE_LEVEL          unknown | healthy | failing — what the log has said.
#                        Inconclusive verdicts freeze it, because the log is read
#                        next to Blocky's own errors (ADR-0012). It is NOT the
#                        Runtime fact: a reader without the log must be given a
#                        state derived from PROBE_LAST_VERDICT too (ADR-0013).
#   PROBE_LAST_VERDICT   the most recent verdict, or empty before the first
#   PROBE_ACTION         what the latest verdict calls for in the log:
#                        verified | recovered | warn | none
#
# PROBE_CONSECUTIVE_FAILURES and PROBE_FAILED_SINCE_WARNING are its counters.
# The state is read by the caller, never in this file, hence the SC2034 opt-outs.
# shellcheck disable=SC2034
probe_reset() {
    PROBE_LEVEL=unknown
    PROBE_LAST_VERDICT=""
    PROBE_ACTION=none
    PROBE_CONSECUTIVE_FAILURES=0
    PROBE_FAILED_SINCE_WARNING=0
}

# probe_observe <verdict>: fold one verdict from probe_once into the state above.
# shellcheck disable=SC2034
probe_observe() {
    PROBE_LAST_VERDICT="$1"
    PROBE_ACTION=none

    case "$1" in
        resolved)
            if [ "${PROBE_LEVEL}" = "failing" ]; then
                PROBE_ACTION=recovered
            elif [ "${PROBE_LEVEL}" = "unknown" ]; then
                PROBE_ACTION=verified
            fi
            PROBE_LEVEL=healthy
            PROBE_CONSECUTIVE_FAILURES=0
            ;;
        failed)
            PROBE_CONSECUTIVE_FAILURES=$((PROBE_CONSECUTIVE_FAILURES + 1))
            if [ "${PROBE_LEVEL}" = "failing" ]; then
                PROBE_FAILED_SINCE_WARNING=$((PROBE_FAILED_SINCE_WARNING + 1))
                if [ "${PROBE_FAILED_SINCE_WARNING}" -ge "${PROBE_REWARN_AFTER_FAILED_PROBES}" ]; then
                    PROBE_FAILED_SINCE_WARNING=0
                    PROBE_ACTION=warn
                fi
            elif [ "${PROBE_CONSECUTIVE_FAILURES}" -ge "${PROBE_FAILURE_THRESHOLD}" ]; then
                PROBE_LEVEL=failing
                PROBE_FAILED_SINCE_WARNING=0
                PROBE_ACTION=warn
            fi
            ;;
        *)
            # inconclusive: Blocky answered locally, or is not answering at all.
            # Not a statement about the upstreams, so it neither moves the level
            # nor warns. The failure run does reset, though: "two consecutive
            # failures" has to mean two in a row with nothing in between, or one
            # failure now and one next week would eventually warn.
            PROBE_CONSECUTIVE_FAILURES=0
            ;;
    esac
}
