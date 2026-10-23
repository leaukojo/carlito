# Carlito preflight — "am I safe to push?" in one command.
# Mirrors the CI gates locally: editor-type gate -> import -> gdUnit4 -> stale-bake
# check -> headless smoke -> contract sync check.
#   powershell -ExecutionPolicy Bypass -File tools/preflight.ps1
# Every Godot step goes through tools/godot_run.mjs (lock, timeout, parse-kill).
$ErrorActionPreference = 'Continue'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

function Fail($name) { Write-Host "PREFLIGHT FAILED: $name" -ForegroundColor Red; exit 1 }
function Announce($name) { Write-Host "`n== $name" -ForegroundColor Cyan }
# A wrapper refusal, timeout or parse kill prints no Godot error, so the output gates alone would pass it.
function CheckRun($out, $name) {
    if ($out -match '\[godot_run\] (refused|could not start|configured|no import cache|.*is not the _console)|\[godot_run\] exit=12[45]') {
        Write-Host $out; Fail "$name ($($Matches[0]))"
    }
}

$held = node tools/godot_lock.mjs
if ($LASTEXITCODE -ne 0) { Fail "a Godot run holds this checkout ($held); wait, or: node tools/godot_run.mjs --kill-stale" }

Announce 'Editor-type annotation gate'
$bad = git grep -nE '^[^#]*((:|->)[[:space:]]*|Array\[|[[:space:]]as[[:space:]]+)Editor[A-Z][A-Za-z0-9]*' -- 'src/*.gd' 'kit/*.gd' 'tools/*.gd' 'tests/*.gd'
if ($bad) { $bad; Write-Host 'editor-only type annotation outside addons/ (breaks exported builds)'; Fail 'editor-type gate' }

Announce 'Import'
# --import's exit code is unreliable right after new files appear (leak-at-exit noise).
$imp = node tools/godot_run.mjs -- --headless --path . --import 2>&1 | Out-String
CheckRun $imp 'import'
$impErrors = ($imp -split "`n") | Select-String -Pattern 'SCRIPT ERROR|Failed to load|Compile Error'
if ($impErrors) { $impErrors; Fail 'import' }

Announce 'Unit tests (gdUnit4)'
node tools/godot_run.mjs --tests -- -a tests
if ($LASTEXITCODE -ne 0) { Fail 'unit tests' }

Announce 'Stale-bake check'
# Same leak-at-exit unreliability as import above — judge by output, not process code.
$bakes = node tools/godot_run.mjs -- --headless --path . res://tools/check_bakes.tscn 2>&1 | Out-String
Write-Host $bakes
CheckRun $bakes 'stale-bake check'
$staleBakes = ($bakes -split "`n") | Select-String -Pattern '\[check-bakes\].*: (stale|missing|error)'
if ($staleBakes) { Fail 'stale-bake check (run: node tools/godot_run.mjs -- --headless --path . res://tools/bake_levels.tscn)' }
if ($bakes -notmatch '\[check-bakes\] complete:') { Fail 'stale-bake check (no completion sentinel — the run did not finish)' }

Announce 'Headless smoke'
# Judged by output, not exit code: no errors, and boot.gd's level-OK line (printed after the first spawn).
$smoke = node tools/godot_run.mjs -- --headless --path . --quit-after 120 2>&1 | Out-String
CheckRun $smoke 'headless smoke'
$errors = ($smoke -split "`n") | Select-String -Pattern 'SCRIPT ERROR|ERROR:' |
    Where-Object { $_ -notmatch 'still in use at exit|leaked at exit|Pages in use exist at exit' }
if ($errors) { $errors; Fail 'headless smoke' }
if ($smoke -notmatch '(?m)^Carlito level OK: ') { Fail 'headless smoke (no level-OK line — the level never finished loading)' }

Announce 'Orphan check'
node tools/check_orphans.mjs
if ($LASTEXITCODE -ne 0) { Fail 'orphan check (wire it up, delete it, or add it to tools/orphans_allow.txt)' }

Announce 'Doc reference check'
node tools/check_docs.mjs
if ($LASTEXITCODE -ne 0) { Fail 'doc references (fix the doc, or add it to tools/docs_allow.txt)' }

Announce 'GDScript text check'
node tools/check_gd_text.mjs
if ($LASTEXITCODE -ne 0) { Fail 'GDScript text (a scripted edit dropped a line break; restore it with Edit)' }

Announce 'Head-include sync check'
node tools/check_head_include.mjs
if ($LASTEXITCODE -ne 0) { Fail 'head-include sync (export_presets.cfg vs src/bridge/web/head_include.html)' }

Announce 'Contract sync check'
$out = Join-Path $repo '..\sloppycan\carlito_contract.js'
if (Test-Path $out) {
    $before = (Get-FileHash $out).Hash
    node tools/gen_js_contract.mjs | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail 'contract regen' }
    if ((Get-FileHash $out).Hash -ne $before) {
        Write-Host 'sloppyCAN contract copy was stale — regenerated; commit it in the sloppycan repo.' -ForegroundColor Yellow
        Fail 'contract sync'
    }
} else {
    Write-Host 'sloppycan repo not found next to this repo — skipping sync check' -ForegroundColor Yellow
}

Write-Host "`nPREFLIGHT PASSED" -ForegroundColor Green
