#!/usr/bin/env node
// Generates sloppycan/carlito_contract.js from the canonical contract JSON: sloppyCAN
// consumes a committed JS-global copy so it loads from file:// (Web Serial forces that)
// with no build step. Run after editing the contract:
//     node tools/gen_js_contract.mjs
// The runtime version-mismatch console warning is the drift guard. A contract bump is a
// paired change across both repos' dev branches, promoted together.
//
// The sloppycan checkout is expected as a sibling of this repo (both under EXPORTABLE/).

import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const srcPath = resolve(here, '../contract/carlito_contract.json');
const outDir = resolve(here, '../../sloppycan');
const outPath = resolve(outDir, 'carlito_contract.js');

if (!existsSync(outDir)) {
  console.error(
    `Sibling sloppycan checkout not found at ${outDir}.\n` +
    `Clone https://github.com/leaukojo/sloppycan next to this repo, then re-run.`,
  );
  process.exit(1);
}

const contract = JSON.parse(readFileSync(srcPath, 'utf8')); // throws on malformed JSON
const banner =
`// GENERATED from carlito/contract/carlito_contract.json — do not edit by hand.
// Regenerate with:  node tools/gen_js_contract.mjs  (in the carlito repo)
// Canonical contract lives in the carlito repo; this is the synced copy sloppyCAN consumes.
`;
const body = `window.CARLITO_CONTRACT = ${JSON.stringify(contract, null, 2)};\n`;
writeFileSync(outPath, banner + body);
console.log(`Wrote ${outPath} (contract v${contract.version}, ${contract.signals.length} signals)`);
