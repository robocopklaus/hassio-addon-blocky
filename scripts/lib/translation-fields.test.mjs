// ============================================================================
// Tests for the schema <-> translation field parity (translation-fields.mjs).
//
// Zero dependencies: node's built-in test runner. Run by check-config-contract.mjs
// (and thus by check:contracts, pnpm check, and the CI contracts job).
// ============================================================================

import assert from "node:assert/strict";
import test from "node:test";
import { translationFieldGaps } from "./translation-fields.mjs";

const CONFIG = `name: Example
schema:
  query_log:
    type: list(csv|sqlite)?
    fields:
      - list(clientIP|question)?
    ignore_clients:
      - str?
  upstreams:
    groups:
      - name: str
        resolvers:
          - str
  custom_config: bool?
`;

const TRANSLATIONS = (queryLogFields) => `configuration:
  query_log:
    name: Query Logging
    description: >-
      Record DNS queries.
    fields:
${queryLogFields}
  upstreams:
    name: Upstreams
    fields:
      groups:
        name: Groups
  custom_config:
    name: Custom Config
`;

test("every schema field translated: no gaps", () => {
  const translations = TRANSLATIONS(
    [
      "      type:",
      "        name: Log Type",
      "      fields:",
      "        name: Log Fields",
      "      ignore_clients:",
      "        name: Ignored Clients",
    ].join("\n")
  );
  assert.deepEqual(translationFieldGaps(CONFIG, translations), {
    untranslated: [],
    orphaned: [],
  });
});

test("a schema field with no translation entry is untranslated", () => {
  const translations = TRANSLATIONS(
    ["      type:", "        name: Log Type", "      fields:", "        name: Log Fields"].join("\n")
  );
  assert.deepEqual(translationFieldGaps(CONFIG, translations), {
    untranslated: ["query_log.ignore_clients"],
    orphaned: [],
  });
});

test("a translated field no longer in the schema is orphaned", () => {
  const translations = TRANSLATIONS(
    [
      "      type:",
      "        name: Log Type",
      "      fields:",
      "        name: Log Fields",
      "      ignore_clients:",
      "        name: Ignored Clients",
      "      retired_option:",
      "        name: Gone",
    ].join("\n")
  );
  assert.deepEqual(translationFieldGaps(CONFIG, translations), {
    untranslated: [],
    orphaned: ["query_log.retired_option"],
  });
});

test("keys inside list items are not fields (only <section>.<field> counts)", () => {
  // upstreams.groups[].resolvers sits below a list item; HA translates one level
  // of fields per section, so it must neither be required nor reported.
  const translations = TRANSLATIONS(
    [
      "      type:",
      "        name: Log Type",
      "      fields:",
      "        name: Log Fields",
      "      ignore_clients:",
      "        name: Ignored Clients",
    ].join("\n")
  );
  const { untranslated } = translationFieldGaps(CONFIG, translations);
  assert.ok(!untranslated.some((p) => p.includes("resolvers")));
});
