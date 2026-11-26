#!/usr/bin/env node
// ============================================================================
// Render-harness entry — `pnpm check:render [fixture]` / `pnpm render:update`.
//
// Owns the platform decision for the render harness (ADR-0008): on Linux it
// runs run.mjs bare; anywhere else it runs the same run.mjs inside the
// throwaway container from docker-render.mjs. Arguments pass through unchanged,
// so one fixture or `--update` works the same on every OS. run.mjs itself stays
// Linux-only and refusing (ADR-0003): its goldens are authoritative only from
// the shipped Linux binaries.
//
// Exit status is run.mjs's own, or one of RENDER_CANTRUN_EXITS when the render
// could not run at all — `pnpm check` (which calls this script) reports those
// as ⚠ rather than ✗.
// ============================================================================

import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { dockerRenderArgs } from "./docker-render.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "..", "..");
const harnessArgs = process.argv.slice(2);

// A docker CLI that can talk to its daemon but never gets a response must not
// wedge the render forever — cap the probe and the render container.
const DOCKER_PROBE_TIMEOUT_MS = 15_000;
const DOCKER_RENDER_TIMEOUT_MS = 15 * 60_000;

// Exit with the child's status, mapping "never ran / killed" onto the
// can't-run codes documented in docker-render.mjs.
function exitWith(result, what) {
  if (result.error?.code === "ETIMEDOUT") {
    console.error(`\n! ${what} timed out`);
    process.exit(124);
  }
  if (result.error || result.status === null) {
    const reason = result.error?.message ?? `terminated by signal ${result.signal ?? "unknown"}`;
    console.error(`\n! could not run ${what}: ${reason}`);
    process.exit(127);
  }
  process.exit(result.status);
}

if (process.platform === "linux") {
  const result = spawnSync(process.execPath, [path.join(HERE, "run.mjs"), ...harnessArgs], {
    cwd: ROOT,
    stdio: "inherit",
  });
  exitWith(result, "the render harness");
}

// `docker version` needs both the binary (else ENOENT) and a running server
// (else non-zero), so a zero exit means the render container can really launch.
const probe = spawnSync("docker", ["version"], {
  cwd: ROOT,
  stdio: "ignore",
  timeout: DOCKER_PROBE_TIMEOUT_MS,
});
if (probe.status !== 0) {
  console.error(
    "! The render harness runs the shipped Linux tempio/blocky binaries; off Linux it needs a running Docker daemon, and none is reachable. Start Docker, or run on Linux."
  );
  process.exit(125);
}

console.error(`Rendering in a throwaway Linux container (${process.platform} host)…`);
const result = spawnSync("docker", dockerRenderArgs(ROOT, harnessArgs), {
  cwd: ROOT,
  stdio: "inherit",
  timeout: DOCKER_RENDER_TIMEOUT_MS,
});
exitWith(result, "the render container");
