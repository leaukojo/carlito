#!/usr/bin/env node
// Finds public (non-underscore) GDScript functions under src/ and kit/ with zero call sites
// anywhere in real code — same file included. Text search, not the class graph: a call,
// `call("name")`/`call(&"name")`, a signal `.connect(name)`, and `has_method("name")` all
// count as callers, since it's a whole-word search over the raw source. tests/ does NOT
// count: a function reachable only from its own test suite is exactly the never-wired case
// this looks for, same as if nothing called it at all.
//     node tools/check_orphans.mjs
// A hit is either wired up, deleted, or added to tools/orphans_allow.txt with a reason.

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { extname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = fileURLToPath(new URL('.', import.meta.url));
const repoRoot = join(here, '..');

const DEFINITION_DIRS = ['src', 'kit'];
// Callers can live anywhere real code does; tests/ is excluded on purpose (a function called
// only from its own test suite is exactly the "never wired" case this looks for).
const CALLER_EXCLUDE_DIRS = new Set(['tests', '.git', '.godot', 'build', 'reports', 'tmp']);
const CALLER_EXTS = new Set(['.gd', '.tscn', '.tres']);

function walk(dir, out) {
  for (const entry of readdirSync(dir)) {
    const path = join(dir, entry);
    const st = statSync(path);
    if (st.isDirectory()) {
      if (CALLER_EXCLUDE_DIRS.has(entry)) continue;
      walk(path, out);
    } else {
      out.push(path);
    }
  }
}

const allFiles = [];
walk(repoRoot, allFiles);

function relPosix(f) {
  return relative(repoRoot, f).replace(/\\/g, '/');
}

const callerFiles = allFiles.filter((f) => CALLER_EXTS.has(extname(f)));
const gdFiles = allFiles.filter(
  (f) => extname(f) === '.gd' && DEFINITION_DIRS.some((d) => relPosix(f).startsWith(d + '/')),
);

const FUNC_RE = /^\s*(?:static\s+)?func\s+([A-Za-z_]\w*)\s*\(/;

const definitions = []; // { name, file, line }
for (const file of gdFiles) {
  const lines = readFileSync(file, 'utf8').split('\n');
  lines.forEach((line, i) => {
    const m = FUNC_RE.exec(line);
    if (!m) return;
    const name = m[1];
    if (name.startsWith('_')) return; // Godot lifecycle overrides and private helpers
    definitions.push({ name, file, line: i + 1 });
  });
}

const allowPath = join(here, 'orphans_allow.txt');
const allow = new Set();
try {
  for (const raw of readFileSync(allowPath, 'utf8').split('\n')) {
    const line = raw.split('#')[0].trim();
    if (line) allow.add(line);
  }
} catch {
  // no allow-list yet
}

const contentCache = new Map();
function contentOf(file) {
  if (!contentCache.has(file)) contentCache.set(file, readFileSync(file, 'utf8'));
  return contentCache.get(file);
}

const orphans = [];
for (const def of definitions) {
  const relFile = relPosix(def.file);
  const key = `${relFile}:${def.name}`;
  if (allow.has(key)) continue;
  const wordRe = new RegExp(`\\b${def.name}\\b`, 'g');
  const hasCaller = callerFiles.some((f) => {
    const count = (contentOf(f).match(wordRe) || []).length;
    // The defining file itself needs a second hit (the `func` line is the first); any other
    // file needs just one.
    return f === def.file ? count > 1 : count > 0;
  });
  if (!hasCaller) orphans.push({ ...def, relFile });
}

if (orphans.length === 0) {
  console.log('check_orphans: no unwired public functions found.');
  process.exit(0);
}

console.log(`check_orphans: ${orphans.length} public function(s) with no caller anywhere outside tests/:\n`);
for (const o of orphans) {
  console.log(`  ${o.relFile}:${o.line}: ${o.name}`);
}
console.log(
  '\nEach hit: wire it up, delete it, or add "<path>:<func>  # reason" to tools/orphans_allow.txt.',
);
process.exit(1);
