#!/usr/bin/env node
// ============================================================================
// Release-notes smoke test — `pnpm check:release-notes`.
//
// Feeds a fixed set of conventional commits through the exact generateNotes
// semantic-release runs (release-notes-generator + the conventionalcommits
// preset from .releaserc.json) and asserts the rendered notes carry the
// expected sections and entries.
//
// Why: the preset and the writer bundled by release-notes-generator must be the
// same generation. A preset major that outpaces the writer has twice slipped
// past every other check — #265 (preset v10 on writer 8) silently emptied the
// v5.1.0 release notes (fixed in #272), and #274 would have made generateNotes
// throw and block the release. Neither is visible without rendering notes.
//
// Synthetic commits keep it independent of git history, so CI's shallow
// checkout needs no tags.
// ============================================================================

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { generateNotes } from "@semantic-release/release-notes-generator";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

// Use the plugin config the release actually runs with, not a copy of it.
const releaserc = JSON.parse(readFileSync(path.join(ROOT, ".releaserc.json"), "utf8"));
const entry = releaserc.plugins.find(
  (p) => (Array.isArray(p) ? p[0] : p) === "@semantic-release/release-notes-generator",
);
const pluginConfig = Array.isArray(entry) ? entry[1] : {};

const COMMITS = [
  { hash: "1111111111111111111111111111111111111111", message: "feat: add smoke test feature (#1)" },
  { hash: "2222222222222222222222222222222222222222", message: "fix(deps): repair smoke test bug (#2)" },
  { hash: "3333333333333333333333333333333333333333", message: "chore: hidden smoke test chore" },
];

const EXPECTED = ["### Features", "add smoke test feature", "### Bug Fixes", "repair smoke test bug"];

let notes;
try {
  notes = await generateNotes(pluginConfig, {
    cwd: ROOT,
    options: { repositoryUrl: "https://github.com/robocopklaus/hassio-addon-blocky" },
    commits: COMMITS,
    lastRelease: { gitTag: "v1.0.0", version: "1.0.0" },
    nextRelease: { gitTag: "v1.1.0", version: "1.1.0" },
    logger: { log() {}, error: console.error },
  });
} catch (error) {
  console.error("✗ generateNotes threw — the changelog preset and the bundled writer are likely out of step:");
  console.error(`  ${error.message}`);
  process.exit(1);
}

const missing = EXPECTED.filter((s) => !notes.includes(s));
if (missing.length > 0) {
  console.error("✗ release notes are missing expected content:");
  for (const s of missing) console.error(`  - ${s}`);
  console.error("\nrendered notes:\n" + notes);
  process.exit(1);
}

console.log("✓ release notes render with Features and Bug Fixes");
