// ============================================================================
// Tests for the changelog release gate, run by `pnpm check:changelog`.
//
// Each case is a small inline changelog covering one rule the gate enforces.
// Like check:release-notes, this guards release tooling, so it stays out of the
// `pnpm check` aggregate (ADR-0008) and runs in the CI `Release Notes` job.
// ============================================================================

import assert from "node:assert/strict";
import test from "node:test";
import { stampChangelog, verifyChangelog } from "./changelog-release.mjs";

const HEADER = "# Changelog\n\nAll notable changes to this project will be documented in this file.\n";
const REPO = "https://github.com/robocopklaus/hassio-addon-blocky";
const LINKS = `[5.3.0]: ${REPO}/compare/v5.2.1...v5.3.0
[5.2.1]: ${REPO}/compare/v5.2.0...v5.2.1
`;

const READY = `${HEADER}
## [5.4.0]

### Changed

- Blocky upgraded from v0.35.0 to v0.37.0

## [5.3.0] - 2026-10-11

### Added

- Upstream resolution probe

## [5.2.1] - 2026-08-02

### Fixed

- Outgoing IP Version label

${LINKS}`;
const LINK_540 = `[5.4.0]: ${REPO}/compare/v5.3.0...v5.4.0\n`;

test("a finalized, undated top section verifies", () => {
  assert.deepEqual(verifyChangelog(READY, "5.4.0"), []);
});

test("a top section that differs from the computed version fails, in either direction", () => {
  for (const computed of ["6.0.0", "5.3.1"]) {
    const [error, ...rest] = verifyChangelog(READY, computed);
    assert.equal(rest.length, 0);
    assert.match(error, /"## \[5\.4\.0\]"/);
    assert.match(error, new RegExp(computed.replaceAll(".", "\\.")));
  }
});

test("an [Unreleased] section fails, wherever it is", () => {
  const top = READY.replace("## [5.4.0]", "## [Unreleased]\n\n### Added\n\n- x\n\n## [5.4.0]");
  assert.ok(verifyChangelog(top, "5.4.0").some((e) => e.includes("[Unreleased]")));
  const below = READY.replace("## [5.3.0] - 2026-10-11", "## [Unreleased]");
  assert.ok(verifyChangelog(below, "5.4.0").some((e) => e.includes("[Unreleased]")));
});

test("a top section that is already dated fails", () => {
  const dated = READY.replace("## [5.4.0]", "## [5.4.0] - 2026-11-26");
  const errors = verifyChangelog(dated, "5.4.0");
  assert.equal(errors.length, 1);
  assert.match(errors[0], /already dated/);
});

test("a top section without entries fails", () => {
  for (const body of ["", "### Changed\n", "- an entry outside any subsection\n"]) {
    const empty = READY.replace("### Changed\n\n- Blocky upgraded from v0.35.0 to v0.37.0\n", body);
    const errors = verifyChangelog(empty, "5.4.0");
    assert.equal(errors.length, 1, `body ${JSON.stringify(body)}`);
    assert.match(errors[0], /no entries/);
  }
});

test("an undated released section below the top fails (the v5.3.0 case)", () => {
  const undated = READY.replace("## [5.3.0] - 2026-10-11", "## [5.3.0]");
  const errors = verifyChangelog(undated, "5.4.0");
  assert.equal(errors.length, 1);
  assert.match(errors[0], /"## \[5\.3\.0\]" is a released section without a date/);
});

test("a non-version ## line is plain text, but a typo in the top heading still fails", () => {
  const pointer = `${READY}\n## 0.3.0 and earlier\n\nSee git history.\n`;
  assert.deepEqual(verifyChangelog(pointer, "5.4.0"), []);
  const typo = READY.replace("## [5.4.0]", "## 5.4.0");
  assert.ok(verifyChangelog(typo, "5.4.0").some((e) => e.includes('the topmost section is "## [5.3.0]"')));
});

