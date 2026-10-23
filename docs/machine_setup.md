# Setting up a new machine

What a fresh clone needs before Godot, the git hooks and Claude Code work the same as on every
other machine. Most of it travels with the repo; this page covers the per-machine rest.

## Install

| Tool | Why | Get it |
|---|---|---|
| Godot **4.7.1-stable**, the `_console.exe` build | every run; the plain exe prints nothing headless | godotengine.org download archive |
| Git for Windows, with Git Bash | the git hooks and the Claude Code hooks run in bash | git-scm.com |
| Node.js 18+ | the doc/text checks, the Godot wrapper, the hooks | nodejs.org (LTS) |
| the `sloppycan` repo, cloned next to this one | contract sync gates (they skip without it) | `git clone` into `..\sloppycan` |
| poppler (`pdftoppm`), optional | lets Claude read scanned PDF sources | `winget install oschwartz10612.Poppler` |
| Python 3, optional | ad-hoc analysis (not the Microsoft Store stub) | python.org |

## Run once per clone

```powershell
powershell -ExecutionPolicy Bypass -File tools/setup_machine.ps1 -Godot "C:\<dir>\Godot_v4.7.1-stable_win64_console.exe"
```

`tools/setup_machine.ps1` is safe to re-run. In order, it:

1. checks the tools above;
2. records the Godot path (`git config carlito.godotbin`);
3. points git at the repo hooks (`git config core.hooksPath tools/git-hooks`);
4. on a clean tree, re-checks out files left with CRLF line endings by an older checkout;
5. builds the import cache and the level bakes;
6. records its version (`git config carlito.setupversion`).

When a Claude Code session starts on a clone that is missing any of this, it reports what is
missing (`tools/claude_hooks/session_check.mjs`).

## What travels with the repo (nothing to do)

- `.gitattributes`: LF line endings in every checkout, whatever `core.autocrlf` says.
- `.claude/settings.json`: Claude's hooks and the `PYTHONUTF8` setting, which stops non-ASCII
  text from failing under a non-UTF-8 Windows locale. The hooks:
  - `tools/claude_hooks/pretool_guard.mjs` (before shell, edit and web calls) blocks edits to repo files
    made through a shell, `--no-verify`, email addresses in web requests, Godot runs that bypass
    the wrapper, and changes to the tree while a Godot run reads it;
  - `session_check.mjs` runs at session start;
  - the freshness check runs on Stop.
- `tools/godot_run.mjs`: the headless-Godot wrapper (a lock per checkout, a timeout,
  kill-on-parse-error).
- The pre-commit hook, `tools/preflight.ps1` and CI, which share their gates, including
  `tools/check_gd_text.mjs`.

## Per machine, by design

- `git config carlito.godotbin`, `core.hooksPath` and `carlito.setupversion`: local git config,
  set by the setup script.
- `.godot/` (the import cache, and `godot_run.lock`) and `*.baked.scn`: gitignored build output.
- `~/.claude/` (Claude's personal memory and global settings) does not travel. A rule that must
  hold on every machine goes in a CLAUDE.md, never only in memory.
