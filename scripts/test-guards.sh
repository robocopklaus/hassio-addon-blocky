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

if [ "${fail}" -eq 0 ]; then
    echo "All guard checks passed."
else
    echo "Guard checks failed."
    exit 1
fi
