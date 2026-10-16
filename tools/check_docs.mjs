#!/usr/bin/env node
// Fails on doc references that no longer resolve. Scans every CLAUDE.md, docs/**/*.md and the
// `##` doc comments of project GDScript. Inside backticks (and markdown links):
//   - a repo path that does not exist (doc-relative, then repo-relative, then as a path suffix);
//   - a cited `test_*` that no test defines;
//   - a `docs/plans/` link to a deleted plan (also unbackticked);
//   - `Class.member` on a project class (class_name or preload alias) whose member appears
//     nowhere in code. Engine classes are skipped by construction.
//     node tools/check_docs.mjs
// Paths outside the repo (`../sloppycan/...`) are not checked. A hit is either fixed or added
// to tools/docs_allow.txt (a rejected design named on purpose, a generated file) with a reason;
// an allow entry that no longer matches anything fails too, so the list cannot rot.
// Also fails a CLAUDE.md over its line budget (CLAUDE_MD_BUDGET; nested files default to 40), the
// top-level docs/*.md over their one shared DOCS_LINE_CAP, and a run of whole-line comments in src/
// or kit/ GDScript longer than COMMENT_BLOCK_CAP.

import { execSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { join, posix } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = join(fileURLToPath(new URL('.', import.meta.url)), '..');
// The working tree, not the index: a tracked file deleted but not yet committed is gone.
const files = execSync('git ls-files --cached --others --exclude-standard', { cwd: repoRoot })
  .toString().split('\n').filter((f) => f && existsSync(join(repoRoot, f)));
const fileSet = new Set(files);
const dirSet = new Set();
for (const f of files) for (let d = posix.dirname(f); d !== '.'; d = posix.dirname(d)) dirSet.add(d);
const read = (f) => readFileSync(join(repoRoot, f), 'utf8').replace(/\r\n/g, '\n');

const allow = new Set();
for (const raw of read('tools/docs_allow.txt').split('\n')) {
  const line = raw.split('#')[0].trim();
  if (line) allow.add(line);
}

const SCAN_GD = /^(src|kit|tools|tests|addons\/carlito_kit)\//;
const docs = files.filter((f) => /(^|\/)CLAUDE\.md$/.test(f) && !f.startsWith('addons/gdUnit4/')
  || /^docs\/.*\.md$/.test(f));
const gdFiles = files.filter((f) => f.endsWith('.gd') && SCAN_GD.test(f));
const codeFiles = files.filter((f) => /\.(gd|tscn|tres|cfg|godot)$/.test(f));

// Code text with comments stripped, for the member search.
const codeText = codeFiles.map((f) => read(f).split('\n').map((l) => l.replace(/#.*/, '')).join('\n')).join('\n');
const testNames = new Set();
for (const f of files.filter((p) => p.startsWith('tests/') && p.endsWith('.gd'))) {
  for (const m of read(f).matchAll(/^func\s+(test_\w+)/gm)) testNames.add(m[1]);
}
const projectClasses = new Set();
for (const f of gdFiles) {
  const src = read(f);
  for (const m of src.matchAll(/^class_name\s+(\w+)/gm)) projectClasses.add(m[1]);
  for (const m of src.matchAll(/^const\s+(\w+)\s*:?=\s*preload\(/gm)) projectClasses.add(m[1]);
}

const TOP_DIRS = new Set(files.filter((f) => f.includes('/')).map((f) => f.split('/')[0]));
const PATH_EXT = /\.(gd|tscn|tres|md|mjs|js|json|ps1|cfg|html|scn|glb|png|py|sh|cmd|txt|svg|import)$/;

function pathExists(span, fromDir) {
  const p = span.replace(/^res:\/\//, '').replace(/:\d+(-\d+)?$/, '').replace(/\/$/, '');
  const cands = [posix.normalize(posix.join(fromDir, p)), posix.normalize(p)];
  if (cands.some((c) => fileSet.has(c) || dirSet.has(c))) return true;
  const suffix = '/' + p;
  return files.some((f) => f.endsWith(suffix)) || [...dirSet].some((d) => d.endsWith(suffix));
}

const problems = [];
const usedAllow = new Set();
function report(where, kind, span) {
  span = span.replace(/^res:\/\//, '');
  for (const key of [span, `${where.split(':')[0]}:${span}`]) {
    if (allow.has(key)) return void usedAllow.add(key);
  }
  problems.push(`  ${where}: ${kind}: ${span}`);
}

function checkSpan(span, where, fromDir) {
  span = span.trim();
  if (/^test_\w+$/.test(span)) {
    if (!testNames.has(span) && !fileSet.has(`tests/${span}.gd`)) report(where, 'no such test', span);
    return;
  }
  const cm = /^([A-Z]\w*)\.([A-Za-z_]\w*)(\(\))?$/.exec(span);
  if (cm) {
    if (projectClasses.has(cm[1]) && !new RegExp(`\\b${cm[2]}\\b`).test(codeText)) {
      report(where, 'member not in code', span);
    }
    return;
  }
  if (/[\s<>{}*$|"'`,=()\[\]]/.test(span) || /^(user|https?):/.test(span)) return;
  const bare = span.replace(/^res:\/\//, '').replace(/:\d+(-\d+)?$/, '');
  if (!/^[\w.\-/]+$/.test(bare) || /^(\.\.|\/)/.test(bare)) return;
  // A path is a filename with a known extension, or anything rooted at a top-level repo dir;
  // other slashed spans are node paths or project settings.
  if (!PATH_EXT.test(bare) && !TOP_DIRS.has(bare.split('/')[0])) return;
  if (bare.endsWith('.baked.scn') || bare.startsWith('build/')) return;
  if (/^\.[\w.]+$/.test(bare)) return; // a bare extension: `.tres`
  if (!pathExists(bare, fromDir)) report(where, 'missing path', span);
}

function scanText(text, where, fromDir) {
  for (const m of text.matchAll(/`([^`\n]+)`/g)) checkSpan(m[1], where, fromDir);
  for (const m of text.matchAll(/\]\(([^)#\s]+)(#[^)]*)?\)/g)) {
    if (!/^https?:/.test(m[1]) && !pathExists(m[1], fromDir)) report(where, 'missing link', m[1]);
  }
  for (const m of text.replace(/`[^`\n]+`|\]\([^)]*\)/g, '').matchAll(/docs\/plans\/[\w.-]+\.md/g)) {
    if (!fileSet.has(m[0])) report(where, 'dangling plan', m[0]);
  }
}

for (const f of docs) {
  read(f).split('\n').forEach((line, i) => scanText(line, `${f}:${i + 1}`, posix.dirname(f)));
}
for (const f of gdFiles) {
  read(f).split('\n').forEach((line, i) => {
    const m = /^\s*##(.*)$/.exec(line);
    if (m) scanText(m[1], `${f}:${i + 1}`, posix.dirname(f));
  });
}

for (const key of allow) {
  if (!usedAllow.has(key)) problems.push(`  tools/docs_allow.txt: unused allow entry: ${key}`);
}

// Raw lines per CLAUDE.md. Raising a cap is a decision made in this diff, not a side effect.
const CLAUDE_MD_BUDGET = { 'CLAUDE.md': 110 };
const NESTED_CLAUDE_MD_CAP = 40;
const overBudget = [];
for (const f of docs.filter((d) => /(^|\/)CLAUDE\.md$/.test(d))) {
  const cap = CLAUDE_MD_BUDGET[f] ?? NESTED_CLAUDE_MD_CAP;
  const n = read(f).replace(/\n$/, '').split('\n').length;
  if (n > cap) overBudget.push(`  ${f}: ${n} lines, cap ${cap}`);
}

// Raw lines summed over the top-level docs/*.md (plans/ are temporary). One cap, no per-doc caps.
const DOCS_LINE_CAP = 3285;
const docsLines = docs.filter((d) => /^docs\/[^/]+\.md$/.test(d))
  .reduce((sum, d) => sum + read(d).replace(/\n$/, '').split('\n').length, 0);
if (docsLines > DOCS_LINE_CAP) overBudget.push(`  docs/*.md: ${docsLines} lines in total, cap ${DOCS_LINE_CAP}`);

// Consecutive whole-line comments per block. A derivation belongs in docs/ behind a pointer.
const COMMENT_BLOCK_CAP = 10;
const longComments = [];
for (const f of gdFiles.filter((g) => /^(src|kit)\//.test(g))) {
  let run = 0;
  read(f).split('\n').concat('').forEach((line, i) => {
    if (/^\s*#/.test(line)) return void run++;
    if (run > COMMENT_BLOCK_CAP) longComments.push(`  ${f}:${i - run + 1}: ${run} lines`);
    run = 0;
  });
}

if (problems.length === 0 && overBudget.length === 0 && longComments.length === 0) {
  console.log('check_docs: every reference resolves; every CLAUDE.md, docs/ and comment block is within budget.');
  process.exit(0);
}
if (problems.length > 0) {
  console.log(`check_docs: ${problems.length} dangling reference(s):\n`);
  console.log(problems.join('\n'));
  console.log('\nEach hit: fix the doc, or add "<span>" or "<file>:<span>  # reason" to tools/docs_allow.txt.');
}
if (overBudget.length > 0) {
  console.log(`${problems.length > 0 ? '\n' : ''}check_docs: CLAUDE.md or docs/ over its line budget:\n`);
  console.log(overBudget.join('\n'));
  console.log('\nA line stays only if it binds work in its directory, cannot be read from the code or a');
  console.log("guard's failure message, and still matches the code (root CLAUDE.md § Where things go).");
  console.log('Cut it, or move a derivation to docs/. In docs/, a figure has one home (elsewhere a');
  console.log('pointer) and only its latest value. Raising a cap is a decision: edit CLAUDE_MD_BUDGET or');
  console.log('DOCS_LINE_CAP in tools/check_docs.mjs.');
}
if (longComments.length > 0) {
  console.log(`\ncheck_docs: comment block over ${COMMENT_BLOCK_CAP} lines:\n`);
  console.log(longComments.join('\n'));
  console.log('\nKeep the constraint at its site in one or two sentences; move the derivation to docs/ and');
  console.log('leave a one-line pointer (root CLAUDE.md § Where things go).');
}
process.exit(1);
