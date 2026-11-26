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
//   stamp <V>   prepareCmd. Dates the `## [V]` heading with today's UTC date
//               and adds `[V]: <repo>/compare/v<prev>...v<V>` on top of the
//               link block, <prev> being the next older section. Date and
//               compare link are the only things the pipeline writes. The
//               content and the heading stay with the human.
//
// Checked here is the section's structure, never whether its content is
// complete. Picking the entries is the human's job (ADR-0010).
// The logic lives in pure functions, pinned by changelog-release.test.mjs.
// ============================================================================

import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const CHANGELOG_NAME = "blocky/CHANGELOG.md";
const CHANGELOG = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", CHANGELOG_NAME);
// Compare links point here. A repo rename or transfer needs this line changed;
// the gate does not check the URL of existing links.
const REPO_URL = "https://github.com/robocopklaus/hassio-addon-blocky";

const DATE = String.raw`\d{4}-\d{2}-\d{2}`;
const SECTION_HEADING = new RegExp(String.raw`^## \[([^\]]+)\](?: - (${DATE}))?$`);
const LINK_DEFINITION = /^ {0,3}\[([^\]]+)\]: \S/; // CommonMark allows up to 3 spaces of indent

/**
 * Split a changelog into its `## [...]` sections. A `## ` line without a
 * bracket (the closing "## 0.3.0 and earlier" pointer) is plain text. A
 * bracketed one that is not exactly `## [X]` or `## [X] - YYYY-MM-DD` is
 * reported as malformed: read as text, its entries would count toward the
 * section above it and its missing date would go unnoticed.
 */
export function parseSections(text) {
  const sections = [];
  const malformed = [];
  let current = null; // section that collects body lines; null after a malformed heading
  for (const [index, raw] of text.split("\n").entries()) {
    const line = raw.trimEnd();
    const match = SECTION_HEADING.exec(line);
    if (match) {
      current = { version: match[1], date: match[2] ?? null, line: index + 1, body: [] };
      sections.push(current);
    } else if (line.startsWith("## [")) {
      malformed.push({ line: index + 1, text: line });
      current = null;
    } else if (current) {
      current.body.push(line);
    }
  }
  return { sections, malformed };
}

/**
 * The link block: the run of `[X]: <url>` definitions that ends the file, in
 * file order. A reference link inside a section is not part of it.
 */
export function parseLinks(text) {
  const lines = text.split("\n").map((l) => l.trimEnd());
  let end = lines.length;
  while (end > 0 && lines[end - 1] === "") end--;
  let start = end;
  while (start > 0 && LINK_DEFINITION.test(lines[start - 1])) start--;
  return lines.slice(start, end).map((l, i) => ({ version: LINK_DEFINITION.exec(l)[1], line: start + i + 1 }));
}

const isUnreleased = (section) => section.version.toLowerCase() === "unreleased";

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
  const { sections, malformed } = parseSections(text);
  const links = parseLinks(text);
  const linkFor = (v) => links.find((l) => l.version === v);

  for (const m of malformed) {
    errors.push(`line ${m.line}: "${m.text}" is not a well-formed version heading. Use "## [X.Y.Z]" or "## [X.Y.Z] - YYYY-MM-DD"`);
  }

  for (const s of sections.filter(isUnreleased)) {
    errors.push(
      `line ${s.line}: "## [${s.version}]" found. Nothing renames it at release, so write the entries under "## [${version}]" instead (ADR-0010)`,
    );
  }

  // [Unreleased] is already reported above; leave it out of the ordering so
  // it does not also trigger "wrong version" or "undated" errors.
  const [top, ...older] = sections.filter((s) => !isUnreleased(s));
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
    if (older.length === 0) {
      errors.push(`"## [${version}]" has nothing to compare against. The release links it to the next older section`);
    }
  }

  for (const l of links.filter((l) => isUnreleased(l))) {
    errors.push(`line ${l.line}: "[${l.version}]:" found. Remove it; the release adds "[${version}]:" instead`);
  }

  const existing = linkFor(version);
  if (existing) {
    errors.push(`line ${existing.line}: "[${version}]:" already exists. Remove it; the release adds the compare link`);
  }

  for (const [i, s] of older.entries()) {
    if (!s.date) {
      errors.push(`line ${s.line}: "## [${s.version}]" is a released section without a date. Add " - YYYY-MM-DD"`);
    }
    if (!linkFor(s.version)) {
      const previous = older[i + 1]?.version;
      const url = previous
        ? `${REPO_URL}/compare/v${previous}...v${s.version}`
        : `${REPO_URL}/releases/tag/v${s.version}`; // the first release, like [1.0.0]
      errors.push(`line ${s.line}: "## [${s.version}]" has no compare link. Add "[${s.version}]: ${url}" to the link block`);
    }
  }

  return errors;
}

/**
 * Date the `## [version]` heading and add its compare link on top of the link
 * block. Refuses anything verifyChangelog would reject, so a stamp never
 * papers over an unfinished changelog.
 */
export function stampChangelog(text, version, date) {
  if (!new RegExp(`^${DATE}$`).test(date)) {
    throw new Error(`invalid date "${date}" (expected YYYY-MM-DD)`);
  }
  const errors = verifyChangelog(text, version);
  if (errors.length > 0) {
    throw new Error(`refusing to stamp:\n  ${errors.join("\n  ")}`);
  }
  // verify passed: no [Unreleased], `version` is the top section, undated, and
  // the section below it is the one to compare against.
  const [{ line }, { version: previous }] = parseSections(text).sections;
  // verify also passed every older section's link, so the block exists. It
  // ends the file, so it sits below the heading.
  const [firstLink] = parseLinks(text);
  if (!firstLink) throw new Error("refusing to stamp: no link reference block to add the compare link to");

  const lines = text.split("\n");
  const eolOf = (n) => (lines[n - 1].endsWith("\r") ? "\r" : "");
  const compare = `[${version}]: ${REPO_URL}/compare/v${previous}...v${version}${eolOf(firstLink.line)}`;
  lines[line - 1] = `## [${version}] - ${date}${eolOf(line)}`;
  lines.splice(firstLink.line - 1, 0, compare);
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
      console.error(`✗ ${CHANGELOG_NAME} is not finalized for ${version}:`);
      for (const e of errors) console.error(`  - ${e}`);
      console.error("Finalize the section, push it to main, and dispatch the release again.");
      return 1;
    }
    console.log(`✓ ${CHANGELOG_NAME} is ready for ${version}`);
    return 0;
  }

  const date = new Date().toISOString().slice(0, 10);
  try {
    writeFileSync(CHANGELOG, stampChangelog(text, version, date));
  } catch (error) {
    console.error(`✗ ${error.message}`);
    return 1;
  }
  console.log(`Stamped ${CHANGELOG_NAME}: ## [${version}] - ${date}, with its compare link`);
  return 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = main(process.argv.slice(2));
}
