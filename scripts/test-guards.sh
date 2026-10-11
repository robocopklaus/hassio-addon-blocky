#!/usr/bin/env bash
# ==============================================================================
# Tests for the config.sh guard helpers (blocky/rootfs/usr/lib/blocky/guards.sh).
#
# Runs the real detection functions against the committed render-test goldens
# (the same fixtures the render harness uses) plus a few synthetic broken
# configs that no golden covers. Single-sourced: the function under test is the
# exact one config.sh runs at startup. See ADR-0004.
# ==============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=blocky/rootfs/usr/lib/blocky/guards.sh
source "${ROOT}/blocky/rootfs/usr/lib/blocky/guards.sh"

FIXTURES="${ROOT}/scripts/render-test/fixtures"
fail=0
pass() { printf 'ok   %s\n' "$1"; }
bad() {
    printf 'FAIL %s\n' "$1"
    fail=1
}

# Every committed render golden must satisfy the upstreams guard, except the
# upstreams-empty fixture, which exists to pin the broken case.
for golden in "${FIXTURES}"/*/expected.yml; do
    name="$(basename "$(dirname "${golden}")")"
    if upstreams_default_has_resolver "${golden}"; then
        if [ "${name}" = "upstreams-empty" ]; then
            bad "upstreams-empty: should be rejected, was accepted"
        else
            pass "${name}: accepted"
        fi
    else
        if [ "${name}" = "upstreams-empty" ]; then
            pass "upstreams-empty: rejected"
        else
            bad "${name}: should be accepted, was rejected"
        fi
    fi
done

# Synthetic broken states not represented by a golden.
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

cat >"${tmp}/empty-default.yml" <<'YAML'
upstreams:
  groups:
    "default":
  init:
    strategy: "blocking"
YAML
if upstreams_default_has_resolver "${tmp}/empty-default.yml"; then
    bad "empty-default-resolvers: should be rejected, was accepted"
else
    pass "empty-default-resolvers: rejected"
fi

cat >"${tmp}/no-default.yml" <<'YAML'
upstreams:
  groups:
    "custom":
      - "udp:9.9.9.9"
  init:
    strategy: "blocking"
YAML
if upstreams_default_has_resolver "${tmp}/no-default.yml"; then
    bad "no-default-group: should be rejected, was accepted"
else
    pass "no-default-group: rejected"
fi

# ---- query_log_target / query_log_dir / query_log_target_is_safe ------------

# Every committed golden that yields a path-bearing target must produce one the
# safety check accepts (goldens are all valid), and the two path-type defaults
# must extract to exactly the expected target/dir. db/console/none yield nothing.
for golden in "${FIXTURES}"/*/expected.yml; do
    name="$(basename "$(dirname "${golden}")")"
    target="$(query_log_target "${golden}")"

    if [ -n "${target}" ]; then
        if query_log_target_is_safe "${target}"; then
            pass "${name}: query_log_target safe (${target})"
        else
            bad "${name}: emitted target rejected by is_safe (${target})"
        fi
    fi

    # Exact-value contract for the path-type default fixtures. (run.mjs pins the
    # rendered target line byte-for-byte; here we pin that the function extracts it.)
    case "${name}" in
        querylog-csv-default) exp_target="/config/query_logs"; exp_dir="/config/query_logs" ;;
        querylog-sqlite-default) exp_target="/config/querylog.db"; exp_dir="/config" ;;
        *) exp_target=""; exp_dir="" ;;
    esac
    if [ -n "${exp_target}" ]; then
        if [ "${target}" = "${exp_target}" ]; then
            pass "${name}: target == ${exp_target}"
        else
            bad "${name}: target '${target}' != '${exp_target}'"
        fi
        dir="$(query_log_dir "${golden}")"
        if [ "${dir}" = "${exp_dir}" ]; then
            pass "${name}: dir == ${exp_dir}"
        else
            bad "${name}: dir '${dir}' != '${exp_dir}'"
        fi
    fi
done

# Anti-DSN: db-type goldens carry a DSN in "target:", never a path. The function
# must emit NOTHING for them — the bug-prone case the allowlist exists to prevent.
for name in querylog-mysql querylog-postgres; do
    golden="${FIXTURES}/${name}/expected.yml"
    [ -f "${golden}" ] || continue
    target="$(query_log_target "${golden}")"
    if [ -z "${target}" ]; then
        pass "${name}: db-type emits no path"
    else
        bad "${name}: db-type leaked a target (${target})"
    fi
