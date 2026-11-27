#!/usr/bin/env bash
# ==============================================================================
# Bump smoke — `scripts/bump-smoke.sh <old-tag> <new-tag>`
#
# A manual, networked run of the old and new Blocky release binaries against
# what the render harness cannot see (GLOSSARY.md "Bump smoke"): the consumed
# API, the CLI the image runs, and the live default denylists. Evidence for a
# bump review (docs/agents/blocky-bump-review.md), never its gate: render-test
# stays the gate of record, and this never runs in CI — it depends on live
# upstreams and live list downloads.
#
# Checks (the new tag unless stated):
#   1. The defaults golden, unmodified: `blocky validate`, then a live start.
#      Every default denylist must import entries without errors, and no ERROR
#      line may appear. WARN lines are listed for attention, never failed.
#   2. The consumed API: /api/blocking/status, and /api/query for a resolvable
#      name, the probe's own NXDOMAIN name, and a name on the default lists.
#   3. The CLI: `blocky blocking status` (the HEALTHCHECK) exits 0, and
#      `blocky validate` (config.sh's abort) exits non-zero on a bad config.
#   4. Old AND new against unreachable upstreams: the HTTP status and the
#      probe's verdict must match, and the new verdict must be `failed` — the
#      premise the probe stands on (ADR-0012).
#
# Verdicts come from the probe module itself (upstream_probe.sh), and the curl
# budget is the probe service's own PROBE_TIMEOUT, so this sees what the probe
# would see.
#
# Runs in a throwaway container from the add-on's own base image, with the repo
# bind-mounted read-only; nothing is installed on the host. Needs Docker and
# internet access.
#
# Exit status: 0 every check passed; 1 a check failed or old and new differ;
# 2 the smoke could not run (no Docker, a download or checksum failure, Blocky
# never came up), so a run that did not happen never reads as a pass.
# ==============================================================================
set -euo pipefail

readonly EXIT_FAIL=1
readonly EXIT_CANTRUN=2

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
    echo "usage: scripts/bump-smoke.sh <old-tag> <new-tag>   e.g. v0.35.0 v0.37.0" >&2
    exit "${EXIT_CANTRUN}"
}

cant_run() {
    printf '\n! bump smoke could not run: %s\n' "$1" >&2
    exit "${EXIT_CANTRUN}"
}

# A tag ends up in a download URL and a file name; refuse anything that is not
# shaped like a release tag rather than quote it everywhere.
check_tag() {
    [[ "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.+-][0-9A-Za-z.+-]*)?$ ]] ||
        cant_run "'$1' is not a Blocky release tag (expected e.g. v0.37.0)"
}

# ---- host side ----------------------------------------------------------------
# Kept to what macOS's bash 3.2 runs: everything else happens in the container.

host_main() {
    [ "$#" -eq 2 ] || usage
    check_tag "$1"
    check_tag "$2"

    command -v docker >/dev/null 2>&1 || cant_run "docker is not installed"
    local server_arch
    server_arch="$(docker version --format '{{.Server.Arch}}' 2>/dev/null)" ||
        cant_run "no reachable Docker daemon — start Docker"

    # The add-on's own base image: same Alpine, same CA bundle Blocky fetches
    # its lists with in production. Version read from the Dockerfile pin.
    local base_version image_arch image
    base_version="$(sed -n 's/^ARG HOME_ASSISTANT_BASE_VERSION=//p' "${ROOT}/blocky/Dockerfile")"
    [ -n "${base_version}" ] || cant_run "HOME_ASSISTANT_BASE_VERSION not found in blocky/Dockerfile"
    case "${server_arch}" in
        amd64) image_arch=amd64 ;;
        arm64) image_arch=aarch64 ;;
        *) cant_run "Docker host architecture '${server_arch}' has no add-on base image" ;;
    esac
    image="ghcr.io/home-assistant/${image_arch}-base:${base_version}"

    echo "Bump smoke ${1} → ${2} in a throwaway ${image} container…" >&2
    # --entrypoint skips the base image's s6 init; --init still forwards Ctrl-C.
    local status=0
    docker run --rm --init \
        --entrypoint /bin/bash \
        --mount "type=bind,source=${ROOT},target=/work,readonly" \
        -w /work \
        "${image}" \
        /work/scripts/bump-smoke.sh --in-container "$1" "$2" || status=$?

    # Our own codes pass through; anything else is docker failing to run it.
    case "${status}" in
        0 | "${EXIT_FAIL}" | "${EXIT_CANTRUN}") exit "${status}" ;;
        *) cant_run "the container exited ${status} (docker run itself failed?)" ;;
    esac
}

