import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  escapeRegExp,
  extractSectionKeyPaths,
  extractSectionScalarValues,
  extractTopLevelKeys,
} from "./lib/config-walkers.mjs";

const ROOT_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

// The three config.yaml walkers are the load-bearing primitive of this checker,
// so guard them before trusting anything they report. Running the pinning tests
// here — rather than as a separate package/CI step — single-sources "contracts
// includes the walker guard" across every caller of this script (the check:contracts
// package script, the pnpm check aggregate, and the CI contracts job all invoke
// `node scripts/check-config-contract.mjs` directly). Zero deps: node's built-in
// test runner (ADR-0003). A failing walker test fails the contract check.
const WALKER_TEST = path.join(path.dirname(fileURLToPath(import.meta.url)), "lib", "config-walkers.test.mjs");
const walkerTests = spawnSync(process.execPath, ["--test", WALKER_TEST], {
  cwd: ROOT_DIR,
  stdio: "inherit",
});
if (walkerTests.status !== 0) {
  process.exit(walkerTests.status ?? 1);
}

const CONFIG_PATH = path.join(ROOT_DIR, "blocky", "config.yaml");
const DEPRECATIONS_PATH = path.join(ROOT_DIR, "scripts", "deprecations.json");
const FIXTURES_DIR = path.join(ROOT_DIR, "scripts", "render-test", "fixtures");
const TEMPLATE_PATH = path.join(
  ROOT_DIR,
  "blocky",
  "rootfs",
  "usr",
  "share",
  "tempio",
  "blocky.gtpl"
);
const TRANSLATION_PATH = path.join(ROOT_DIR, "blocky", "translations", "en.yaml");

const configYaml = readFileSync(CONFIG_PATH, "utf8");
const template = readFileSync(TEMPLATE_PATH, "utf8");
const translationYaml = readFileSync(TRANSLATION_PATH, "utf8");

const errors = [];
const templateExemptions = new Set(["custom_config"]);

// True when the dotted path resolves to a present key in a parsed override.json.
// Proves a deprecation fixture actually exercises the key (not just that the
// fixture directory exists). Stops at the leaf's parent so a leaf with any value
// — including false/null — still counts as present.
function overrideSetsPath(override, keyPath) {
  const segments = keyPath.split(".");
  let node = override;
  for (const segment of segments) {
    if (!isPlainObject(node) || !(segment in node)) {
      return false;
    }
    node = node[segment];
  }
  return true;
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function parseDirectiveBodies(templateContent) {
  const bodies = [];
  const regex = /{{-?([\s\S]*?)-?}}/g;
  let match;

  while ((match = regex.exec(templateContent)) !== null) {
    bodies.push(match[1]);
  }

  return bodies.join("\n");
}

function normalizeScalar(value) {
  const trimmed = value.trim();

  if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
    return trimmed.slice(1, -1);
  }

  if (trimmed.startsWith("'") && trimmed.endsWith("'")) {
    return trimmed.slice(1, -1);
  }

  return trimmed;
}

function diffSet(left, right) {
  const missing = [];
  for (const item of left) {
    if (!right.has(item)) {
      missing.push(item);
    }
  }
  return missing.sort();
}

const optionKeys = extractTopLevelKeys(configYaml, "options");
const schemaKeys = extractTopLevelKeys(configYaml, "schema");
const translationKeys = extractTopLevelKeys(translationYaml, "configuration");

const missingInSchema = diffSet(optionKeys, schemaKeys);
const extraInSchema = diffSet(schemaKeys, optionKeys);

if (missingInSchema.length > 0) {
  errors.push(
    `Top-level keys in options but missing in schema: ${missingInSchema.join(", ")}`
  );
}

if (extraInSchema.length > 0) {
  errors.push(`Top-level keys in schema but missing in options: ${extraInSchema.join(", ")}`);
}

const missingInTranslation = diffSet(optionKeys, translationKeys);
const extraInTranslation = diffSet(translationKeys, optionKeys);

if (missingInTranslation.length > 0) {
  errors.push(
    `Top-level keys in options but missing in translations/en.yaml: ${missingInTranslation.join(
      ", "
    )}`
  );
}

if (extraInTranslation.length > 0) {
  errors.push(
    `Top-level keys in translations/en.yaml but missing in options: ${extraInTranslation.join(", ")}`
  );
}

const directives = parseDirectiveBodies(template);

for (const key of optionKeys) {
  if (templateExemptions.has(key)) {
    continue;
  }

  const pattern = new RegExp(`\\.${escapeRegExp(key)}(?:\\b|\\.)`);
  if (!pattern.test(directives)) {
    errors.push(`Template does not reference top-level option key: ${key}`);
  }
}

const referencedTemplateRoots = new Set();
const rootPathRegex = /(?:^|[^A-Za-z0-9_$])\.(\w+)\./g;
let rootMatch;

while ((rootMatch = rootPathRegex.exec(directives)) !== null) {
  referencedTemplateRoots.add(rootMatch[1]);
}

const unknownTemplateRoots = [...referencedTemplateRoots]
  .filter((root) => !optionKeys.has(root))
  .sort();

