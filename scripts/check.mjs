#!/usr/bin/env node
// ============================================================================
// Single verification aggregate — `pnpm check`.
//
// One local seam over the three translation-pipeline checks:
//   contracts  static three-file parity        node, dependency-free, any OS
//   guards     guard fns vs render goldens      bash, any OS
//   render     real tempio + blocky render      Linux-only binaries
//
// contracts + guards are instant and ALWAYS run — both results are collected,
// with no short-circuit between them. render runs only if both passed, through
// render-test/render.mjs — the same entry as `pnpm check:render`, which owns the
// platform decision: bare on Linux, else the throwaway Docker container
// documented in ADR-0003 (run.mjs stays Linux-only and refusing). If render
// cannot run (off-Linux and Docker unavailable, an image/daemon failure, or a
// timeout) render.mjs exits with a can't-run code, reported here as ⚠ CANTRUN;
// the aggregate exits non-zero for it, so a green result never hides an
// unverified render. See ADR-0008.
//
// CI does NOT use this aggregate: lint.yml runs the three as lean parallel jobs.
// See docs/adr/0008-single-check-aggregate.md.
// ============================================================================

import { spawnSync } from "node:child_process";
import { writeSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { RENDER_CANTRUN_EXITS } from "./render-test/docker-render.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

const PASS = "pass";
const FAIL = "fail";
const SKIPPED = "skipped";
const CANTRUN = "cantrun";

// Write synchronously to a fd. Child steps stream via spawnSync stdio:"inherit"
// while the event loop is blocked, so an async process.stdout.write for a heading
// would drain only after the child output it labels — scrambling piped/no-TTY
// logs. writeSync flushes before the spawnSync that follows.
function out(msg) {
  writeSync(1, msg);
}
function err(msg) {
  writeSync(2, msg);
}
function heading(label) {
  out(`\n── ${label} ──\n`);
}

// Run a command with inherited stdio. Returns a tagged result:
//   { ok: true }                 exit 0
//   { launchError: Error }       never started / killed (ENOENT, timeout, signal)
//   { code: <non-zero int> }     child ran and exited non-zero
// Distinguishing "could not launch" from "ran and failed" lets callers classify
// an environmental failure as CANTRUN rather than a real check failure.
function run(cmd, args, opts = {}) {
  const r = spawnSync(cmd, args, { cwd: ROOT, stdio: "inherit", ...opts });
  if (r.error) return { launchError: r.error }; // ENOENT, ETIMEDOUT, …
  if (r.status === null) {
    return { launchError: new Error(`${cmd} terminated without an exit code (signal ${r.signal ?? "unknown"})`) };
  }
  return r.status === 0 ? { ok: true } : { code: r.status };
}

// Runs a fast, any-OS check (contracts / guards). A launch failure (e.g. node or
// bash missing from PATH) is surfaced explicitly instead of masquerading as a
// silent check failure, then counted as FAIL.
function runFast(name, cmd, args) {
  heading(name);
  const r = run(cmd, args);
  if (r.launchError) {
    err(`\n! could not launch ${name} (${cmd}): ${r.launchError.message}\n`);
    return FAIL;
  }
  return r.ok ? PASS : FAIL;
}

// --- contracts + guards (always) --------------------------------------------
const contracts = runFast("contracts", "node", ["scripts/check-config-contract.mjs"]);
const guards = runFast("guards", "bash", ["scripts/test-guards.sh"]);

// --- render (gated on the fast two) -----------------------------------------
let render;
if (contracts !== PASS || guards !== PASS) {
  render = SKIPPED;
} else {
  // Environment problems (no Docker, image/daemon error, timeout) arrive as a
  // can't-run exit code and degrade to CANTRUN, not a misleading FAIL.
  heading(process.platform === "linux" ? "render" : "render (via Docker)");
  const r = run("node", ["scripts/render-test/render.mjs"]);
  if (r.ok) render = PASS;
  else if (r.launchError || RENDER_CANTRUN_EXITS.has(r.code)) render = CANTRUN;
  else render = FAIL;
}

// --- summary -----------------------------------------------------------------
const MARK = {
  [PASS]: "✓", // check
  [FAIL]: "✗", // cross
  [CANTRUN]: "⚠", // warn
  [SKIPPED]: "–", // dash
};
const NOTE = {
  [SKIPPED]: "  skipped (fix the above first)",
  [CANTRUN]: "  could not run — render did not verify (Docker unavailable, image/daemon error, or timeout); run on Linux or start Docker",
};

out("\n── summary ──\n");
for (const [name, state] of [
  ["contracts", contracts],
  ["guards", guards],
  ["render", render],
]) {
  out(`  ${MARK[state]}  ${name.padEnd(10)}${NOTE[state] ?? ""}\n`);
}

// A can't-run render fails the gate just like a real failure (no false green). A
// skipped render never fails on its own — it only happens when a fast check
// already failed, which is what turns the run red.
const failed = [contracts, guards, render].some((s) => s === FAIL || s === CANTRUN);
out(failed ? "\n✗ pnpm check failed\n" : "\n✓ pnpm check passed\n");
process.exit(failed ? 1 : 0);