# ---- container side -------------------------------------------------------------

readonly API="http://127.0.0.1:4000"
readonly GOLDEN="/work/scripts/render-test/fixtures/defaults/expected.yml"
readonly PROBE_RUN="/work/blocky/rootfs/etc/services.d/upstream-probe/run"
# Stable names for step 2: IANA-reserved and always resolvable, and a name the
# default StevenBlack list has carried for years.
readonly RESOLVED_NAME="example.com"
readonly BLOCKED_NAME="doubleclick.net"

# The runbook's dispositions (docs/agents/blocky-bump-review.md), so the summary
# says what each failure means for the merge, not just that it failed.
readonly HOLD="Hold"
readonly REPIN="Note + re-pin scripts/test-guards.sh"
readonly INVESTIGATE="Investigate before Go"

passes=()
failures=()
attention=()
blocky_pid=""

pass() {
    passes+=("$1")
    printf '  ok    %s\n' "$1"
}
fail() {
    failures+=("[$1] $2")
    printf '  FAIL  [%s] %s\n' "$1" "$2"
}
note_attention() {
    attention+=("$1")
    printf '  WARN  %s\n' "$1"
}

stop_blocky() {
    if [ -n "${blocky_pid}" ]; then
        kill "${blocky_pid}" 2>/dev/null || true
        wait "${blocky_pid}" 2>/dev/null || true
        blocky_pid=""
    fi
}

# fetch_blocky <tag> -> path of the verified binary
#
# The Linux build for this container's architecture, verified against the
# release's blocky_checksums.txt — the same check render-test and the
# Dockerfile make.
fetch_blocky() {
    local tag="$1" arch tarball dir base
    case "$(uname -m)" in
        x86_64) arch=x86_64 ;;
        aarch64) arch=arm64 ;;
        *) cant_run "no Blocky Linux build for $(uname -m)" ;;
    esac
    tarball="blocky_${tag}_Linux_${arch}.tar.gz"
    dir="${WORK}/${tag}"
    base="https://github.com/0xERR0R/blocky/releases/download/${tag}"
    mkdir -p "${dir}"
    curl -fsSL -o "${dir}/${tarball}" "${base}/${tarball}" ||
        cant_run "download of ${base}/${tarball} failed (no internet, or no such tag?)"
    curl -fsSL -o "${dir}/checksums.txt" "${base}/blocky_checksums.txt" ||
        cant_run "download of ${base}/blocky_checksums.txt failed"
    grep -E "^[0-9a-f]{64}  ${tarball}\$" "${dir}/checksums.txt" >"${dir}/expected.sha256" ||
        cant_run "no checksum for ${tarball} in blocky_checksums.txt"
    (cd "${dir}" && sha256sum -c -s expected.sha256) ||
        cant_run "sha256 mismatch for ${tarball}"
    tar -xzf "${dir}/${tarball}" -C "${dir}" blocky ||
        cant_run "could not unpack blocky from ${tarball}"
    echo "${dir}/blocky"
}

# start_blocky <binary> <config> <log>
#
# Starts Blocky in the background and waits for its HTTP listener. A Blocky
# that never answers cannot be smoke-tested at all, so that is can't-run.
start_blocky() {
    local bin="$1" config="$2" log="$3" i
    "${bin}" --config "${config}" >"${log}" 2>&1 &
    blocky_pid=$!
    for i in $(seq 1 90); do
        if ! kill -0 "${blocky_pid}" 2>/dev/null; then
            blocky_pid=""
            tail -n 20 "${log}" >&2
            cant_run "Blocky exited during startup (log tail above)"
        fi
        if [ "$(curl -s -o /dev/null -w '%{http_code}' "${API}/api/blocking/status")" != "000" ]; then
            return 0
        fi
        sleep 1
    done
    tail -n 20 "${log}" >&2
    cant_run "Blocky did not open ${API} within ${i}s (log tail above)"
}

