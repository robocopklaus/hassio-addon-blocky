#!/usr/bin/env node
// ==============================================================================
// Render-test harness for the Blocky translation pipeline.
//
// Crosses the same seam the add-on does at runtime:
//   options.json -> tempio + blocky.gtpl -> Rendered config -> blocky validate
//
// For each fixture it renders the shipped defaults (read live from config.yaml)
// deep-merged with the fixture's override.json, diffs the result byte-for-byte
// against the committed golden (expected.yml), and runs `blocky validate`.
//
// See docs/adr/0003-render-test-strategy.md for the design and rationale.
//
//   node scripts/render-test/run.mjs            # render + assert (CI does this)
//   node scripts/render-test/run.mjs --update   # regenerate goldens (local only)
//   node scripts/render-test/run.mjs <name>     # limit to one fixture
// ==============================================================================

import { createHash } from "node:crypto";
import {
  chmodSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import YAML from "yaml";
import { dockerRenderHint } from "./docker-render.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "..", "..");
const DOCKERFILE = path.join(ROOT, "blocky", "Dockerfile");
const CONFIG_YAML = path.join(ROOT, "blocky", "config.yaml");
const TEMPLATE = path.join(
  ROOT,
  "blocky",
  "rootfs",
  "usr",
  "share",
  "tempio",
  "blocky.gtpl"
);
const FIXTURES_DIR = path.join(HERE, "fixtures");
const BIN_DIR = path.join(HERE, ".bin");

const args = process.argv.slice(2);
const UPDATE = args.includes("--update");
const onlyFixture = args.find((a) => !a.startsWith("-"));

// ---------------------------------------------------------------------------
// Pinned binaries only run on Linux (tempio publishes no macOS build), and the
// goldens are authoritative only when produced by the binaries we actually ship.
// ---------------------------------------------------------------------------
if (process.platform !== "linux") {
  console.error(
    [
      `This harness runs the shipped Linux ${"tempio"}/${"blocky"} binaries and must run on Linux.`,
      `tempio publishes no macOS build, so render here through a throwaway Linux container:`,
      ``,
      dockerRenderHint({ update: UPDATE }),
      ``,
    ].join("\n")
  );
  process.exit(1);
}

// ---------------------------------------------------------------------------
// Versions: the Dockerfile is the single source of truth (Renovate bumps it).
// ---------------------------------------------------------------------------
function readDockerfilePins() {
  const text = readFileSync(DOCKERFILE, "utf8");
  const pick = (name) => {
    const m = text.match(new RegExp(`^ARG ${name}=(\\S+)`, "m"));
    if (!m) throw new Error(`Could not find ARG ${name} in ${DOCKERFILE}`);
    return m[1];
  };
  return {
    blockyVersion: pick("BLOCKY_VERSION"),
    tempioVersion: pick("TEMPIO_VERSION"),
    tempioSha256: pick("TEMPIO_SHA256_AMD64"),
  };
}

async function download(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`GET ${url} -> ${res.status} ${res.statusText}`);
  return Buffer.from(await res.arrayBuffer());
}

function sha256(buf) {
  return createHash("sha256").update(buf).digest("hex");
}

// Provision tempio + blocky into BIN_DIR, verifying checksums. Cached across
// runs via a version marker so repeat invocations skip the download.
async function provision(pins) {
  const tempioBin = path.join(BIN_DIR, "tempio");
  const blockyBin = path.join(BIN_DIR, "blocky");
  const marker = path.join(BIN_DIR, ".pins.json");
  const want = JSON.stringify(pins);

  if (
    existsSync(tempioBin) &&
    existsSync(blockyBin) &&
    existsSync(marker) &&
    readFileSync(marker, "utf8") === want
  ) {
    return { tempioBin, blockyBin };
  }

  mkdirSync(BIN_DIR, { recursive: true });

  // tempio: single binary, sha256 pinned in the Dockerfile.
  process.stderr.write(`Provisioning tempio ${pins.tempioVersion}...\n`);
  const tempio = await download(
    `https://github.com/home-assistant/tempio/releases/download/${pins.tempioVersion}/tempio_amd64`
  );
  const tempioGot = sha256(tempio);
  if (tempioGot !== pins.tempioSha256) {
    throw new Error(
      `tempio sha256 mismatch: got ${tempioGot}, expected ${pins.tempioSha256}`
    );
  }
  writeFileSync(tempioBin, tempio);
  chmodSync(tempioBin, 0o755);

  // blocky: tarball verified against its published checksums file.
  process.stderr.write(`Provisioning blocky ${pins.blockyVersion}...\n`);
  const tarball = `blocky_${pins.blockyVersion}_Linux_x86_64.tar.gz`;
  const base = `https://github.com/0xERR0R/blocky/releases/download/${pins.blockyVersion}`;
  const archive = await download(`${base}/${tarball}`);
  const checksums = (await download(`${base}/blocky_checksums.txt`)).toString("utf8");
  const expected = checksums
    .split(/\r?\n/)
    .map((l) => l.trim().split(/\s+/))
    .find(([, name]) => name === tarball)?.[0];
  if (!expected) throw new Error(`No checksum for ${tarball} in blocky_checksums.txt`);
  const archiveGot = sha256(archive);
  if (archiveGot !== expected) {
    throw new Error(`blocky sha256 mismatch: got ${archiveGot}, expected ${expected}`);
  }
  const tmpTar = path.join(BIN_DIR, tarball);
  writeFileSync(tmpTar, archive);
  const untar = spawnSync("tar", ["-xzf", tmpTar, "-C", BIN_DIR, "blocky"], {
    encoding: "utf8",
  });
  if (untar.status !== 0) throw new Error(`tar failed: ${untar.stderr || untar.stdout}`);
  rmSync(tmpTar);
  chmodSync(blockyBin, 0o755);

  writeFileSync(marker, want);
  return { tempioBin, blockyBin };
}

