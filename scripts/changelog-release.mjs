#!/usr/bin/env node
// ============================================================================
// Changelog release gate: `verify` and `stamp` for blocky/CHANGELOG.md.
//
// blocky/CHANGELOG.md is hand-curated (ADR-0010): a human writes the section
// for the next version and finalizes it before dispatching release.yml. That
// step has nothing behind it, and it has already failed once: v5.3.0 shipped
// with an undated heading. semantic-release calls this script twice:
//
//   verify <V>  verifyReleaseCmd. Runs once the version is computed and before
//               anything is tagged or published (in --dry-run too). A non-zero
//               exit aborts the release.
//   stamp <V>   prepareCmd. Dates the `## [V]` heading with today's UTC date.
//               The date is the only thing the pipeline writes. The content and
//               the heading stay with the human.
//
// Checked here is the section's structure, never whether its content is
// complete. Picking the entries is the human's job (ADR-0010).
// The logic lives in pure functions, pinned by changelog-release.test.mjs.
// ============================================================================

import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const CHANGELOG = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../blocky/CHANGELOG.md");

const SECTION_HEADING = /^## \[([^\]]+)\](?: - (\d{4}-\d{2}-\d{2}))?$/;

/**
 * Split a changelog into its `## [...]` sections. A `## ` line that is not a
 * version heading (the closing "## 0.3.0 and earlier" pointer) is plain text.
 * A typo in the top heading still fails: the next section becomes the top one
 * and no longer matches the computed version.
 */
export function parseSections(text) {
  const sections = [];
  for (const [index, raw] of text.split("\n").entries()) {
    const line = raw.trimEnd();
    const match = SECTION_HEADING.exec(line);
    if (match) sections.push({ version: match[1], date: match[2] ?? null, line: index + 1, body: [] });
    else if (sections.length > 0) sections[sections.length - 1].body.push(line);
  }
  return sections;
}

/** True when at least one `### ` subsection holds at least one `- ` entry. */
function hasEntries(body) {
  let inSubsection = false;
  for (const line of body) {
    if (/^### \S/.test(line)) inSubsection = true;
    else if (inSubsection && /^- \S/.test(line)) return true;
  }
  return false;
}

/**
 * Every reason the changelog is not ready to release `version`. Empty means
 * ready.
 */
export function verifyChangelog(text, version) {
  const errors = [];
  const sections = parseSections(text);

  for (const s of sections) {
    if (s.version.toLowerCase() === "unreleased") {
      errors.push(
        `line ${s.line}: "## [${s.version}]" found. Nothing renames it at release, so write the entries under "## [${version}]" instead (ADR-0010)`,
      );
    }
  }

  const [top, ...older] = sections;
  if (!top) {
    errors.push(`no version section found. Add "## [${version}]" with this release's entries`);
    return errors;
  }

  if (top.version !== version) {
    errors.push(
      `the topmost section is "## [${top.version}]", but semantic-release computed ${version}. The computed version wins: rename the heading to "## [${version}]" (ADR-0010)`,
    );
  } else {
    if (top.date) {
      errors.push(
        `line ${top.line}: "## [${version}]" is already dated ${top.date}. Remove the date; the release stamps it`,
      );
    }
    if (!hasEntries(top.body)) {
      errors.push(`"## [${version}]" has no entries. It needs at least one "### " subsection with a "- " line`);
    }
  }

  for (const s of older) {
    if (!s.date) {
      errors.push(`line ${s.line}: "## [${s.version}]" is a released section without a date. Add " - YYYY-MM-DD"`);
    }
  }

  return errors;
}

/**
 * Date the `## [version]` heading. Refuses anything verifyChangelog would
 * reject, so a stamp never papers over an unfinished changelog.
 */
export function stampChangelog(text, version, date) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    throw new Error(`invalid date "${date}" (expected YYYY-MM-DD)`);
  }
  const errors = verifyChangelog(text, version);
  if (errors.length > 0) {
    throw new Error(`refusing to stamp:\n  ${errors.join("\n  ")}`);
  }
  const heading = `## [${version}]`;
  const lines = text.split("\n");
  const index = lines.findIndex((line) => line.trimEnd() === heading);
  lines[index] = `${heading} - ${date}`;
  return lines.join("\n");
}

function main([command, version]) {
  if (!["verify", "stamp"].includes(command) || !version) {
    console.error("usage: changelog-release.mjs <verify|stamp> <version>");
    return 2;
  }
  const text = readFileSync(CHANGELOG, "utf8");

  if (command === "verify") {
    const errors = verifyChangelog(text, version);
    if (errors.length > 0) {
      console.error(`✗ blocky/CHANGELOG.md is not finalized for ${version}:`);
      for (const e of errors) console.error(`  - ${e}`);
      console.error("Finalize the section, push it to main, and dispatch the release again.");
      return 1;
    }
    console.log(`✓ blocky/CHANGELOG.md is ready for ${version}`);
    return 0;
  }

  const date = new Date().toISOString().slice(0, 10);
  try {
    writeFileSync(CHANGELOG, stampChangelog(text, version, date));
  } catch (error) {
    console.error(`✗ ${error.message}`);
    return 1;
  }
  console.log(`Stamped blocky/CHANGELOG.md: ## [${version}] - ${date}`);
  return 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = main(process.argv.slice(2));
}
