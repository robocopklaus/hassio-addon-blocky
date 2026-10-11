#!/usr/bin/env bash
# ==============================================================================
# ShellCheck over every shell script in the repo: the add-on's rootfs (services,
# cont-init, the guard and probe libraries) and the repo's own scripts/. The one
# list both `pnpm lint:shell` and CI's ShellCheck job run, so a script added
# under either tree is linted without anyone updating a glob.
#
# rootfs services carry no .sh extension, so a file counts as shell by its
# shebang or a `# shellcheck shell=` directive, not by its name.
# ==============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

files=()
while IFS= read -r -d '' file; do
    first="$(head -n 1 "${file}")"
    case "${first}" in
        # *sh* covers sh, bash and with-contenv bashio alike.
        '#!'*sh* | '# shellcheck shell='*) files+=("${file}") ;;
    esac
done < <(find blocky/rootfs scripts -type f ! -path '*/node_modules/*' -print0 | sort -z)

if [ "${#files[@]}" -eq 0 ]; then
    echo "lint-shell: no shell scripts found; the file discovery is broken." >&2
    exit 1
fi

printf 'ShellCheck: %s files\n' "${#files[@]}"
shellcheck "${files[@]}"
echo "ShellCheck passed."
