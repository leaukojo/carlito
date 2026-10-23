// Runs headless Godot (or the gdUnit4 suite) with the guards a bare call lacks:
//   - one run per checkout (lock in .godot/, see godot_lock.mjs); a second run is refused;
//   - a wall-clock timeout, then the whole process tree is killed;
//   - a parse error or the interactive `debug>` prompt kills the run at once (headless Godot
//     otherwise sits there until the timeout: a shadowed built-in name is a parse error here);
//   - Ctrl-C / stop kills the tree, so no Godot outlives its caller.
//
//   node tools/godot_run.mjs [--timeout=SECONDS] [--keep-going] -- <godot args>
//   node tools/godot_run.mjs --tests [--timeout=SECONDS] -- -a tests
//   node tools/godot_run.mjs --kill-stale          # kill a Godot left behind by a killed caller
//
// Godot binary: $GODOT_BIN -> `git config carlito.godotbin` -> `godot` on PATH (godot_bin.ps1).
// The exit code is the child's (124 on timeout, 125 on a kill for a parse error). Judge a run by
// its output anyway (root CLAUDE.md): the last line is always a `[godot_run]` summary.
import { spawn, execFileSync } from 'child_process';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { lockPath, readLock, lockHolder, alive } from './godot_lock.mjs';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const WIN = process.platform === 'win32';
const argv = process.argv.slice(2);
const dd = argv.indexOf('--');
const opts = dd < 0 ? argv : argv.slice(0, dd);
const rest = dd < 0 ? [] : argv.slice(dd + 1);
const flag = n => opts.includes(n);
const timeoutS = Number((opts.find(o => o.startsWith('--timeout=')) || '--timeout=900').split('=')[1]);
const say = m => process.stdout.write(`[godot_run] ${m}\n`);

function killTree(pid) {
  if (!alive(pid)) return;
  try {
    if (WIN) execFileSync('taskkill', ['/PID', String(pid), '/T', '/F'], { stdio: 'ignore' });
    else process.kill(-pid, 'SIGKILL');
  } catch { /* already gone */ }
}

if (flag('--kill-stale')) {
  const l = readLock(repo);
  if (l && alive(l.godot_pid) && !alive(l.wrapper_pid)) { killTree(l.godot_pid); say(`killed orphaned pid ${l.godot_pid}`); }
  else if (l && alive(l.wrapper_pid)) { killTree(l.wrapper_pid); killTree(l.godot_pid); say(`stopped the live run (pid ${l.godot_pid})`); }
  else say('no live run');
  try { fs.unlinkSync(lockPath(repo)); } catch { /* none */ }
  process.exit(0);
}

const held = lockHolder(repo);
if (held) {
  say(`refused: a Godot run already holds this checkout (${held}).`);
  say('Two headless Godots on one checkout corrupt the import cache. Wait, or: node tools/godot_run.mjs --kill-stale');
  process.exit(1);
}

function resolveGodot() {
  let bin = process.env.GODOT_BIN;
  if (!bin) { try { bin = execFileSync('git', ['config', '--get', 'carlito.godotbin'], { cwd: repo, encoding: 'utf8' }).trim(); } catch { /* unset */ } }
  if (bin) {
    if (!fs.existsSync(bin)) { say(`configured Godot binary does not exist: ${bin}`); process.exit(1); }
  } else bin = 'godot';
  // The plain Windows exe swallows print/push_error, so a headless run comes back silent.
  if (WIN && /\.exe$/i.test(bin) && !/console/i.test(path.basename(bin))) {
    say(`${bin} is not the _console build; set carlito.godotbin to Godot_v<ver>-stable_win64_console.exe (docs/machine_setup.md).`);
    process.exit(1);
  }
  return bin;
}

const godot = resolveGodot();
const tests = flag('--tests');
if (!rest.includes('--import') && !fs.existsSync(path.join(repo, '.godot', 'imported'))) {
  say('no import cache in this checkout (fresh clone or worktree): run `node tools/godot_run.mjs -- --headless --path . --import` first.');
  process.exit(1);
}
const [cmd, args] = tests
  ? (WIN ? ['cmd.exe', ['/d', '/c', path.join('addons', 'gdUnit4', 'runtest.cmd'), ...rest]]
         : ['sh', [path.join('addons', 'gdUnit4', 'runtest.sh'), ...rest]])
  : [godot, rest];

const child = spawn(cmd, args, {
  cwd: repo, stdio: ['ignore', 'pipe', 'pipe'], detached: !WIN, windowsHide: true,
  env: { ...process.env, GODOT_BIN: godot },
});
child.on('error', e => { say(`could not start ${cmd}: ${e.message}`); process.exit(1); });
if (!child.pid) await new Promise(() => {}); // the 'error' handler exits; no lock for a failed spawn
const started = new Date();
fs.mkdirSync(path.join(repo, '.godot'), { recursive: true });
fs.writeFileSync(lockPath(repo), JSON.stringify({
  wrapper_pid: process.pid, godot_pid: child.pid, started: started.toISOString().slice(0, 19),
  args: [tests ? 'tests' : 'godot', ...rest].join(' '),
}));

let why = null;
function stop(reason) { if (!why) why = reason; killTree(child.pid); }
const timer = setTimeout(() => stop('timeout'), timeoutS * 1000);
const FATAL = /Parse Error|^debug> /m;
// A first import prints transient parse errors until the class cache exists.
const failFast = !flag('--keep-going') && !rest.includes('--import');
let tail = '';
function pump(stream, out) {
  stream.on('data', buf => {
    out.write(buf);
    tail = (tail + buf.toString()).slice(-4096);
    if (failFast && FATAL.test(tail)) stop('parse');
  });
}
pump(child.stdout, process.stdout);
pump(child.stderr, process.stderr);
for (const sig of ['SIGINT', 'SIGTERM', 'SIGHUP', 'SIGBREAK']) process.on(sig, () => { stop('signal'); });

child.on('close', code => {
  clearTimeout(timer);
  try { if (readLock(repo)?.wrapper_pid === process.pid) fs.unlinkSync(lockPath(repo)); } catch { /* gone */ }
  const s = ((Date.now() - started) / 1000).toFixed(1);
  const exit = why === 'timeout' ? 124 : why === 'parse' ? 125 : (code ?? 1);
  const note = { timeout: ` TIMEOUT after ${timeoutS}s, process tree killed (raise with --timeout=)`,
    parse: ' killed: parse error or debugger prompt (fix the script; --keep-going to disable)',
    signal: ' stopped by signal' }[why] || '';
  say(`exit=${exit} elapsed=${s}s${note}`);
  process.exit(exit);
});