# query <name> [budget] -> sets Q_STATUS, Q_BODY, Q_EXIT, Q_TIME
#
# The probe's own exchange (probe_once in upstream_probe.sh), with the elapsed
# time added. Q_STATUS is 000 when no HTTP response arrived.
query() {
    local name="$1" budget="${2:-10}" out
    out="$(curl -s -m "${budget}" -X POST \
        -H 'Content-Type: application/json' \
        -d "{\"query\":\"${name}\",\"type\":\"A\"}" \
        -w '\n%{http_code} %{time_total}' \
        "${API}/api/query")" && Q_EXIT=0 || Q_EXIT=$?
    local tail_line="${out##*$'\n'}"
    Q_BODY="${out%$'\n'*}"
    [ "${Q_BODY}" != "${out}" ] || Q_BODY=""
    Q_BODY="${Q_BODY%$'\n'}"
    Q_STATUS="${tail_line%% *}"
    Q_TIME="${tail_line#* }"
}

# field <name> <json> -> the string value, or nothing for any other shape.
field() { jq -r --arg f "$1" '(.[$f]? // "") | strings' <<<"$2" 2>/dev/null || true; }

# ---- step 1: the defaults golden, live -------------------------------------

step_defaults() {
    local new="$1" bin="$2" log="${WORK}/defaults.log" src line count
    echo
    echo "== 1. Defaults golden, live (${new})"

    if ! "${bin}" validate --config "${GOLDEN}" >"${WORK}/validate.log" 2>&1; then
        sed 's/^/        /' "${WORK}/validate.log"
        fail "${HOLD}" "blocky validate rejects the defaults golden (render-test should be red too)"
        return 1
    fi
    pass "blocky validate accepts the defaults golden"

    # Blocky's default loading strategy imports every list before the server
    # starts, so once HTTP answers the import lines are all in the log.
    start_blocky "${bin}" "${GOLDEN}" "${log}"
    pass "Blocky started on the defaults golden"

    # The golden's denylist sources. Coupled to our own golden's layout: the
    # quoted entries between `denylists:` and `clientGroupsBlock:`.
    local sources=()
    while IFS= read -r src; do sources+=("${src}"); done < <(
        sed -n '/^  denylists:/,/^  clientGroupsBlock:/s/^ *- "\(.*\)"$/\1/p' "${GOLDEN}"
    )
    [ "${#sources[@]}" -gt 0 ] || cant_run "found no denylist sources in ${GOLDEN}"

    for src in "${sources[@]}"; do
        line="$(grep -F "import succeeded" "${log}" | grep -F "source=${src}" | tail -n 1 || true)"
        count="$(sed -n 's/.*import succeeded count=\([0-9]*\) .*/\1/p' <<<"${line}")"
        if [ -z "${count}" ]; then
            fail "${INVESTIGATE}" "denylist did not import: ${src}"
        elif [ "${count}" -eq 0 ]; then
            fail "${INVESTIGATE}" "denylist imported 0 entries: ${src}"
        else
            pass "denylist imported ${count} entries: ${src}"
        fi
    done
}

# Read after steps 2 and 3 so the scan covers the whole live run.
scan_log() {
    local log="${WORK}/defaults.log" line
    echo
    echo "== 1b. Log lines of the defaults run"
    while IFS= read -r line; do
        fail "${INVESTIGATE}" "list parse error: ${line}"
    done < <(grep -F "parse error" "${log}" || true)
    while IFS= read -r line; do
        fail "${INVESTIGATE}" "error log line: ${line}"
    done < <(grep -E '^\[[^]]*\] +(ERROR|FATAL|PANIC) ' "${log}" | grep -vF "parse error" || true)
    while IFS= read -r line; do
        note_attention "${line}"
    done < <(grep -E '^\[[^]]*\] +WARN(ING)? ' "${log}" | grep -vF "parse error" || true)
    if ! grep -qE '^\[[^]]*\] +(ERROR|FATAL|PANIC|WARN(ING)?) ' "${log}"; then
        pass "no error or warn lines in the defaults run"
    fi
}

# ---- step 2: the consumed API ------------------------------------------------

