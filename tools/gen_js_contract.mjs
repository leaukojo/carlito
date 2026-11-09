#!/usr/bin/env node
// Generates sloppycan/js/carlito_contract.js from the canonical contract JSON: sloppyCAN
// consumes a committed JS-global copy so it loads from file:// (Web Serial forces that)
// with no build step. Run after editing the contract:
//     node tools/gen_js_contract.mjs
//     node tools/gen_js_contract.mjs --check   # the gates' form: exit 1 when the copy was stale
// The body is the contract's own text, verbatim (CRLF -> LF, ends trimmed), and beside it
// CARLITO_CONTRACT_HASH is the SHA-256 of exactly that text. contract.gd hashes the same bytes,
// so both sides warn at runtime on a version OR content mismatch, and sloppyCAN CI re-hashes the
// embedded body to catch a hand edit to this copy. A contract bump is a paired change across
// both repos' dev branches, promoted together.
//
// The sloppycan checkout is expected as a sibling of this repo (both under EXPORTABLE/). Without
// it a plain run fails (it cannot do what was asked); --check skips with a note and exits 0, as
// a machine without sloppyCAN has no copy to keep in sync.

import { createHash } from 'node:crypto';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const srcPath = resolve(here, '../contract/carlito_contract.json');
const outDir = resolve(here, '../../sloppycan');
const outPath = resolve(outDir, 'js', 'carlito_contract.js');
const check = process.argv.slice(2).includes('--check');

if (!existsSync(outDir)) {
  if (check) {
    console.log(`Sibling sloppycan checkout not found at ${outDir}: contract sync check skipped.`);
    process.exit(0);
  }
  console.error(
    `Sibling sloppycan checkout not found at ${outDir}.\n` +
    `Clone https://github.com/leaukojo/sloppycan next to this repo, then re-run.`,
  );
  process.exit(1);
}

// Trims ASCII 0-32 only, exactly GDScript's strip_edges() (JS trim() also strips Unicode spaces).
const source = readFileSync(srcPath, 'utf8').replace(/\r\n/g, '\n').replace(/^[\x00-\x20]+|[\x00-\x20]+$/g, '');
const contract = JSON.parse(source); // throws on malformed JSON
const hash = createHash('sha256').update(source, 'utf8').digest('hex');
const banner =
`// GENERATED from carlito/contract/carlito_contract.json — do not edit by hand.
// Regenerate with:  node tools/gen_js_contract.mjs  (in the carlito repo)
// Canonical contract lives in the carlito repo; this is the synced copy sloppyCAN consumes.
// CARLITO_CONTRACT_HASH is the SHA-256 of the contract object's text: from its opening "{" to the
// "}" just before the hash line (descs contain ";", so not to the first one). CI re-checks it.
`;
const body = `window.CARLITO_CONTRACT = ${source};\nwindow.CARLITO_CONTRACT_HASH = "${hash}";\n`;
const text = banner + body;
// CRLF-normalized: a sloppycan checkout under core.autocrlf is not stale for its line endings.
const before = existsSync(outPath) ? readFileSync(outPath, 'utf8').replace(/\r\n/g, '\n') : null;
if (before !== text) writeFileSync(outPath, text);
console.log(`${before === text ? 'Up to date' : 'Wrote'} ${outPath} (contract v${contract.version} ${hash.slice(0, 12)}, ${contract.signals.length} signals)`);
if (check && before !== text) {
  console.error('sloppyCAN contract copy was stale: just regenerated it. Review + commit it in the sloppycan repo.');
  process.exit(1);
}
