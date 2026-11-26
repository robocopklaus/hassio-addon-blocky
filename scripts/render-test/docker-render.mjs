// ============================================================================
// Single source for the throwaway-container render (ADR-0003's Linux fallback),
// shared by two consumers so they can never drift:
//   - scripts/render-test/render.mjs  EXECUTES it (dockerRenderArgs, for spawn)
//   - scripts/render-test/run.mjs     PRINTS it as a copy-paste hint (dockerRenderHint)
//
// The container's `pnpm install` is ISOLATED from the host: node_modules is
// masked with a private volume so the Linux-resolved tree never overwrites the
// developer's platform-resolved one, and the pnpm store is a named cache volume
// so the isolated install stays fast. The repo bind-mount still persists the
// provisioned tempio/blocky binaries under scripts/render-test/.bin. See ADR-0008.
// ============================================================================

export const DOCKER_RENDER_IMAGE = "node:24-bookworm-slim";

// The in-container command. Harness arguments (a fixture name, `--update`) reach
// run.mjs as sh's positional parameters via "$@", so they are passed through
// verbatim and never spliced into the command string.
const RENDER_SCRIPT =
  'corepack enable && pnpm install --frozen-lockfile && node scripts/render-test/run.mjs "$@"';

// Exit codes meaning the render COULD NOT RUN, as opposed to ran and failed
// (run.mjs itself only exits 0 or 1). `pnpm check` reports these as ⚠, not ✗:
//   124      the render container timed out (render.mjs)
//   125      no reachable Docker daemon (render.mjs), or docker run's own failure
//            (image pull, daemon, bad option)
//   126/127  docker run could not invoke the container command, or the render
//            process could not be launched at all (render.mjs)
export const RENDER_CANTRUN_EXITS = new Set([124, 125, 126, 127]);

// docker run arguments for child_process spawn. `repoRoot` is bind-mounted at
// /work (see the module header for why node_modules and the store are volumes).
export function dockerRenderArgs(repoRoot, harnessArgs = []) {
  return [
    "run", "--rm",
    "-e", "CI=true",
    "-e", "npm_config_store_dir=/pnpm-store",
    "--mount", `type=bind,source=${repoRoot},target=/work`,
    "--mount", "type=volume,target=/work/node_modules",
    "--mount", "type=volume,source=blocky-render-pnpm-store,target=/pnpm-store",
    "-w", "/work",
    DOCKER_RENDER_IMAGE,
    "sh", "-c", RENDER_SCRIPT, "sh",
    ...harnessArgs,
  ];
}

// The same command as a copy-pasteable shell one-liner for a human-facing hint.
export function dockerRenderHint(harnessArgs = []) {
  return [
    `  docker run --rm -e CI=true -e npm_config_store_dir=/pnpm-store \\`,
    `    --mount type=bind,source="$PWD",target=/work \\`,
    `    --mount type=volume,target=/work/node_modules \\`,
    `    --mount type=volume,source=blocky-render-pnpm-store,target=/pnpm-store \\`,
    `    -w /work ${DOCKER_RENDER_IMAGE} \\`,
    `    sh -c '${RENDER_SCRIPT}' sh${harnessArgs.map((arg) => ` ${arg}`).join("")}`,
  ].join("\n");
}
