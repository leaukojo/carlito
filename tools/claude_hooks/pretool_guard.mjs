// Claude Code PreToolUse guard (.claude/settings.json). Reads the hook JSON on stdin; exit 2
// blocks the call and feeds stderr back to Claude, exit 0 lets it through.
//
// Each rule stops a failure that recurred across sessions:
//   - multi-line edits through a shell (sed -i, heredoc/redirect, Set-Content, inline
//     python/node writes) dropped `\` continuations, mangled `§`/arrows and flipped line endings;
//   - git commit --no-verify skipped the pre-commit gates;
//   - a personal email address went out in a web request;
//   - Godot runs hung on a parse error, overlapped, or read a tree being edited or stashed.
import fs from 'fs';
import path from 'path';
import { lockHolder } from '../godot_lock.mjs';

let input;
try { input = JSON.parse(fs.readFileSync(0, 'utf8')); } catch { process.exit(0); }
const tool = input.tool_name || '';
const ti = input.tool_input || {};
const repo = process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd();

function block(msg) { process.stderr.write(`[pretool_guard] ${msg}\n`); process.exit(2); }

const SRC_EXT = /\.(gd|tscn|tres|gdshader|md|json|mjs|js|ps1|cfg|html|ya?ml|sh|txt|import|godot)$/i;
const TEMPISH = /(^|[\\/])(temp|tmp|scratchpad)([\\/]|$)|\$env:TEMP|%TEMP%|\$TMPDIR|^\/dev\/null$|^\$null$|^nul$/i;
const isRepoSource = p => SRC_EXT.test(p) && !TEMPISH.test(p);

// --- 1. Personal emails in anything that leaves the machine -------------------------------
const EMAIL = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g;
const EMAIL_OK = /^(noreply@anthropic\.com|git@[\w.-]+|[\w.+-]+@users\.noreply\.github\.com)$/i;
function checkOutbound(text, what) {
  const hits = (String(text).match(EMAIL) || []).filter(e => !EMAIL_OK.test(e));
  if (hits.length) block(`${what} contains an email address (${hits[0]}). Never send the user's ` +
    'address to an outside service (API contact fields included): drop the parameter or ask the user.');
}
const NET_CMD = /\b(curl|wget|Invoke-WebRequest|Invoke-RestMethod|iwr|irm)\b|https?:\/\//i;

