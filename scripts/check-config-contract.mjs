import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const CONFIG_PATH = path.join(ROOT_DIR, "blocky", "config.yaml");
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

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function isSectionRoot(line, sectionName) {
  return new RegExp(`^${escapeRegExp(sectionName)}:\\s*$`).test(line.trim());
}

function extractTopLevelKeys(content, sectionName) {
  const lines = content.split(/\r?\n/);
  const keys = new Set();
  let inSection = false;

  for (const line of lines) {
    if (!inSection) {
      if (isSectionRoot(line, sectionName) && !line.startsWith(" ")) {
        inSection = true;
      }
      continue;
    }

    if (line.trim() === "" || line.trim().startsWith("#")) {
      continue;
    }

    if (!line.startsWith(" ")) {
      break;
    }

    const match = line.match(/^  ([A-Za-z0-9_]+):\s*/);
    if (match) {
      keys.add(match[1]);
    }
  }

  return keys;
}

function stripInlineComment(value) {
  const quote = value.startsWith('"') ? '"' : value.startsWith("'") ? "'" : null;
  if (quote) {
    return value;
  }

  const commentIndex = value.indexOf(" #");
  if (commentIndex >= 0) {
    return value.slice(0, commentIndex).trim();
  }

  return value;
}

function extractSectionScalarValues(content, sectionName) {
  const lines = content.split(/\r?\n/);
  const values = new Map();
  const stack = [];
  let inSection = false;

  for (const line of lines) {
    if (!inSection) {
      if (isSectionRoot(line, sectionName) && !line.startsWith(" ")) {
        inSection = true;
      }
      continue;
    }

    if (line.trim() === "" || line.trim().startsWith("#")) {
      continue;
    }

    if (!line.startsWith(" ")) {
      break;
    }

    const match = line.match(/^(\s*)([A-Za-z0-9_]+):\s*(.*)$/);
    if (!match) {
      continue;
    }

    const indent = match[1].length;
    const key = match[2];
    const rawValue = stripInlineComment(match[3]);
    const relativeIndent = indent - 2;

    if (relativeIndent < 0 || relativeIndent % 2 !== 0) {
      continue;
    }

    const level = relativeIndent / 2;
    stack.length = level;
    stack[level] = key;

    if (rawValue !== "") {
      values.set(stack.join("."), rawValue);
    }
  }

  return values;
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

if (errors.length > 0) {
  for (const error of errors) {
    console.error(`ERROR: ${error}`);
  }
  process.exit(1);
}

console.log("Config contract check passed.");