test("a bracketed heading that is not a well-formed version heading fails instead of turning into text", () => {
  // The bypass the #401 review reproduced: the malformed heading's entries
  // counted toward an empty [5.4.0], and its missing date went unnoticed.
  const bypass = READY.replace("### Changed\n\n- Blocky upgraded from v0.35.0 to v0.37.0\n", "").replace(
    "## [5.3.0] - 2026-10-11",
    "## [5.3.0] \u2013 2026-10-11",
  );
  const errors = verifyChangelog(bypass, "5.4.0");
  assert.ok(errors.some((e) => e.includes('"## [5.4.0]" has no entries')));
  assert.ok(errors.some((e) => e.includes("is not a well-formed version heading")));
  for (const heading of ["## [5.3.0] - TBD", "## [5.3.0] - 2026-10-11 (yanked)", "## [5.3.0]: 2026-10-11"]) {
    const errors = verifyChangelog(READY.replace("## [5.3.0] - 2026-10-11", heading), "5.4.0");
    assert.equal(errors.length, 1, heading);
    assert.match(errors[0], /is not a well-formed version heading/);
  }
});

test("an [Unreleased] section above the release reports only itself, not follow-on errors", () => {
  const above = READY.replace("## [5.4.0]", "## [Unreleased]\n\n### Added\n\n- x\n\n## [5.4.0]");
  const errors = verifyChangelog(above, "5.4.0");
  assert.equal(errors.length, 1);
  assert.match(errors[0], /\[Unreleased\]/);
});

test("a changelog without any section fails", () => {
  assert.equal(verifyChangelog(HEADER, "5.4.0").length, 1);
});

test("a compare link that already exists for the release fails", () => {
  const linked = READY.replace(LINKS, LINK_540 + LINKS);
  const errors = verifyChangelog(linked, "5.4.0");
  assert.equal(errors.length, 1);
  assert.match(errors[0], /"\[5\.4\.0\]:" already exists/);
});

test("a dated section without a compare link fails (the v5.3.0 case, again)", () => {
  const unlinked = READY.replace(`[5.3.0]: ${REPO}/compare/v5.2.1...v5.3.0\n`, "");
  const errors = verifyChangelog(unlinked, "5.4.0");
  assert.equal(errors.length, 1);
  assert.match(errors[0], /"## \[5\.3\.0\]" has no compare link/);
});

test("a release without an older section to compare against fails", () => {
  const only = `${HEADER}\n## [1.0.0]\n\n### Added\n\n- First release\n`;
  const errors = verifyChangelog(only, "1.0.0");
  assert.equal(errors.length, 1);
  assert.match(errors[0], /nothing to compare against/);
});

test("stamp dates the top heading, adds its compare link on top of the link block, and touches nothing else", () => {
  const stamped = stampChangelog(READY, "5.4.0", "2026-11-26");
  assert.equal(
    stamped,
    READY.replace("## [5.4.0]\n", "## [5.4.0] - 2026-11-26\n").replace(LINKS, LINK_540 + LINKS),
  );
});

test("stamp compares against the next older section, not a version in between", () => {
  // 3.2.1 and 3.2.2 were tagged without a section, and [4.0.0] compares to
  // v3.2.0. Same here: without a [5.3.0] section, 5.4.0 compares to v5.2.1.
  const start = READY.indexOf("## [5.3.0]");
  const gap = (READY.slice(0, start) + READY.slice(READY.indexOf("## [5.2.1]"))).replace(
    `[5.3.0]: ${REPO}/compare/v5.2.1...v5.3.0\n`,
    "",
  );
  const stamped = stampChangelog(gap, "5.4.0", "2026-11-26");
  assert.ok(stamped.includes(`\n[5.4.0]: ${REPO}/compare/v5.2.1...v5.4.0\n[5.2.1]:`));
});

test("stamp keeps CRLF line endings on the stamped and the added line", () => {
  const crlf = READY.replaceAll("\n", "\r\n");
  const stamped = stampChangelog(crlf, "5.4.0", "2026-11-26");
  assert.equal(
    stamped,
    crlf
      .replace("## [5.4.0]\r\n", "## [5.4.0] - 2026-11-26\r\n")
      .replace(LINKS.replaceAll("\n", "\r\n"), (LINK_540 + LINKS).replaceAll("\n", "\r\n")),
  );
});

test("stamp refuses a changelog that does not verify", () => {
  assert.throws(() => stampChangelog(READY, "6.0.0", "2026-11-26"), /refusing to stamp/);
  assert.throws(() => stampChangelog(READY, "5.4.0", "26.11.2026"), /invalid date/);
});

test("the stamped changelog no longer verifies, so a second stamp cannot run", () => {
  const stamped = stampChangelog(READY, "5.4.0", "2026-11-26");
  assert.throws(() => stampChangelog(stamped, "5.4.0", "2026-11-27"), /already dated/);
});
