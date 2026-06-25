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

if [ "${fail}" -eq 0 ]; then
    echo "All guard checks passed."
else
    echo "Guard checks failed."
    exit 1
fi