# expect_query <label> <name> <responseType> <returnCode> <mismatch disposition>
expect_query() {
    local label="$1" name="$2" want_type="$3" want_code="$4" disp="$5" rtype rcode
    query "${name}"
    if [ "${Q_STATUS}" != "200" ]; then
        fail "${HOLD}" "/api/query (${label}) returned HTTP ${Q_STATUS}, not 200"
        return 1
    fi
    rtype="$(field responseType "${Q_BODY}")"
    rcode="$(field returnCode "${Q_BODY}")"
    if [ "${rtype}" = "${want_type}" ] && [ "${rcode}" = "${want_code}" ]; then
        pass "/api/query ${label}: ${rtype}/${rcode}"
        return 0
    fi
    fail "${disp}" "/api/query ${label}: want ${want_type}/${want_code}, got ${rtype:-?}/${rcode:-?} — ${Q_BODY}"
    return 1
}

step_api() {
    local status body probe_name verdict
    echo
    echo "== 2. Consumed API"

    body="$(curl -s -m 10 -w '\n%{http_code}' "${API}/api/blocking/status")" || true
    status="${body##*$'\n'}"
    body="${body%$'\n'*}"
    body="${body%$'\n'}"
    if [ "${status}" != "200" ]; then
        fail "${HOLD}" "/api/blocking/status (the Supervisor watchdog) returned HTTP ${status}"
    elif [ "$(jq -r '(.enabled? | type)' <<<"${body}" 2>/dev/null)" != "boolean" ]; then
        fail "${REPIN}" "/api/blocking/status has no boolean 'enabled': ${body}"
    else
        pass "/api/blocking/status: 200 ${body}"
    fi

    expect_query "resolvable name (${RESOLVED_NAME})" "${RESOLVED_NAME}" RESOLVED NOERROR "${REPIN}" || true

    # The probe's own name, and its own verdict on the answer.
    probe_name="$(probe_query_name)"
    if expect_query "probe name (${probe_name})" "${probe_name}" RESOLVED NXDOMAIN "${REPIN}"; then
        verdict="$(probe_classify "${Q_STATUS}" "${Q_BODY}" "${Q_EXIT}")"
        if [ "${verdict}" = "resolved" ]; then
            pass "probe_classify reads the probe answer as resolved"
        else
            fail "${REPIN}" "probe_classify reads the probe answer as ${verdict}, not resolved"
        fi
    fi

    # A name that resolves instead of blocking means the list moved, not the API.
    query "${BLOCKED_NAME}"
    if [ "${Q_STATUS}" = "200" ] && [ "$(field responseType "${Q_BODY}")" = "RESOLVED" ]; then
        fail "${INVESTIGATE}" "${BLOCKED_NAME} resolved — no longer on the default lists? ${Q_BODY}"
    else
        expect_query "blocked name (${BLOCKED_NAME})" "${BLOCKED_NAME}" BLOCKED NOERROR "${REPIN}" || true
    fi
}

# ---- step 3: the CLI ---------------------------------------------------------

step_cli() {
    local bin="$1" rc=0
    echo
    echo "== 3. CLI"

    "${bin}" blocking status >"${WORK}/cli.log" 2>&1 || rc=$?
    if [ "${rc}" -eq 0 ]; then
        pass "blocky blocking status (HEALTHCHECK) exits 0"
    else
        sed 's/^/        /' "${WORK}/cli.log"
        fail "${HOLD}" "blocky blocking status (HEALTHCHECK) exits ${rc}"
    fi

    printf 'upstreams:\n  groups:\n    default:\n      - "nope://192.0.2.1"\n' >"${WORK}/invalid.yml"
    rc=0
    "${bin}" validate --config "${WORK}/invalid.yml" >/dev/null 2>&1 || rc=$?
    if [ "${rc}" -ne 0 ]; then
        pass "blocky validate exits ${rc} on an invalid config"
    else
        fail "${HOLD}" "blocky validate exits 0 on an invalid config — config.sh would no longer abort"
    fi
}

# ---- step 4: chain failure, old vs new ---------------------------------------

readonly CHAIN_FAIL_CONFIG='upstreams:
  groups:
    default:
      - "tcp-tls:192.0.2.1"
      - "192.0.2.2"
  timeout: "1s"
  init:
    strategy: "fast"
ports:
  http:
    - 4000
log:
  level: "info"
'

