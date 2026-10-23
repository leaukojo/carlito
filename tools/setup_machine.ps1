# One-time setup of a clone on a new machine (docs/machine_setup.md). Safe to re-run: each step
# checks before it acts, and the last one records SETUP_VERSION so the Claude SessionStart
# check (tools/claude_hooks/session_check.mjs) stops nagging.
#   powershell -ExecutionPolicy Bypass -File tools/setup_machine.ps1 [-Godot <console exe>]
param([string]$Godot)
$ErrorActionPreference = 'Continue'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo
# Bump with session_check.mjs's SETUP_VERSION when a step is added, so every machine re-runs.
$SETUP_VERSION = 1
$failed = @()
function Ok($m)   { Write-Host "  ok    $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  warn  $m" -ForegroundColor Yellow }
function Bad($m)  { Write-Host "  FAIL  $m" -ForegroundColor Red; $script:failed += $m }

Write-Host '== Prerequisites' -ForegroundColor Cyan
if (Get-Command node -ErrorAction SilentlyContinue) {
    $v = (node --version).TrimStart('v'); if ([int]($v.Split('.')[0]) -ge 18) { Ok "node $v" } else { Bad "node $v is older than 18" }
} else { Bad 'node is not on PATH (https://nodejs.org, LTS)' }
# Claude Code finds Git Bash beside git itself; it need not be on PATH.
$gitExe = (Get-Command git -ErrorAction SilentlyContinue).Source
$bash = if ($gitExe) { Join-Path (Split-Path (Split-Path $gitExe)) 'bin\bash.exe' }
if ((Get-Command bash -ErrorAction SilentlyContinue) -or ($bash -and (Test-Path $bash))) { Ok 'Git Bash (runs the git hooks and Claude Code hooks)' }
else { Bad 'Git Bash not found: install Git for Windows (git-scm.com) with its bash' }
if (Test-Path (Join-Path $repo '..\sloppycan')) { Ok 'sloppycan sibling repo' }
else { Warn 'no ..\sloppycan clone: the contract sync gates skip until it exists' }
$py = Get-Command python -ErrorAction SilentlyContinue
if ($py -and $py.Source -notmatch 'WindowsApps') { Ok "python ($($py.Source))" }
else { Warn 'python missing (or only the Microsoft Store stub): optional, used for ad-hoc analysis' }
if (Get-Command pdftoppm -ErrorAction SilentlyContinue) { Ok 'pdftoppm (poppler: lets Claude read scanned PDF sources)' }
else { Warn 'pdftoppm missing: winget install oschwartz10612.Poppler  (then reopen the shell)' }

Write-Host '== Godot' -ForegroundColor Cyan
if (-not $Godot) { $Godot = git config --get carlito.godotbin }
if (-not $Godot) { $c = Get-Command godot -ErrorAction SilentlyContinue; if ($c) { $Godot = $c.Source } }
if (-not $Godot -or -not (Test-Path -LiteralPath $Godot)) {
    Bad 'Godot not found: re-run with -Godot "<dir>\Godot_v4.7.1-stable_win64_console.exe"'
} else {
    if ((Split-Path -Leaf $Godot) -notmatch 'console') { Bad "$Godot is not the _console build (headless output would be silent)" }
    $ver = (& $Godot --version 2>$null | Out-String).Trim()
    if ($ver -match '^4\.7\.1\.stable') { Ok "Godot $ver" } else { Warn "Godot reports '$ver'; the project pins 4.7.1-stable" }
    git config carlito.godotbin $Godot; Ok "git config carlito.godotbin = $Godot"
}

Write-Host '== Git' -ForegroundColor Cyan
git config core.hooksPath tools/git-hooks; Ok 'git config core.hooksPath = tools/git-hooks'
# .gitattributes forces LF, but files checked out before that keep CRLF until rewritten from the
# index. Done only on a clean tree: the re-checkout overwrites every tracked file.
$crlf = @(git ls-files --eol | Where-Object { $_ -match 'w/(crlf|mixed)' -and $_ -notmatch '\.(cmd|bat)$' })
if ($crlf.Count -eq 0) { Ok 'working tree is LF' }
elseif (git status --porcelain) { Bad "$($crlf.Count) files still CRLF/mixed; commit or stash your changes, then re-run" }
else {
    git read-tree (git write-tree)   # drops cached stat info so checkout-index rewrites every file
    git checkout-index -f -a
    $left = @(git ls-files --eol | Where-Object { $_ -match 'w/(crlf|mixed)' -and $_ -notmatch '\.(cmd|bat)$' }).Count
    if ($left -eq 0 -and -not (git status --porcelain)) { Ok "re-checked out $($crlf.Count) files as LF" } else { Bad "$left files still CRLF after re-checkout" }
}

if ($failed.Count -eq 0) {
    Write-Host '== Import cache and bakes' -ForegroundColor Cyan
    if (-not (Test-Path (Join-Path $repo '.godot\imported'))) {
        node tools/godot_run.mjs -- --headless --path . --import | Select-Object -Last 3
    }
    if (Test-Path (Join-Path $repo '.godot\imported')) { Ok 'import cache' } else { Bad 'import did not create .godot/imported' }
    $baked = Get-ChildItem -Path src -Recurse -Filter *.baked.scn -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $baked) { node tools/godot_run.mjs -- --headless --path . res://tools/bake_levels.tscn | Select-Object -Last 3 }
    if (Get-ChildItem -Path src -Recurse -Filter *.baked.scn -ErrorAction SilentlyContinue | Select-Object -First 1) { Ok 'level bakes' }
    else { Bad 'no .baked.scn after bake_levels (levels would run on dev collision)' }
}

if ($failed.Count) { Write-Host "`nSETUP INCOMPLETE ($($failed.Count) failure(s) above)" -ForegroundColor Red; exit 1 }
git config carlito.setupversion $SETUP_VERSION
Write-Host "`nSETUP DONE (version $SETUP_VERSION)" -ForegroundColor Green