if (unknownTemplateRoots.length > 0) {
  errors.push(
    `Template references unknown top-level roots (not in options): ${unknownTemplateRoots.join(", ")}`
  );
}

const optionScalarValues = extractSectionScalarValues(configYaml, "options");
const schemaScalarValues = extractSectionScalarValues(configYaml, "schema");

for (const [pathKey, schemaType] of schemaScalarValues) {
  const enumMatch = schemaType.match(/^list\((.*)\)\??$/);
  if (!enumMatch) {
    continue;
  }

  if (!optionScalarValues.has(pathKey)) {
    continue;
  }

  const allowedValues = enumMatch[1].split("|").map((value) => normalizeScalar(value));
  const optionDefault = normalizeScalar(optionScalarValues.get(pathKey));

  if (!allowedValues.includes(optionDefault)) {
    errors.push(
      `Default value '${optionDefault}' for '${pathKey}' is not part of schema enum [${allowedValues.join(
        ", "
      )}]`
    );
  }
}

// Deprecation retention (see ADR-0005): Home Assistant silently drops persisted
// values for keys no longer in the schema, so a deprecated option must stay in
// both the options and schema blocks — and keep a live fixture proving the
// template still translates it — until we deliberately break it for upgraders.
// The registry lives outside the schema on purpose: a marker on the schema line
// would vanish together with the line it is meant to protect.
//
// Presence is tested against key *paths* (not scalar values), so a deprecated key
// with a bare-empty default or a container key still counts as present. The check
// does not assert *types*, only that the declared path still exists.
const optionKeyPaths = extractSectionKeyPaths(configYaml, "options");
const schemaKeyPaths = extractSectionKeyPaths(configYaml, "schema");

if (existsSync(DEPRECATIONS_PATH)) {
  let deprecations;
  try {
    deprecations = JSON.parse(readFileSync(DEPRECATIONS_PATH, "utf8"));
  } catch (err) {
    errors.push(`Could not parse ${path.relative(ROOT_DIR, DEPRECATIONS_PATH)}: ${err.message}`);
    deprecations = [];
  }

  if (!Array.isArray(deprecations)) {
    errors.push("deprecations.json must be a JSON array of deprecation entries");
    deprecations = [];
  }

  const seenPaths = new Set();

  for (const entry of deprecations) {
    const { path: keyPath, replacedBy, fixture } = entry ?? {};

    if (typeof keyPath !== "string" || keyPath === "") {
      errors.push(`Deprecation entry is missing a 'path': ${JSON.stringify(entry)}`);
      continue;
    }

    if (seenPaths.has(keyPath)) {
      errors.push(`Duplicate deprecation entry for path '${keyPath}' in deprecations.json`);
      continue;
    }
    seenPaths.add(keyPath);

    if (!optionKeyPaths.has(keyPath)) {
      errors.push(
        `Deprecated key '${keyPath}' is no longer a default in the options block of config.yaml — ` +
          `removing it silently deletes this setting for existing users (see ADR-0005)`
      );
    }

    if (!schemaKeyPaths.has(keyPath)) {
      errors.push(
        `Deprecated key '${keyPath}' is no longer in the schema block of config.yaml — ` +
          `Home Assistant will silently drop persisted values for it on upgrade (see ADR-0005)`
      );
    }

    // replacedBy is optional (a removed-with-no-replacement deprecation leaves it
    // empty); when set, the migration target must still exist in the schema.
    if (typeof replacedBy === "string" && replacedBy !== "" && !schemaKeyPaths.has(replacedBy)) {
      errors.push(
        `Deprecation '${keyPath}' names replacedBy '${replacedBy}', which is not in the schema block of config.yaml`
      );
    }

    if (typeof fixture !== "string" || fixture === "") {
      errors.push(`Deprecation '${keyPath}' must name a 'fixture' proving its translation`);
      continue;
    }

    const overridePath = path.join(FIXTURES_DIR, fixture, "override.json");
    if (!existsSync(path.join(FIXTURES_DIR, fixture))) {
      errors.push(
        `Deprecation '${keyPath}' references render-test fixture '${fixture}', which does not exist`
      );
    } else if (!existsSync(overridePath)) {
      errors.push(
        `Deprecation '${keyPath}' fixture '${fixture}' has no override.json to exercise the key`
      );
    } else {
      let override;
      try {
        override = JSON.parse(readFileSync(overridePath, "utf8"));
      } catch (err) {
        errors.push(`Could not parse ${path.relative(ROOT_DIR, overridePath)}: ${err.message}`);
      }
      if (override !== undefined && !overrideSetsPath(override, keyPath)) {
        errors.push(
          `Deprecation '${keyPath}' fixture '${fixture}' does not set '${keyPath}' in override.json, ` +
            `so it never exercises the deprecated translation (see ADR-0005)`
        );
      }
    }
  }
}

if (errors.length > 0) {
  for (const error of errors) {
    console.error(`ERROR: ${error}`);
  }
  process.exit(1);
}

console.log("Config contract check passed.");
