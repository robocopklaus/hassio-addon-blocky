// ============================================================================
// Characterization tests for the config.yaml walkers.
//
// These pin the EXACT current behaviour of the three walkers — quirks included —
// so the shared walkSection they sit on can be refactored with provable
// equivalence (ADR-0003's fear is a "concrete parser bug"; this is the net that
// catches one). Anything asserted here that turns out to be a genuine misread is
// a real bug to fix in its OWN change, never silently inside a refactor.
//
// Zero dependencies: node's built-in test runner. Run by check-config-contract.mjs
// (and thus by check:contracts, pnpm check, and the CI contracts job).
// ============================================================================

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  extractSectionKeyPaths,
  extractSectionScalarValues,
  extractTopLevelKeys,
} from "./config-walkers.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");

// A single document exercising every branch of the walk:
//   - a scalar, a quoted scalar (quotes preserved), an inline-comment scalar
//   - onlycomment: value is a bare "# …" — a QUIRK: stripInlineComment only
//     strips on " #" (space-hash), so a comment-only tail is kept as a value
//   - a container key + nested scalars + an empty child + depth-2 nesting
//   - badindent: a 3-space "odd:" child — relativeIndent 1 is skipped everywhere
//   - emptyval: a bare container-style key with no value
//   - a following section (schema) and a col-0 key that ends the walk
const DOC = `pre_section: ignored
options:
  simple: value1
  quoted: "quoted value"
  commented: value2 # trailing comment
  onlycomment: # just a comment
  container:
    nested_scalar: deep
    empty_child:
    deeper:
      leaf: bottom
  badindent:
   odd: skipme
  emptyval:
schema:
  simple: str
next_top: ends_section
`;

const sortedSet = (s) => [...s].sort();
const sortedEntries = (m) => [...m.entries()].sort(([a], [b]) => a.localeCompare(b));

test("extractTopLevelKeys: only depth-0 keys of the named section", () => {
  assert.deepEqual(sortedSet(extractTopLevelKeys(DOC, "options")), [
    "badindent",
    "commented",
    "container",
    "emptyval",
    "onlycomment",
    "quoted",
    "simple",
  ]);
  assert.deepEqual(sortedSet(extractTopLevelKeys(DOC, "schema")), ["simple"]);
});

test("extractSectionScalarValues: dotted path -> value, only for value-bearing keys", () => {
  assert.deepEqual(sortedEntries(extractSectionScalarValues(DOC, "options")), [
    ["commented", "value2"], // inline comment stripped
    ["container.deeper.leaf", "bottom"], // depth-2 nesting
    ["container.nested_scalar", "deep"],
    ["onlycomment", "# just a comment"], // QUIRK: comment-only tail kept as value
    ["quoted", '"quoted value"'], // surrounding quotes preserved verbatim
    ["simple", "value1"],
  ]);
  assert.deepEqual(sortedEntries(extractSectionScalarValues(DOC, "schema")), [["simple", "str"]]);
});

test("extractSectionKeyPaths: every key path, value-bearing or not", () => {
  assert.deepEqual(sortedSet(extractSectionKeyPaths(DOC, "options")), [
    "badindent",
    "commented",
    "container",
    "container.deeper",
    "container.deeper.leaf",
    "container.empty_child", // present despite no value (unlike scalars)
    "container.nested_scalar",
    "emptyval",
    "onlycomment",
    "quoted",
    "simple",
  ]);
});

test("odd indentation (3-space 'odd:') is skipped by all three walkers", () => {
  assert.ok(!extractTopLevelKeys(DOC, "options").has("odd"));
  assert.ok(!extractSectionScalarValues(DOC, "options").has("badindent.odd"));
  assert.ok(!extractSectionKeyPaths(DOC, "options").has("badindent.odd"));
});

test("an absent section yields empty results for all three walkers", () => {
  assert.equal(extractTopLevelKeys(DOC, "nope").size, 0);
  assert.equal(extractSectionScalarValues(DOC, "nope").size, 0);
  assert.equal(extractSectionKeyPaths(DOC, "nope").size, 0);
});

test("a section root only counts at column 0 (indented 'options:' is ignored)", () => {
  const nested = `outer:\n  options:\n    trap: value\nreal_top: x\n`;
  assert.equal(extractTopLevelKeys(nested, "options").size, 0);
  assert.equal(extractSectionKeyPaths(nested, "options").size, 0);
});

// Invariants over the real config.yaml. These hold by construction regardless of
// how config.yaml evolves, so they are regression coverage that never needs
// editing when an option is added — the three views must stay mutually coherent.
test("real config.yaml: the three views stay mutually coherent", () => {
  const cfg = readFileSync(path.join(ROOT, "blocky", "config.yaml"), "utf8");
  const topLevel = extractTopLevelKeys(cfg, "options");
  const keyPaths = extractSectionKeyPaths(cfg, "options");
  const scalars = extractSectionScalarValues(cfg, "options");

  // Top-level keys are exactly the dotless key paths.
  assert.deepEqual(
    sortedSet(topLevel),
    sortedSet(keyPaths).filter((p) => !p.includes("."))
  );
  // Every scalar-valued path is also a known key path.
  for (const p of scalars.keys()) {
    assert.ok(keyPaths.has(p), `scalar path ${p} missing from key paths`);
  }
  // Sanity: the section is non-empty (guards against a silent "found nothing").
  assert.ok(topLevel.size > 0 && keyPaths.size >= topLevel.size);
});
