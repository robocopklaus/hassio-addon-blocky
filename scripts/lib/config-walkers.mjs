// ============================================================================
// config.yaml section walkers.
//
// The add-on's config.yaml is maintainer-controlled and written in a known,
// regular style (2-space indent, `key: value`), so it is walked by hand rather
// than with a YAML dependency — keeping the contract check dependency-free
// (ADR-0003). The single indentation walk lives in walkSection(); the three
// views the contract checker takes over it (top-level keys, scalar values,
// key-path presence) are thin filters over it. Behaviour is pinned exactly by
// config-walkers.test.mjs, so walkSection can change without silent drift.
// ============================================================================

export function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function isSectionRoot(line, sectionName) {
  return new RegExp(`^${escapeRegExp(sectionName)}:\\s*$`).test(line.trim());
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

// The one indentation walk. Scoped to the top-level section named `sectionName`
// (its `name:` header at column 0) and stopping at the next column-0 line, it
// yields `[dottedPath, value | null]` for every `key:` line at an even 2-space
// indent — value being the inline-comment-stripped scalar, or null when the key
// carries none (a container or bare-empty key). Blank lines, comments, list
// items, and odd-indent lines are skipped; the three exported views differ only
// in how they filter this stream.
function* walkSection(content, sectionName) {
  const lines = content.split(/\r?\n/);
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
    const relativeIndent = indent - 2;

    if (relativeIndent < 0 || relativeIndent % 2 !== 0) {
      continue;
    }

    const level = relativeIndent / 2;
    stack.length = level;
    stack[level] = match[2];

    const value = stripInlineComment(match[3]);
    yield [stack.join("."), value === "" ? null : value];
  }
}

// Top-level keys of the section: exactly the paths with no dot.
export function extractTopLevelKeys(content, sectionName) {
  const keys = new Set();
  for (const [dottedPath] of walkSection(content, sectionName)) {
    if (!dottedPath.includes(".")) {
      keys.add(dottedPath);
    }
  }
  return keys;
}

// Dotted path -> scalar value, for value-bearing keys only (container and
// bare-empty keys carry null and are dropped).
export function extractSectionScalarValues(content, sectionName) {
  const values = new Map();
  for (const [dottedPath, value] of walkSection(content, sectionName)) {
    if (value !== null) {
      values.set(dottedPath, value);
    }
  }
  return values;
}

// Every key path, value-bearing or not. Used to test key presence (e.g. a
// deprecated key with a bare-empty default, or a container key) without the
// value-only filtering that would otherwise report such keys as missing.
export function extractSectionKeyPaths(content, sectionName) {
  const paths = new Set();
  for (const [dottedPath] of walkSection(content, sectionName)) {
    paths.add(dottedPath);
  }
  return paths;
}