done

# ---- https_cert_rendered / single_name_order_rendered (ADR-0007) ------------
# These read the OUTCOME half of a degrade-warn guard: did the side feature
# survive into the rendered config? config.sh pairs each with the operator's
# INTENT read from options.json (which a dropped feature cannot be recovered
# from). The four fixtures pin both the survived and the dropped branch.
assert_rendered() { # <fn> <fixture> <want: yes|no>
    local fn="$1" fixture="$2" want="$3" got
    local golden="${FIXTURES}/${fixture}/expected.yml"
    if [ ! -f "${golden}" ]; then
        bad "${fixture}: golden missing"
        return
    fi
    if "${fn}" "${golden}"; then got=yes; else got=no; fi
    if [ "${got}" = "${want}" ]; then
        pass "${fixture}: ${fn} -> ${got}"
    else
        bad "${fixture}: ${fn} -> ${got}, want ${want}"
    fi
}
assert_rendered https_cert_rendered tls-ready yes
assert_rendered https_cert_rendered tls-no-cert no
assert_rendered single_name_order_rendered single-name-order-with-upstream yes
assert_rendered single_name_order_rendered single-name-order-no-upstream no

# Synthetic safety cases not represented by a golden.
for safe in "/config" "/config/query_logs" "/config/querylog.db"; do
    if query_log_target_is_safe "${safe}"; then
        pass "is_safe accepts ${safe}"
    else
        bad "is_safe should accept ${safe}"
    fi
done
for unsafe in "/config/../secrets" "/etc/passwd" "../x" "/configfoo"; do
    if query_log_target_is_safe "${unsafe}"; then
        bad "is_safe should reject ${unsafe}"
    else
        pass "is_safe rejects ${unsafe}"
    fi
done

# ---- upstream_probe.sh -----------------------------------------------------
#
# The probe module: the classifier that turns one /api/query exchange into a
# verdict about the UPSTREAMS (never about the add-on), the exchange itself, and
# the step that turns a run of verdicts into the log's level and actions. It is
# not format-coupled to the rendered config (it reads Blocky's API), but it is
# coupled to that response shape, so it is pinned here the same way. ADR-0012.

# shellcheck source=blocky/rootfs/usr/lib/blocky/upstream_probe.sh
source "${ROOT}/blocky/rootfs/usr/lib/blocky/upstream_probe.sh"

assert_classify() {
    local status="$1" body="$2" want="$3" curl_exit="${4:-0}" got
    got="$(probe_classify "${status}" "${body}" "${curl_exit}")"
    if [ "${got}" = "${want}" ]; then
        pass "classify ${status} ${body:-<empty>} (curl ${curl_exit}) -> ${got}"
    else
        bad "classify ${status} ${body:-<empty>} (curl ${curl_exit}) -> ${got}, want ${want}"
    fi
}

# An upstream answered — NXDOMAIN for the probe's nonexistent name is exactly
# the healthy case, and NOERROR is accepted too so the verdict never depends on
# the probe name staying unresolvable.
assert_classify 200 '{"reason":"","response":"","responseType":"RESOLVED","returnCode":"NXDOMAIN"}' resolved
assert_classify 200 '{"reason":"","response":"","responseType":"RESOLVED","returnCode":"NOERROR"}' resolved

# No upstream answered. Blocky's API turns a resolver-chain error into a 500,
# and a SERVFAIL/BOGUS body is the same failure seen from the DNS side.
assert_classify 500 'query failed' failed
assert_classify 502 '' failed
assert_classify 200 '{"responseType":"RESOLVED","returnCode":"SERVFAIL"}' failed
assert_classify 200 '{"responseType":"BOGUS","returnCode":"SERVFAIL"}' failed

# Answered locally, so it says nothing about the upstreams: never warn on these.
# CONDITIONAL belongs here, not with the healthy cases: a conditional upstream
# answering proves nothing about the default group the probe watches.
for local_type in CACHED BLOCKED FILTERED NOTFQDN SPECIAL CUSTOMDNS HOSTSFILE SYNTHESIZED REBIND CONDITIONAL; do
    assert_classify 200 "{\"responseType\":\"${local_type}\",\"returnCode\":\"NOERROR\"}" inconclusive
