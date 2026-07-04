// ============================================================================
// Single source for the throwaway-container render (ADR-0003's Linux fallback),
// shared by two consumers so they can never drift:
//   - scripts/check.mjs        EXECUTES it (dockerRenderArgs, for spawn)
//   - scripts/render-test/run.mjs  PRINTS it as a copy-paste hint (dockerRenderHint)
//
// The container's `pnpm install` is ISOLATED from the host: node_modules is
// masked with a private volume so the Linux-resolved tree never overwrites the
// developer's platform-resolved one, and the pnpm store is a named cache volume
// so the isolated install stays fast. The repo bind-mount still persists the
// provisioned tempio/blocky binaries under scripts/render-test/.bin. See ADR-0008.
// ============================================================================

export const DOCKER_RENDER_IMAGE = "node:24-bookworm-slim";

// The in-container command; `--update` regenerates goldens (run.mjs's local-only
// path), which the execute-side (check.mjs) never uses.
const renderCmd = (update) =>
  `corepack enable && pnpm install --frozen-lockfile && node scripts/render-test/run.mjs${
    update ? " --update" : ""
  }`;

// docker run arguments for child_process spawn. `repoRoot` is bind-mounted at
// /work (see the module header for why node_modules and the store are volumes).
export function dockerRenderArgs(repoRoot, { update = false } = {}) {
  return [
    "run", "--rm",
    "-e", "CI=true",
    "-e", "npm_config_store_dir=/pnpm-store",
    "--mount", `type=bind,source=${repoRoot},target=/work`,
    "--mount", "type=volume,target=/work/node_modules",
    "--mount", "type=volume,source=blocky-render-pnpm-store,target=/pnpm-store",
    "-w", "/work",
    DOCKER_RENDER_IMAGE,
    "sh", "-c",
    renderCmd(update),
  ];
}

// The same command as a copy-pasteable shell one-liner for a human-facing hint.
export function dockerRenderHint({ update = false } = {}) {
  return [
    `  docker run --rm -e CI=true -e npm_config_store_dir=/pnpm-store \\`,
    `    --mount type=bind,source="$PWD",target=/work \\`,
    `    --mount type=volume,target=/work/node_modules \\`,
    `    --mount type=volume,source=blocky-render-pnpm-store,target=/pnpm-store \\`,
    `    -w /work ${DOCKER_RENDER_IMAGE} \\`,
    `    sh -c '${renderCmd(update)}'`,
  ].join("\n");
}
