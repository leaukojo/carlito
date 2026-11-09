# Carlito preflight — "am I safe to push?" in one command.
# Mirrors the CI gates locally: import -> gdUnit4 -> stale-bake check -> headless smoke ->
# node gates (orphans, docs, GDScript text incl. the editor-type gate, head include, contract sync).
#   powershell -ExecutionPolicy Bypass -File tools/preflight.ps1
# Every Godot step goes through tools/godot_run.mjs (lock, timeout, parse-kill) and is judged by
# tools/godot_verdict.mjs, which also fails a wrapper refusal, timeout or parse kill.
$ErrorActionPreference = 'Continue'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

function Fail($name) { Write-Host "PREFLIGHT FAILED: $name" -ForegroundColor Red; exit 1 }
function Announce($name) { Write-Host "`n== $name" -ForegroundColor Cyan }

$held = node tools/godot_lock.mjs
if ($LASTEXITCODE -ne 0) { Fail "a Godot run holds this checkout ($held); wait, or: node tools/godot_run.mjs --kill-stale" }

Announce 'Import'
# --import's exit code is unreliable right after new files appear (leak-at-exit noise).
$imp = node tools/godot_run.mjs -- --headless --path . --import 2>&1 | Out-String
$imp | node tools/godot_verdict.mjs --script-errors
if ($LASTEXITCODE -ne 0) { Fail 'import' }

Announce 'Unit tests (gdUnit4)'
node tools/godot_run.mjs --tests -- -a tests
if ($LASTEXITCODE -ne 0) { Fail 'unit tests' }

Announce 'Stale-bake check'
# Same leak-at-exit unreliability as import above — judge by output, not process code.
$bakes = node tools/godot_run.mjs -- --headless --path . res://tools/check_bakes.tscn 2>&1 | Out-String
Write-Host $bakes
$bakes | node tools/godot_verdict.mjs --bakes
if ($LASTEXITCODE -ne 0) { Fail 'stale-bake check' }

Announce 'Headless smoke'
# Judged by output, not exit code: no errors, and boot.gd's level-OK line (printed after the first spawn).
$smoke = node tools/godot_run.mjs -- --headless --path . --quit-after 120 2>&1 | Out-String
$smoke | node tools/godot_verdict.mjs --errors
if ($LASTEXITCODE -ne 0) { Fail 'headless smoke' }
if ($smoke -notmatch '(?m)^Carlito level OK: ') { Fail 'headless smoke (no level-OK line — the level never finished loading)' }

Announce 'Orphan check'
node tools/check_orphans.mjs
if ($LASTEXITCODE -ne 0) { Fail 'orphan check (wire it up, delete it, or add it to tools/orphans_allow.txt)' }

Announce 'Doc reference check'
node tools/check_docs.mjs
if ($LASTEXITCODE -ne 0) { Fail 'doc references (fix the doc, or add it to tools/docs_allow.txt)' }

Announce 'GDScript text check'
node tools/check_gd_text.mjs
if ($LASTEXITCODE -ne 0) { Fail 'GDScript text (a dropped line break, or an editor-only type annotation)' }

Announce 'Head-include sync check'
node tools/check_head_include.mjs
if ($LASTEXITCODE -ne 0) { Fail 'head-include sync (export_presets.cfg vs src/bridge/web/head_include.html)' }

Announce 'Contract sync check'
node tools/gen_js_contract.mjs --check
if ($LASTEXITCODE -ne 0) { Fail 'contract sync' }

Write-Host "`nPREFLIGHT PASSED" -ForegroundColor Green