// ---------------------------------------------------------------------------
// Fixture input: defaults (from config.yaml) deep-merged with the override.
// Arrays replace wholesale (HA does not element-merge lists); objects recurse.
// ---------------------------------------------------------------------------
function isPlainObject(v) {
  return v !== null && typeof v === "object" && !Array.isArray(v);
}

function deepMerge(base, over) {
  if (!isPlainObject(base) || !isPlainObject(over)) {
    return structuredClone(over);
  }
  const out = structuredClone(base);
  for (const key of Object.keys(over)) {
    out[key] =
      isPlainObject(over[key]) && isPlainObject(base[key])
        ? deepMerge(base[key], over[key])
        : structuredClone(over[key]);
  }
  return out;
}

function loadDefaults() {
  const parsed = YAML.parse(readFileSync(CONFIG_YAML, "utf8"));
  if (!parsed || !isPlainObject(parsed.options)) {
    throw new Error(`No 'options:' block found in ${CONFIG_YAML}`);
  }
  return parsed.options;
}

function render(tempioBin, options) {
  const work = mkdtempSync(path.join(tmpdir(), "render-test-"));
  try {
    const optionsPath = path.join(work, "options.json");
    const outPath = path.join(work, "config.yml");
    writeFileSync(optionsPath, JSON.stringify(options));
    const r = spawnSync(
      tempioBin,
      ["-conf", optionsPath, "-template", TEMPLATE, "-out", outPath],
      { encoding: "utf8" }
    );
    if (r.status !== 0) {
      throw new Error(`tempio failed: ${r.stderr || r.stdout}`);
    }
    return readFileSync(outPath, "utf8");
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}

function validate(blockyBin, rendered) {
  const work = mkdtempSync(path.join(tmpdir(), "render-validate-"));
  try {
    const cfg = path.join(work, "config.yml");
    writeFileSync(cfg, rendered);
    const r = spawnSync(blockyBin, ["validate", "--config", cfg], { encoding: "utf8" });
    return { ok: r.status === 0, output: (r.stdout || "") + (r.stderr || "") };
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}

function unifiedDiff(goldenPath, actual) {
  const work = mkdtempSync(path.join(tmpdir(), "render-diff-"));
  try {
    const actualPath = path.join(work, "actual.yml");
    writeFileSync(actualPath, actual);
    const r = spawnSync("diff", ["-u", goldenPath, actualPath], { encoding: "utf8" });
    return r.stdout || r.stderr || "(no diff output)";
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
const pins = readDockerfilePins();
const { tempioBin, blockyBin } = await provision(pins);
const defaults = loadDefaults();

let names = readdirSync(FIXTURES_DIR, { withFileTypes: true })
  .filter((d) => d.isDirectory())
  .map((d) => d.name)
  .sort();
if (onlyFixture) names = names.filter((n) => n === onlyFixture);
if (names.length === 0) {
  console.error(onlyFixture ? `No fixture named '${onlyFixture}'` : "No fixtures found");
  process.exit(1);
}

let failed = 0;
let updated = 0;

for (const name of names) {
  const dir = path.join(FIXTURES_DIR, name);
  const overridePath = path.join(dir, "override.json");
  const goldenPath = path.join(dir, "expected.yml");
  const expectInvalid = existsSync(path.join(dir, "expect-invalid"));

  const override = existsSync(overridePath)
    ? JSON.parse(readFileSync(overridePath, "utf8"))
    : {};

  let rendered;
  try {
    rendered = render(tempioBin, deepMerge(defaults, override));
  } catch (err) {
    console.error(`✗ ${name}: render failed — ${err.message}`);
    failed++;
    continue;
  }

  // Validate expectation is the teeth of ADR-0002: a degraded config must still
  // be servable (default), and a core fail-fast fixture must be rejected.
  const { ok, output } = validate(blockyBin, rendered);
  if (expectInvalid && ok) {
    console.error(`✗ ${name}: expected blocky validate to FAIL, but it passed`);
    failed++;
    continue;
  }
  if (!expectInvalid && !ok) {
    console.error(`✗ ${name}: rendered config failed blocky validate:\n${output}`);
    failed++;
    continue;
  }

  if (UPDATE) {
    const exists = existsSync(goldenPath);
    const changed = !exists || readFileSync(goldenPath, "utf8") !== rendered;
    writeFileSync(goldenPath, rendered);
    if (changed) {
      updated++;
      console.log(`↻ ${name}: golden ${exists ? "updated" : "created"}`);
    } else {
      console.log(`= ${name}: golden unchanged`);
    }
    continue;
  }

  if (!existsSync(goldenPath)) {
    console.error(`✗ ${name}: no golden (expected.yml). Run with --update to create it.`);
    failed++;
    continue;
  }
  if (readFileSync(goldenPath, "utf8") !== rendered) {
    console.error(`✗ ${name}: rendered output differs from golden:`);
    console.error(unifiedDiff(goldenPath, rendered));
    failed++;
    continue;
  }
  console.log(`✓ ${name}`);
}

if (UPDATE) {
  console.log(`\n${names.length} fixture(s) processed, ${updated} golden(s) written.`);
  if (failed > 0) {
    console.error(`${failed} fixture(s) could not be updated (see errors above).`);
    process.exit(1);
  }
  process.exit(0);
}

if (failed > 0) {
  console.error(`\n${failed} of ${names.length} fixture(s) failed.`);
  process.exit(1);
}
console.log(`\nAll ${names.length} fixture(s) passed.`);