done
assert_classify 400 'unknown query type' inconclusive
assert_classify 200 'not json at all' inconclusive
assert_classify 200 '{"responseType":"RESOLVED"}' inconclusive

# curl writes 000 when it never got an HTTP response, but 000 alone does not say
# WHY, and the two whys are opposite verdicts. curl's exit code separates them.
#
# Could not connect at all (7 = refused, 6 = DNS, 0 = anything else that left us
# without a status): Blocky is down or still starting, which is Blocky's own
# logging to report and says nothing about the upstreams.
assert_classify 000 '' inconclusive
assert_classify '' '' inconclusive
assert_classify 000 '' inconclusive 7
assert_classify 000 '' inconclusive 6

# Timed out (28) against a listener on 127.0.0.1, where a connection either
# succeeds or is refused at once: Blocky accepted the query and never answered,
# which is the resolver chain hanging on upstreams that swallow packets rather
# than refuse them. That is the silent failure #310 is about, so it must warn.
assert_classify 000 '' failed 28
assert_classify '' '' failed 28

# A real HTTP status is its own evidence; the exit code cannot override it.
assert_classify 200 '{"responseType":"RESOLVED","returnCode":"NXDOMAIN"}' resolved 0
assert_classify 500 'query failed' failed 0

# probe_once is the exchange the service loop runs, crossed through the same
# interface: curl is shadowed by a shell function that replays what the real
# curl -w '\n%{http_code}' writes, plus its exit code. Nothing re-types the
# split between curl's output and probe_classify; that stays inside the module.
FAKE_CURL_OUTPUT=""
FAKE_CURL_EXIT=0
curl() {
    printf '%s\n' "$*" >"${tmp}/curl-args"
    printf '%s' "${FAKE_CURL_OUTPUT}"
    return "${FAKE_CURL_EXIT}"
}

assert_probe_once() {
    local output="$1" curl_exit="$2" want="$3" got
    FAKE_CURL_OUTPUT="${output}"
    FAKE_CURL_EXIT="${curl_exit}"
    got="$(probe_once "http://127.0.0.1:4000" 30)"
    if [ "${got}" = "${want}" ]; then
        pass "probe_once $(printf '%q' "${output}") (curl ${curl_exit}) -> ${got}"
    else
        bad "probe_once $(printf '%q' "${output}") (curl ${curl_exit}) -> ${got}, want ${want}"
    fi
}

assert_probe_once "$(printf '{"responseType":"RESOLVED","returnCode":"NXDOMAIN"}\n200')" 0 resolved
assert_probe_once "$(printf 'query failed\n500')" 0 failed
# The status is taken after the LAST newline, so a multi-line body still splits.
assert_probe_once "$(printf 'query\nfailed\n500')" 0 failed
assert_probe_once "$(printf '\n000')" 7 inconclusive
assert_probe_once "$(printf '\n000')" 28 failed
# curl produced nothing at all, not even a status.
assert_probe_once '' 7 inconclusive
assert_probe_once '' 28 failed

# The exchange it makes: the query endpoint under the given base, the given
# timeout as curl's budget, and a fresh probe name in the request body.
FAKE_CURL_OUTPUT="$(printf '\n000')"
FAKE_CURL_EXIT=7
probe_once "http://127.0.0.1:4000" 30 >/dev/null
curl_args="$(cat "${tmp}/curl-args")"
case "${curl_args}" in
    *" http://127.0.0.1:4000/api/query") pass "probe_once posts to <base>/api/query" ;;
    *) bad "probe_once request target unexpected: ${curl_args}" ;;
esac
case "${curl_args}" in
    *"-m 30 "*) pass "probe_once passes the timeout to curl" ;;
    *) bad "probe_once did not pass the timeout: ${curl_args}" ;;
esac
case "${curl_args}" in
    *'"query":"p'*'.blocky-addon-probe"'*) pass "probe_once queries a fresh probe name" ;;
    *) bad "probe_once request body unexpected: ${curl_args}" ;;
esac
unset -f curl

