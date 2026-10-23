// Claude Code SessionStart check (.claude/settings.json): reports what this clone or machine is
// missing, so a fresh clone on another PC is set up before work starts, not discovered by a
// failing hook halfway through. Silent when everything is in place; never blocks.
import fs from 'fs';
import path from 'path';
import { execFileSync } from 'child_process';
import { lockHolder } from '../godot_lock.mjs';

// Bump with tools/setup_machine.ps1's $SETUP_VERSION when the setup gains a step.
const SETUP_VERSION = 1;
const repo = process.env.CLAUDE_PROJECT_DIR || process.cwd();
const git = (...a) => { try { return execFileSync('git', a, { cwd: repo, encoding: 'utf8' }).trim(); } catch { return ''; } };
const issues = [];

if (Number(git('config', '--get', 'carlito.setupversion') || 0) < SETUP_VERSION) {
  issues.push(`setup version ${git('config', '--get', 'carlito.setupversion') || 'none'} < ${SETUP_VERSION} on this clone`);
}
if (git('config', '--get', 'core.hooksPath') !== 'tools/git-hooks') issues.push('core.hooksPath is not tools/git-hooks: the pre-commit gates never run');
const godot = process.env.GODOT_BIN || git('config', '--get', 'carlito.godotbin');
if (!godot) issues.push('no Godot binary configured (git config carlito.godotbin)');
else if (!fs.existsSync(godot)) issues.push(`configured Godot binary is missing: ${godot}`);
if (!fs.existsSync(path.join(repo, '.godot', 'imported'))) issues.push('no import cache (.godot/imported): tests and runs fail to parse');

function hasBake(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.isFile() && e.name.endsWith('.baked.scn')) return true;
    if (e.isDirectory() && hasBake(path.join(dir, e.name))) return true;
  }
  return false;
}
try { if (!hasBake(path.join(repo, 'src', 'levels'))) issues.push('no .baked.scn: levels run on dev collision'); } catch { /* no levels dir */ }

const crlf = git('ls-files', '--eol').split('\n').filter(l => /w\/(crlf|mixed)/.test(l) && !/\.(cmd|bat)$/.test(l)).length;
if (crlf) issues.push(`${crlf} working-tree files are CRLF/mixed (checked out before .gitattributes forced LF): exact-match edits will miss`);

const held = lockHolder(repo);
if (held) issues.push(`a Godot run from an earlier session still holds this checkout (${held}): node tools/godot_run.mjs --kill-stale`);

if (issues.length) {
  console.log('Carlito clone/machine setup is incomplete:\n' + issues.map(i => `  - ${i}`).join('\n') +
    '\nTell the user, and offer to run: powershell -ExecutionPolicy Bypass -File tools/setup_machine.ps1' +
    ' (docs/machine_setup.md). A Godot path the user must supply goes in as -Godot "<path>".');
}
