#!/usr/bin/env node
// Fails on doc references that no longer resolve. Scans every CLAUDE.md, docs/**/*.md and the
// `##` doc comments of project GDScript. Inside backticks (and markdown links):
//   - a repo path that does not exist (doc-relative, then repo-relative, then as a path suffix);
//   - a cited `test_*` that no test defines;
//   - a `docs/plans/` link to a deleted plan (also unbackticked);
//   - `Class.member` on a project class (class_name or preload alias) whose member appears
//     nowhere in code. Engine classes are skipped by construction.
// Also, anywhere in those docs and in .gd / .tres / .tscn / .yml comments: a `§ Name` that names no
// heading or run-in head of its doc (`checkAnchors`).
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

// `§ Name` anchors. A doc's anchors are its headings and its bold or italic run-in heads; a
// reference resolves when its text starts with one (so "§ Balance: the pass" finds "Balance").
// The target is the doc path just before the §, a § chained after another (", § X", " and § X"),
// or else the file itself; a bare § in code has no file to mean, so it is skipped.
const anchorCache = new Map();
function anchorsOf(doc) {
  if (!anchorCache.has(doc)) {
    const set = [];
    for (const line of read(doc).split('\n')) {
      const h = /^#+\s+(.*)$/.exec(line);
      if (h) set.push(h[1]);
      for (const m of line.matchAll(/\*\*([^*]+)\*\*/g)) set.push(m[1]);
      const it = /^\s*(?:- )?\*([^*\s][^*]*)\*/.exec(line);
      if (it) set.push(it[1]);
    }
    anchorCache.set(doc, set.map((a) => a.replace(/`/g, '').replace(/[.:]\s*$/, '').trim().toLowerCase())
      .filter(Boolean));
  }
  return anchorCache.get(doc);
}
// Characters of `rest` an anchor covers, or 0. A reference may shorten a heading to its leading
// words ("§ Truck sizing" for "Truck sizing (derivations)") if it stops at punctuation or "and" there.
function leadMatch(anchor, rest) {
  if (rest.startsWith(anchor) && !/[a-z0-9]/.test(rest[anchor.length] ?? '')) return anchor.length;
  const words = anchor.split(/\s+/);
  for (let k = words.length - 1; k >= 1; k--) {
    const lead = words.slice(0, k).join(' ').replace(/[,:;.]$/, '');
    if (rest.startsWith(lead) && /^($|[^a-z0-9\s]|\s+(and|or)\s)/.test(rest.slice(lead.length))) return lead.length;
  }
  return 0;
}
function resolveDoc(p, fromDir) {
  for (const c of [posix.normalize(posix.join(fromDir, p)), posix.normalize(p)]) if (fileSet.has(c)) return c;
  const hits = files.filter((f) => f.endsWith('/' + p));
  return hits.length === 1 ? hits[0] : null;
}
function checkAnchors(text, file, isDoc, lineAt) {
  // Line breaks and comment markers blank out to spaces of the same length, so offsets stay lines.
  const flat = text.replace(/\n[ \t]*(?:#+|;+)?/g, (w) => ' '.repeat(w.length));
  let chainDoc = null;
  let chainEnd = -1;
  for (const m of flat.matchAll(/`?([\w./-]+\.md)`?|§ /g)) {
    if (m[1]) {
      // "root `CLAUDE.md`" names the repo root's, not the nearest one.
      const root = /root\s+`?$/.test(flat.slice(Math.max(0, m.index - 6), m.index));
      chainDoc = /^\.\./.test(m[1]) ? undefined : resolveDoc(m[1], root ? '.' : posix.dirname(file));
      chainEnd = m.index + m[0].length;
      continue;
    }
    const glue = flat.slice(chainEnd, m.index);
    const doc = chainEnd >= 0 && /^[\s`,;(]*(?:and|or)?[\s`(]*$/.test(glue) ? chainDoc : (isDoc ? file : undefined);
    if (doc === undefined || doc === null) continue; // outside the repo, or no file to mean
    // The reference's text, backticks dropped and runs of space collapsed, each char mapped to flat.
    let rest = '';
    const at = [];
    for (let i = m.index + 2; i < flat.length && rest.length < 200; i++) {
      const c = flat[i];
      if (c === '`' || (/\s/.test(c) && rest.endsWith(' '))) continue;
      rest += /\s/.test(c) ? ' ' : c.toLowerCase();
      at.push(i);
    }
    const hit = Math.max(0, ...anchorsOf(doc).map((a) => leadMatch(a, rest)));
    if (!hit) {
      const said = flat.slice(m.index + 2, m.index + 202).replace(/`/g, '').replace(/\s+/g, ' ');
      const words = said.split(/[,;:()]|\s(?:and|or)\s|\.\s/)[0].trim();
      report(`${file}:${lineAt(m.index)}`, 'missing anchor', `${doc} § ${words}`);
      chainEnd = -1;
    } else {
      chainDoc = doc;
      chainEnd = at[hit - 1] + 1;
    }
  }
}
function lineIndex(text) {
  const starts = [0];
  for (let i = 0; i < text.length; i++) if (text[i] === '\n') starts.push(i + 1);
  return (pos) => { let lo = 0; while (lo + 1 < starts.length && starts[lo + 1] <= pos) lo++; return lo + 1; };
}
for (const f of docs) {
  const t = read(f);
  checkAnchors(t, f, true, lineIndex(t));
}
for (const f of files.filter((p) => /\.(gd|tres|tscn|yml)$/.test(p) && !p.startsWith('addons/gdUnit4/'))) {
  // Comment runs only, kept on their own lines so a wrapped reference still reads whole.
  const t = read(f).split('\n').map((l) => (/^\s*(#|;)/.test(l) ? l : '')).join('\n');
  if (t.includes('§')) checkAnchors(t, f, false, lineIndex(t));
}

for (const key of allow) {
  if (!usedAllow.has(key)) problems.push(`  tools/docs_allow.txt: unused allow entry: ${key}`);
}

// Raw lines per CLAUDE.md. Raising a cap is a decision made in this diff, not a side effect.
const CLAUDE_MD_BUDGET = { 'CLAUDE.md': 106 };
const NESTED_CLAUDE_MD_CAP = 40;
const overBudget = [];
const lineCount = (f) => read(f).replace(/\n$/, '').split('\n').length;
let rootClaudeLines = 0;
for (const f of docs.filter((d) => /(^|\/)CLAUDE\.md$/.test(d))) {
  const cap = CLAUDE_MD_BUDGET[f] ?? NESTED_CLAUDE_MD_CAP;
  const n = lineCount(f);
  if (f === 'CLAUDE.md') rootClaudeLines = n;
  if (n > cap) overBudget.push(`  ${f}: ${n} lines, cap ${cap}`);
}

// Raw lines summed over the top-level docs/*.md (plans/ are temporary; sources.md is reference
// data, read on demand; machine_setup.md is read once per machine). One cap, no per-doc caps.
const DOCS_LINE_CAP = 3605;
const UNCAPPED_DOCS = ['docs/sources.md', 'docs/machine_setup.md'];
const docSizes = docs.filter((d) => /^docs\/[^/]+\.md$/.test(d) && !UNCAPPED_DOCS.includes(d))
  .map((d) => [d, lineCount(d)]).sort((a, b) => b[1] - a[1]);
const docsLines = docSizes.reduce((sum, [, n]) => sum + n, 0);
if (docsLines > DOCS_LINE_CAP) {
  overBudget.push(`  docs/*.md: ${docsLines} lines in total, cap ${DOCS_LINE_CAP} (largest: ` +
    `${docSizes.slice(0, 5).map(([d, n]) => `${d.slice(5)} ${n}`).join(', ')})`);
}

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

// Measured figures (a number with an output unit) outside a generated `<!-- measure:<id> -->`
// region in docs/*.md; backticked spans (code values, run lines) are skipped. They go stale when
// vehicle code moves; a region refreshes by re-running its tool. A ratchet: the cap only goes down.
// Code comments are not scanned: their figures are mostly set tolerances, not measurements.
// `(?!\d{4}s\b)`: a decade or product name ("1990s", "3000s"), not seconds.
const MEASURED_FIGURE = /(?<![\w.])(?!\d{4}s\b)\d+(?:\.\d+)?\s?(?:s|ms|µs|g|km\/h|fps|mm|kN|N|°)(?![\w/²])/g;
const MEASURED_FIGURE_CAP = 25;
const figureHits = [];
for (const f of docs.filter((d) => /^docs\/[^/]+\.md$/.test(d))) {
  let inRegion = false;
  read(f).split('\n').forEach((line, i) => {
    if (/<!-- measure:/.test(line)) return void (inRegion = true);
    if (/<!-- \/measure:/.test(line)) return void (inRegion = false);
    if (!inRegion) for (const m of line.replace(/`[^`\n]+`/g, '').matchAll(MEASURED_FIGURE)) figureHits.push(`  ${f}:${i + 1}: ${m[0]}`);
  });
}
if (figureHits.length > MEASURED_FIGURE_CAP) {
  overBudget.push(`  measured figures outside a measure region: ${figureHits.length}, cap ${MEASURED_FIGURE_CAP}`);
}

if (problems.length === 0 && overBudget.length === 0 && longComments.length === 0) {
  console.log('check_docs: every reference resolves; every CLAUDE.md, docs/ and comment block is within budget.');
  // Headroom up front, so a doc edit is sized to fit instead of trimmed by trial afterwards.
  console.log(`check_docs: headroom: CLAUDE.md ${rootClaudeLines}/${CLAUDE_MD_BUDGET['CLAUDE.md']}, ` +
    `docs/*.md ${docsLines}/${DOCS_LINE_CAP}, measured figures ${figureHits.length}/${MEASURED_FIGURE_CAP}.`);
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
if (figureHits.length > MEASURED_FIGURE_CAP) {
  console.log(`\ncheck_docs: measured figures outside a measure region:\n`);
  console.log(figureHits.join('\n'));
  console.log('\nA measured output (speed, time, g, force, tick, cost) lives only in a generated');
  console.log('`<!-- measure:<id> -->` region; prose points at it (§ name) instead of quoting it. A value');
  console.log('set in code is cited by its name (`GroundDriveSpec.axle_radius`), not its number. Lower');
  console.log('MEASURED_FIGURE_CAP as hits are fixed; raising it is a decision.');
}
if (longComments.length > 0) {
  console.log(`\ncheck_docs: comment block over ${COMMENT_BLOCK_CAP} lines:\n`);
  console.log(longComments.join('\n'));
  console.log('\nKeep the constraint at its site in one or two sentences; move the derivation to docs/ and');
  console.log('leave a one-line pointer (root CLAUDE.md § Where things go).');
}
process.exit(1);