# The probe name must be a two-label name (so fqdn_only cannot reject it) under
# a nonexistent TLD, and must differ per call so Blocky's cache is never hit.
name_a="$(probe_query_name)"
name_b="$(probe_query_name)"
if [ "${name_a}" != "${name_b}" ]; then
    pass "probe_query_name varies per call"
else
    bad "probe_query_name repeated itself: ${name_a}"
fi
if [ "${name_a%.*}" != "${name_a}" ] && [ -n "${name_a%%.*}" ]; then
    pass "probe_query_name is multi-label: ${name_a}"
else
    bad "probe_query_name is not multi-label: ${name_a}"
fi
case "${name_a}" in
    *.blocky-addon-probe) pass "probe_query_name uses the self-identifying suffix" ;;
    *) bad "probe_query_name suffix unexpected: ${name_a}" ;;
esac
case "${name_a}" in
    *[!a-z0-9.-]*) bad "probe_query_name has non-hostname characters: ${name_a}" ;;
    *) pass "probe_query_name is hostname-safe" ;;
esac

# probe_observe: the ADR-0012 rules the service loop used to hold as locals.
# Each sequence starts from a fresh probe_reset and feeds verdicts in order;
# the actions it reports are what the loop turns into log lines.
assert_observe() {
    local desc="$1" verdicts="$2" want_actions="$3" want_level="$4" verdict actions=""
    probe_reset
    for verdict in ${verdicts}; do
        probe_observe "${verdict}"
        actions="${actions:+${actions} }${PROBE_ACTION}"
    done
    if [ "${actions}" = "${want_actions}" ] && [ "${PROBE_LEVEL}" = "${want_level}" ]; then
        pass "observe ${desc}"
    else
        bad "observe ${desc}: actions '${actions}' level ${PROBE_LEVEL}, want '${want_actions}' level ${want_level}"
    fi
}

assert_observe "nothing yet is unknown" "" "" unknown
assert_observe "first resolve verifies, later ones are quiet" \
    "resolved resolved" "verified none" healthy
assert_observe "one failure stays quiet" "failed" "none" unknown
assert_observe "two consecutive failures warn" "failed failed" "none warn" failing
assert_observe "a healthy add-on warns after two failures too" \
    "resolved failed failed" "verified none warn" failing
# "Consecutive" means consecutive: anything in between resets the run.
assert_observe "inconclusive breaks the failure run" \
    "failed inconclusive failed" "none none none" unknown
assert_observe "a resolve breaks the failure run" \
    "resolved failed resolved failed" "verified none none none" healthy
# Inconclusive is no statement about the upstreams: the level freezes.
assert_observe "inconclusive from unknown stays unknown" "inconclusive" "none" unknown
assert_observe "inconclusive while failing keeps failing" \
    "failed failed inconclusive" "none warn none" failing
assert_observe "inconclusive while healthy keeps healthy" \
    "resolved inconclusive" "verified none" healthy
assert_observe "recovery is reported once" \
    "failed failed resolved resolved" "none warn recovered none" healthy
# Re-warn after twelve more failed probes, so a log opened mid-outage explains
# itself; inconclusive probes in between neither count nor restart the cadence.
assert_observe "re-warns after twelve more failures" \
    "failed failed $(printf 'failed %.0s' {1..12})" \
    "none warn $(printf 'none %.0s' {1..11})warn" failing
assert_observe "inconclusive does not restart the re-warn cadence" \
    "failed failed $(printf 'failed %.0s' {1..6})inconclusive $(printf 'failed %.0s' {1..6})" \
    "none warn $(printf 'none %.0s' {1..6})none $(printf 'none %.0s' {1..5})warn" failing
assert_observe "a new outage after recovery warns at the threshold again" \
    "failed failed resolved failed failed" "none warn recovered none warn" failing

probe_reset
probe_observe failed
probe_observe inconclusive
if [ "${PROBE_LAST_VERDICT}" = "inconclusive" ] && [ "${PROBE_LEVEL}" = "unknown" ]; then
    pass "observe records the last verdict apart from the level"
else
    bad "observe last verdict ${PROBE_LAST_VERDICT} level ${PROBE_LEVEL}, want inconclusive unknown"
fi

if [ "${fail}" -eq 0 ]; then
    echo "All guard checks passed."
else
    echo "Guard checks failed."
    exit 1
fi
