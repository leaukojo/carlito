// The verdict on a headless Godot log, read on stdin, for the gates that judge a run by its output
// rather than its exit code (root CLAUDE.md): CI, pre-commit, preflight, the Stop hook and
// rebuild_level.ps1. Exits 0 on a pass; on a fail, prints why (and the lines) and exits 1.
//   ... | node tools/godot_verdict.mjs --bakes           # check_bakes: no stale line, and its sentinel
//   ... | node tools/godot_verdict.mjs --errors [--allow=<regex>]   # no error beyond leak-at-exit noise
//   ... | node tools/godot_verdict.mjs --script-errors   # no script or load error (engine ERROR: lines pass)
// Every mode also fails a `godot_run.mjs` refusal, start failure, timeout or parse kill: those print
// no Godot error, so the output checks alone would pass them.
import fs from 'fs';

const argv = process.argv.slice(2);
const mode = ['--bakes', '--errors', '--script-errors'].find(m => argv.includes(m));
if (!mode) { console.error('godot_verdict: pass --bakes, --errors or --script-errors'); process.exit(2); }
const allowArg = argv.find(a => a.startsWith('--allow='));
const allow = allowArg ? new RegExp(allowArg.slice('--allow='.length)) : null;

const lines = fs.readFileSync(0, 'utf8').split(/\r?\n/);
function fail(why, bad = []) {
  console.log(`godot_verdict: ${why}`);
  for (const l of bad) console.log(`  ${l}`);
  process.exit(1);
}

const WRAPPER = /\[godot_run\] (refused|could not start|configured|no import cache|.*is not the _console)|\[godot_run\] exit=12[45]/;
const wrapper = lines.filter(l => WRAPPER.test(l));
if (wrapper.length) fail('the godot_run wrapper stopped the run', wrapper);

// Known-harmless leak-at-exit noise, printed after the run's real work ("Pages in use" is
// PagedAllocator, Linux only).
const NOISE = /still in use at exit|leaked at exit|Pages in use exist at exit/;

if (mode === '--bakes') {
  // Unanchored: PowerShell 5.1 prefixes the first captured stderr line with the exe name.
  const stale = lines.filter(l => /\[check-bakes\].*: (stale|missing|error)/.test(l));
  if (stale.length) fail('stale bakes or road paint (fix as named), then re-bake: node tools/godot_run.mjs -- --headless --path . res://tools/bake_levels.tscn', stale);
  const done = lines.map(l => l.match(/\[check-bakes\] complete: \d+ fresh, \d+ unbuilt, (\d+) stale/)).find(Boolean);
  if (!done) fail('check_bakes printed no completion sentinel: the run did not finish. Its last lines:',
    lines.filter(l => l.trim()).slice(-8));
  if (Number(done[1]) !== 0) fail(`check_bakes counted ${done[1]} stale level(s)`, [done[0]]);
} else {
  const pattern = mode === '--errors' ? /SCRIPT ERROR|ERROR:|Failed to load|Compile Error/
    : /SCRIPT ERROR|Failed to load|Compile Error/;
  const bad = lines.filter(l => pattern.test(l) && !NOISE.test(l) && !(allow && allow.test(l)));
  if (bad.length) fail(`${bad.length} error line(s) in the log`, bad);
}