// --- shell commands -------------------------------------------------------------------------
function checkShell(cmd) {
  if (NET_CMD.test(cmd)) checkOutbound(cmd, 'This network command');

  // 2. Hook bypass.
  if (/\bgit\b[^|;&\n]*\b(commit|push|merge|rebase|am)\b[^|;&\n]*(--no-verify|--no-gpg-sign)/.test(cmd) ||
      /\bgit\b[^|;&\n]*\bcommit\b[^|;&\n]*\s-[a-zA-Z]*n[a-zA-Z]*\b/.test(cmd) ||
      /commit\.gpgsign=false/.test(cmd)) {
    block('git hook/signing bypass. A failing pre-commit gate is fixed, not skipped; if the user ' +
      'explicitly asked to bypass it, they run that command themselves (`! git commit --no-verify ...`).');
  }

  // 3. Scripted edits of repo source files.
  const editHint = 'Edit repo files with the Edit/Write tools (they keep line endings, escapes and ' +
    'non-ASCII intact). Scratch output goes to the scratchpad directory.';
  if (/\bsed\b[^|;&\n]*\s(-i|--in-place)\b|\bperl\b[^|;&\n]*\s-[a-z]*i/.test(cmd) &&
      [...cmd.matchAll(/[^\s"'|;&<>]+/g)].some(m => isRepoSource(m[0]))) {
    block(`in-place sed/perl on a repo file. ${editHint}`);
  }
  // Redirect / tee targets (2>&1, >$null, >/dev/null stay allowed).
  for (const m of cmd.matchAll(/(?:^|[^0-9&>=-])>{1,2}\s*(["']?)([^\s"'|;&<>()]+)\1|\btee\s+(?:-a\s+)?(["']?)([^\s"'|;&<>]+)\3/g)) {
    const target = m[2] || m[4];
    if (target && !target.startsWith('&') && isRepoSource(target)) {
      block(`shell redirect writes to ${target}. ${editHint}`);
    }
  }
  // PowerShell writers.
  for (const m of cmd.matchAll(/\b(Set-Content|Add-Content|Out-File|WriteAllText|WriteAllLines|WriteAllBytes)\b([^|;\n]*)/gi)) {
    const args = m[2] || '';
    const target = [...args.matchAll(/["']([^"']+)["']|(\S+)/g)].map(x => x[1] || x[2]).find(isRepoSource);
    if (target) block(`${m[1]} writes to ${target} (PowerShell 5.1 also re-encodes it). ${editHint}`);
  }
  // Inline or scratch python/node scripts that write files.
  const WRITES = /writeFileSync|appendFileSync|write_text|write_bytes|open\([^)]*,\s*['"][wa]b?\+?['"]|\.write\(/;
  const inline = /\b(python3?|py|node)\b[^|;&\n]*\s(-c|-e|--eval)\s/.test(cmd) || /\b(python3?|py|node)\b\s*-\s*<</.test(cmd);
  const scripts = [...cmd.matchAll(/\b(?:python3?|py|node)\b(?:\s+-[A-Za-z]+)*\s+(["']?)([^\s"']+\.(?:py|mjs|cjs|js))\1/g)].map(m => m[2]);
  const bodies = inline ? [cmd] : [];
  for (const s of scripts) {
    const p = path.isAbsolute(s) ? s : path.join(repo, s);
    // Repo tools (tools/*.mjs) are reviewed code; only ad-hoc scripts outside the repo are read.
    if (!path.resolve(p).toLowerCase().startsWith(path.resolve(repo).toLowerCase() + path.sep)) {
      try { bodies.push(fs.readFileSync(p, 'utf8')); } catch { /* not found: nothing to inspect */ }
    }
  }
  for (const body of bodies) {
    // A string literal naming a source file (or a glob of them) that is not a scratch path.
    const targets = [...body.matchAll(/["'`]([^"'`\n]*\.(?:gd|tscn|tres|gdshader|md))["'`]/g)].map(m => m[1]);
    if (WRITES.test(body) && targets.some(t => !TEMPISH.test(t))) {
      block(`an ad-hoc python/node script writes repo .gd/.tscn/.tres/.md files. ${editHint} ` +
        'For a mechanical edit across many files, make the Edit calls (several per message).');
    }
  }

  // 4. Godot: one run per checkout, through the wrapper; nothing rewrites the tree under it.
  // Per command segment, by the program it starts: a grep FOR `$GODOT --headless` is not a run, and
  // a wrapper call chained with a bare one still has the bare one.
  const GODOT_PROG = /^(\$\{?GODOT\}?|\$env:GODOT_BIN|\$\{?GODOT_BIN\}?|godot(\.exe)?|.*[\\/]godot[^\\/]*\.exe)$/i;
  const segments = cmd.split(/&&|\|\||[;|\n]/).map(s => s.trim().replace(/^&\s*/, ''));
  const bare = segments.some(s => {
    const m = s.match(/^(?:"([^"]+)"|'([^']+)'|(\S+))/);
    const prog = m ? (m[1] || m[2] || m[3]) : '';
    return (GODOT_PROG.test(prog) && /--headless/.test(s)) ||
      (/runtest\.(cmd|sh)\b/.test(s) && !/^node\b/.test(s) && !/^(grep|rg|cat|sed|head|tail|git|Get-Content|Select-String)\b/i.test(s));
  });
  if (bare) {
    block('run headless Godot through the wrapper: `node tools/godot_run.mjs -- <godot args>` ' +
      '(tests: `node tools/godot_run.mjs --tests -- -a tests`). It enforces one run per checkout, ' +
      'a wall-clock timeout, kill-on-parse-error and process-tree cleanup.');
  }
  const held = lockHolder(repo);
  if (held && /\bgit\b[^|;&\n]*\b(stash|checkout|switch|restore|reset|rebase|merge|pull|cherry-pick)\b|preflight\.ps1/.test(cmd)) {
    block(`a Godot run is reading this tree (${held}). Wait for it, or stop it with ` +
      '`node tools/godot_run.mjs --kill-stale`, before changing the checkout.');
  }
}

if (tool === 'Bash' || tool === 'PowerShell') checkShell(String(ti.command || ''));
else if (tool === 'WebFetch') checkOutbound(`${ti.url || ''} ${ti.prompt || ''}`, 'This WebFetch');
else if (tool === 'WebSearch') checkOutbound(ti.query || '', 'This web search');
else if (tool === 'Agent' && ti.subagent_type === 'web-fetch') checkOutbound(ti.prompt || '', 'This web-fetch prompt');
else if (tool === 'Edit' || tool === 'Write' || tool === 'MultiEdit' || tool === 'NotebookEdit') {
  const f = String(ti.file_path || '');
  const held = /\.(gd|tscn|tres|gdshader)$/i.test(f) && lockHolder(repo);
  if (held) block(`a Godot run is loading scripts from this tree (${held}); editing ${path.basename(f)} now ` +
    'mixes two code versions in its output. Wait for it, or stop it with `node tools/godot_run.mjs --kill-stale`.');
}
process.exit(0);
