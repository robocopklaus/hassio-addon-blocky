// ============================================================================
// Schema <-> translation field parity.
//
// Home Assistant translates add-on options one level deep: each top-level
// section gets a name/description, and each of its direct schema keys gets an
// entry under `configuration.<section>.fields.<field>`. A schema field without
// that entry renders in the UI as a bare key with no explanation; a translated
// field no longer in the schema is dead text.
//
// Both files are static YAML, so this parity is checked exactly — unlike
// schema <-> template parity, which stays top-level only because the template
// aliases sections into `$vars` (ADR-0005). Reuses the dependency-free walkers.
// ============================================================================

import { extractSectionKeyPaths } from "./config-walkers.mjs";

// `<section>.<field>` for every direct child key of a schema section. Keys under
// list items (e.g. upstreams.groups[].resolvers) walk to deeper paths and drop out.
function schemaFields(configYaml) {
  return new Set(
    [...extractSectionKeyPaths(configYaml, "schema")].filter(
      (keyPath) => keyPath.split(".").length === 2
    )
  );
}

// `<section>.<field>` for every `configuration.<section>.fields.<field>` entry.
function translatedFields(translationYaml) {
  const fields = new Set();
  for (const keyPath of extractSectionKeyPaths(translationYaml, "configuration")) {
    const [section, fieldsKey, field, ...rest] = keyPath.split(".");
    if (fieldsKey === "fields" && field !== undefined && rest.length === 0) {
      fields.add(`${section}.${field}`);
    }
  }
  return fields;
}

export function translationFieldGaps(configYaml, translationYaml) {
  const schema = schemaFields(configYaml);
  const translated = translatedFields(translationYaml);
  return {
    untranslated: [...schema].filter((field) => !translated.has(field)).sort(),
    orphaned: [...translated].filter((field) => !schema.has(field)).sort(),
  };
}
