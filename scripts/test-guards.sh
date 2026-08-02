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
# The probe's pure classifier: it turns one /api/query exchange into a verdict
# about the UPSTREAMS, never about the add-on. It is not format-coupled to the
# rendered config (it reads Blocky's API), but it is coupled to that response
# shape, so it is pinned here the same way. See ADR-0012.

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
# logging to report, not an upstream verdict.
assert_classify 000 '' unreachable
assert_classify '' '' unreachable
assert_classify 000 '' unreachable 7
assert_classify 000 '' unreachable 6

# Timed out (28) against a listener on 127.0.0.1, where a connection either
# succeeds or is refused at once: Blocky accepted the query and never answered,
# which is the resolver chain hanging on upstreams that swallow packets rather
# than refuse them. That is the silent failure #310 is about, so it must warn.
assert_classify 000 '' failed 28
assert_classify '' '' failed 28

# A real HTTP status is its own evidence; the exit code cannot override it.
assert_classify 200 '{"responseType":"RESOLVED","returnCode":"NXDOMAIN"}' resolved 0
assert_classify 500 'query failed' failed 0

# The curl -w split: status after the last newline, everything before it the
# body. This is what feeds probe_classify at runtime, so it is pinned here
# rather than left to the service loop.
assert_split() {
    local response="$1" want="$2" got
    got="$(probe_split_response "${response}")"
    if [ "${got}" = "${want}" ]; then
        pass "split $(printf '%q' "${response}") -> $(printf '%q' "${got}")"
    else
        bad "split $(printf '%q' "${response}") -> $(printf '%q' "${got}"), want $(printf '%q' "${want}")"
    fi
}
assert_split "$(printf '{"returnCode":"NXDOMAIN"}\n200')" '200 {"returnCode":"NXDOMAIN"}'
assert_split "$(printf 'query failed for x\n500')" '500 query failed for x'
assert_split "$(printf '\n000')" '000 '
assert_split '' ' '

# A split response must survive the round trip into a verdict unchanged — this
# is the seam the service loop crosses, so exercise it end to end.
for triple in \
    "$(printf '{"responseType":"RESOLVED","returnCode":"NXDOMAIN"}\n200')|0|resolved" \
    "$(printf 'query failed\n500')|0|failed" \
    "$(printf '\n000')|7|unreachable" \
    "$(printf '\n000')|28|failed"; do
    response="${triple%%|*}"
    want="${triple##*|}"
    curl_exit="${triple#*|}"
    curl_exit="${curl_exit%|*}"
    split="$(probe_split_response "${response}")"
    got="$(probe_classify "${split%% *}" "${split#* }" "${curl_exit}")"
    if [ "${got}" = "${want}" ]; then
        pass "split+classify (curl ${curl_exit}) -> ${got}"
    else
        bad "split+classify (curl ${curl_exit}) -> ${got}, want ${want}"
    fi
done

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

if [ "${fail}" -eq 0 ]; then
    echo "All guard checks passed."
else
    echo "Guard checks failed."
    exit 1
fi
