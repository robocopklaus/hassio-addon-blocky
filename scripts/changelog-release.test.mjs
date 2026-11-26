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

const READY = `${HEADER}
## [5.4.0]

### Changed

- Blocky upgraded from v0.35.0 to v0.37.0

## [5.3.0] - 2026-10-11

### Added

- Upstream resolution probe
`;

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

test("a changelog without any section fails", () => {
  assert.equal(verifyChangelog(HEADER, "5.4.0").length, 1);
});

test("stamp dates only the top heading and leaves everything else byte-identical", () => {
  const stamped = stampChangelog(READY, "5.4.0", "2026-11-26");
  assert.equal(stamped, READY.replace("## [5.4.0]\n", "## [5.4.0] - 2026-11-26\n"));
});

test("stamp refuses a changelog that does not verify", () => {
  assert.throws(() => stampChangelog(READY, "6.0.0", "2026-11-26"), /refusing to stamp/);
  assert.throws(() => stampChangelog(READY, "5.4.0", "26.11.2026"), /invalid date/);
});

test("the stamped changelog no longer verifies, so a second stamp cannot run", () => {
  const stamped = stampChangelog(READY, "5.4.0", "2026-11-26");
  assert.throws(() => stampChangelog(stamped, "5.4.0", "2026-11-27"), /already dated/);
});
