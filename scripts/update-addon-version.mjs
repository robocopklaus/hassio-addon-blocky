import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const version = process.argv[2];

if (!version) {
  throw new Error("Missing version argument");
}

const configPath = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../blocky/config.yaml"
);

const original = readFileSync(configPath, "utf8");
const updated = original.replace(/^(version:\s*).+$/m, `$1${version}`);

if (original === updated) {
  throw new Error("Could not locate version field in blocky/config.yaml");
}

writeFileSync(configPath, updated);
console.log(`Updated ${configPath} -> ${version}`);
