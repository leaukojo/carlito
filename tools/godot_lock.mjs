// The per-checkout Godot run lock, shared by tools/godot_run.mjs (writer), the Claude PreToolUse
// guard, the Stop hook and pre-commit (readers). It lives in .godot/, which is gitignored and per
// checkout, so two clones or worktrees never see each other's lock.
//   node tools/godot_lock.mjs    # prints the live holder and exits 1, or exits 0 when free
import fs from 'fs';
import path from 'path';
import { execFileSync } from 'child_process';
import { fileURLToPath } from 'url';

export const lockPath = repo => path.join(repo, '.godot', 'godot_run.lock');

// Alive AND still a process the lock could own: a PID left in a stale lock is reused by the OS,
// and --kill-stale must never kill whatever got that number.
const OURS = /^(node|godot|cmd|sh|bash)/i;
export function alive(pid) {
  if (!pid) return false;
  try { process.kill(pid, 0); } catch (e) { if (e.code !== 'EPERM') return false; }
  try {
    const name = process.platform === 'win32'
      ? execFileSync('tasklist', ['/FI', `PID eq ${pid}`, '/FO', 'CSV', '/NH'], { encoding: 'utf8' }).split(',')[0].replace(/"/g, '')
      : execFileSync('ps', ['-p', String(pid), '-o', 'comm='], { encoding: 'utf8' }).trim().split('/').pop();
    return OURS.test(name.trim());
  } catch { return false; }
}

export function readLock(repo) {
  try { return JSON.parse(fs.readFileSync(lockPath(repo), 'utf8')); } catch { return null; }
}

// A one-line description of the live run holding the lock, or null (a dead lock reads as free).
export function lockHolder(repo) {
  const l = readLock(repo);
  if (!l || !(alive(l.godot_pid) || alive(l.wrapper_pid))) return null;
  const orphan = !alive(l.wrapper_pid) ? ', wrapper gone: an orphaned Godot' : '';
  return `pid ${l.godot_pid}${orphan}, since ${l.started}: ${l.args}`;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const held = lockHolder(path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..'));
  if (held) { console.log(held); process.exit(1); }
}