# chain_failure <tag> <binary> <budget> -> "status verdict time"
chain_failure() {
    local tag="$1" bin="$2" budget="$3" verdict
    printf '%s' "${CHAIN_FAIL_CONFIG}" >"${WORK}/chain-fail.yml"
    start_blocky "${bin}" "${WORK}/chain-fail.yml" "${WORK}/chain-fail-${tag}.log"
    query "$(probe_query_name)" "${budget}"
    stop_blocky
    verdict="$(probe_classify "${Q_STATUS}" "${Q_BODY}" "${Q_EXIT}")"
    echo "${Q_STATUS} ${verdict} ${Q_TIME}"
}

step_chain_failure() {
    local old="$1" old_bin="$2" new="$3" new_bin="$4" budget old_r new_r
    echo
    echo "== 4. Resolver-chain failure, ${old} vs ${new}"

    budget="$(sed -n 's/^readonly PROBE_TIMEOUT=\([0-9]*\).*/\1/p' "${PROBE_RUN}")"
    [ -n "${budget}" ] || cant_run "PROBE_TIMEOUT not found in ${PROBE_RUN}"

    old_r="$(chain_failure "${old}" "${old_bin}" "${budget}")"
    new_r="$(chain_failure "${new}" "${new_bin}" "${budget}")"
    local old_status old_verdict old_time new_status new_verdict new_time
    read -r old_status old_verdict old_time <<<"${old_r}"
    read -r new_status new_verdict new_time <<<"${new_r}"
    printf '  %-10s HTTP %s, verdict %s, %ss (budget %ss)\n' \
        "${old}" "${old_status}" "${old_verdict}" "${old_time}" "${budget}" \
        "${new}" "${new_status}" "${new_verdict}" "${new_time}" "${budget}"

    if [ "${old_status}" = "${new_status}" ] && [ "${old_verdict}" = "${new_verdict}" ]; then
        pass "chain failure unchanged: HTTP ${new_status}, verdict ${new_verdict}"
    else
        fail "${HOLD}" "chain failure changed: ${old} HTTP ${old_status}/${old_verdict} → ${new} HTTP ${new_status}/${new_verdict}"
    fi
    if [ "${new_verdict}" = "failed" ]; then
        pass "the probe reads ${new}'s chain failure as failed"
    else
        fail "${HOLD}" "the probe reads ${new}'s chain failure as ${new_verdict}, not failed — it would stay silent through an outage"
    fi
}

summary() {
    local old="$1" new="$2" line
    echo
    echo "== Summary: bump smoke ${old} → ${new}"
    echo "  ${#passes[@]} passed, ${#failures[@]} failed, ${#attention[@]} for attention"
    for line in "${failures[@]}"; do echo "  FAIL  ${line}"; done
    for line in "${attention[@]}"; do echo "  WARN  ${line}"; done
    if [ "${#failures[@]}" -eq 0 ]; then
        echo "Result: PASS"
    else
        echo "Result: FAIL — see the runbook (docs/agents/blocky-bump-review.md) for each disposition"
    fi
}

container_main() {
    [ "$#" -eq 2 ] || usage
    local old="$1" new="$2" old_bin new_bin
    check_tag "${old}"
    check_tag "${new}"

    # shellcheck source=blocky/rootfs/usr/lib/blocky/upstream_probe.sh
    source /work/blocky/rootfs/usr/lib/blocky/upstream_probe.sh

    WORK="$(mktemp -d)"
    trap 'stop_blocky; rm -rf "${WORK}"' EXIT

    echo "Fetching and verifying ${old} and ${new}…"
    old_bin="$(fetch_blocky "${old}")"
    new_bin="$(fetch_blocky "${new}")"
    echo "  $("${old_bin}" version 2>&1 | grep -m1 -i version || echo "${old}")"
    echo "  $("${new_bin}" version 2>&1 | grep -m1 -i version || echo "${new}")"

    if step_defaults "${new}" "${new_bin}"; then
        step_api
        step_cli "${new_bin}"
        stop_blocky
        scan_log
    fi
    step_chain_failure "${old}" "${old_bin}" "${new}" "${new_bin}"

    summary "${old}" "${new}"
    [ "${#failures[@]}" -eq 0 ] || exit "${EXIT_FAIL}"
}

if [ "${1:-}" = "--in-container" ]; then
    shift
    container_main "$@"
else
    host_main "$@"
fi
