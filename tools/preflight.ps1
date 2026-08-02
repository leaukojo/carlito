# Carlito preflight — "am I safe to push?" in one command.
# Mirrors the CI gates locally: editor-type gate -> import -> gdUnit4 -> stale-bake
# check -> headless smoke -> contract sync check.
#   powershell -File tools/preflight.ps1
$ErrorActionPreference = 'Continue'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo
. (Join-Path $PSScriptRoot 'godot_bin.ps1')
$GODOT = Resolve-GodotBin

function Fail($name) { Write-Host "PREFLIGHT FAILED: $name" -ForegroundColor Red; exit 1 }
function Announce($name) { Write-Host "`n== $name" -ForegroundColor Cyan }

Announce 'Editor-type annotation gate'
$bad = git grep -nE '^[^#]*(:|->)[[:space:]]*Editor[A-Z][A-Za-z0-9]*' -- 'src/*.gd' 'kit/*.gd' 'tools/*.gd' 'tests/*.gd'
if ($bad) { $bad; Write-Host 'editor-only type annotation outside addons/ (breaks exported builds)'; Fail 'editor-type gate' }

Announce 'Import'
# Godot's --import exit code is unreliable on the pass right after new files appear
# (leak-at-exit noise) — judge by output instead.
$imp = & $GODOT --headless --path . --import 2>&1 | Out-String
$impErrors = ($imp -split "`n") | Select-String -Pattern 'SCRIPT ERROR|Failed to load|Compile Error'
if ($impErrors) { $impErrors; Fail 'import' }

Announce 'Unit tests (gdUnit4)'
$env:GODOT_BIN = $GODOT
& .\addons\gdUnit4\runtest.cmd -a tests
if ($LASTEXITCODE -ne 0) { Fail 'unit tests' }

Announce 'Stale-bake check'
# check_bakes.gd quit()s 0 when every bake is fresh, but Godot's leak-at-exit can still
# hand back a nonzero PROCESS code on an otherwise clean run (the same unreliability the
# import step above works around) — so judge by output: a stale/missing/error line is the
# only real failure.
$bakes = & $GODOT --headless --path . res://tools/check_bakes.tscn 2>&1 | Out-String
Write-Host $bakes
$staleBakes = ($bakes -split "`n") | Select-String -Pattern '\[check-bakes\].*: (stale|missing|error)'
if ($staleBakes) { Fail 'stale-bake check (run: & $GODOT --headless --path . res://tools/bake_levels.tscn)' }

Announce 'Headless smoke'
$smoke = & $GODOT --headless --path . --quit-after 120 2>&1 | Out-String
$errors = ($smoke -split "`n") | Select-String -Pattern 'SCRIPT ERROR|ERROR:' |
    Where-Object { $_ -notmatch 'still in use at exit|leaked at exit|Pages in use exist at exit' }
if ($LASTEXITCODE -ne 0 -or $errors) { $errors; Fail 'headless smoke' }

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
