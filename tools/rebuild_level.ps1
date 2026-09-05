# Replay a level's generator chain from its committed manifest (src/levels/**/<id>_gen.json,
# the one copy of the chain). Not a CI gate, not part of the bake pipeline: a replay takes
# minutes and rewrites committed content. Run on a branch, read the diff, commit what you
# meant to change.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Level,
    # Print the chain and stop. Nothing is run, nothing is snapshotted.
    [switch]$DryRun,
    # Run a manifest marked "replayable": false anyway. It will destroy hand-authored content.
    [switch]$Force,
    # Skip the tmp/<level>_before/ snapshot (and with it the diff report).
    [switch]$NoSnapshot
)

$ErrorActionPreference = 'Continue'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo
. (Join-Path $PSScriptRoot 'godot_bin.ps1')

function Fail($msg) { Write-Host "REBUILD FAILED: $msg" -ForegroundColor Red; exit 1 }
function Announce($msg) { Write-Host "`n== $msg" -ForegroundColor Cyan }

# --- manifest ---------------------------------------------------------------------------
$found = @(Get-ChildItem -Path (Join-Path $repo 'src/levels') -Recurse -File -Filter "${Level}_gen.json")
if ($found.Count -eq 0) { Fail "no manifest src/levels/**/${Level}_gen.json" }
if ($found.Count -gt 1) { Fail "more than one ${Level}_gen.json under src/levels/" }
$manifestPath = $found[0].FullName
try { $m = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json }
catch { Fail "$manifestPath is not valid JSON: $_" }

$sceneRel = ([string]$m.scene) -replace '^res://', ''      # src/levels/island/level_1/level_1.tscn
$levelRel = Split-Path -Parent $sceneRel

Write-Host "Manifest: $manifestPath" -ForegroundColor Cyan
Write-Host "Scene:    $($m.scene)"
foreach ($line in $m.notes) { Write-Host "  note: $line" -ForegroundColor DarkGray }

Write-Host "`nChain:"
$i = 0
foreach ($step in $m.steps) {
    $i++
    switch ($step.kind) {
        'manual' { Write-Host ("  {0}. [manual, skipped] {1}" -f $i, $step.what) -ForegroundColor Yellow }
        'import' { Write-Host ("  {0}. --import" -f $i) }
        'bake'   { Write-Host ("  {0}. bake {1}" -f $i, $sceneRel) }
        'scene'  { Write-Host ("  {0}. {1} {2}" -f $i, $step.path, ($step.args -join ' ')) }
        'script' { Write-Host ("  {0}. --script {1}" -f $i, $step.path) }
        default  { Fail "unknown step kind '$($step.kind)' in $manifestPath" }
    }
    if ($step.why) { Write-Host "       $($step.why)" -ForegroundColor DarkGray }
}

if (-not $m.replayable) {
    Write-Host "`nThis manifest is marked NOT replayable:" -ForegroundColor Red
    Write-Host "  $($m.blocked)" -ForegroundColor Red
    if (-not $Force) { Write-Host 'Refusing. Pass -Force if you mean it.' -ForegroundColor Red; exit 1 }
    Write-Host '-Force given - proceeding anyway.' -ForegroundColor Yellow
}

if ($DryRun) { Write-Host "`n-DryRun: nothing was run." -ForegroundColor Green; exit 0 }

$GODOT = Resolve-GodotBin

# --- snapshot ----------------------------------------------------------------------------
# Backups go under tmp/, which carries a committed .gdignore, or Godot imports the copies and the generator sculpts the backup instead.
$snapDir = Join-Path $repo "tmp/${Level}_before"
$tracked = @($sceneRel) + @($m.sources | ForEach-Object { "$levelRel/$_" })
if (-not $NoSnapshot) {
    $gdignore = Join-Path $repo 'tmp/.gdignore'
    if (-not (Test-Path -LiteralPath $gdignore)) {
        New-Item -ItemType Directory -Force (Join-Path $repo 'tmp') | Out-Null
        New-Item -ItemType File $gdignore | Out-Null
        Write-Host 'wrote tmp/.gdignore (uid-hijack guard)' -ForegroundColor Yellow
    }
    if (Test-Path -LiteralPath $snapDir) { Remove-Item -Recurse -Force -LiteralPath $snapDir }
    New-Item -ItemType Directory -Force $snapDir | Out-Null
    foreach ($rel in $tracked) {
        $src = Join-Path $repo $rel
        if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination $snapDir }
        else { Write-Host "  snapshot: $rel does not exist yet" -ForegroundColor Yellow }
    }
    Write-Host "`nSnapshot: $snapDir ($($tracked.Count) files)" -ForegroundColor Cyan
}

# --- run ----------------------------------------------------------------------------------
# Judged by output, not exit code: --import and game-mode tool scenes hand back unreliable process codes (leak-at-exit noise).
function Invoke-Godot($label, $godotArgs) {
    Announce "$label"
    $out = & $GODOT @godotArgs 2>&1 | Out-String
    Write-Host $out
    $bad = ($out -split "`n") | Select-String -Pattern 'SCRIPT ERROR|Failed to load|Compile Error|ERROR:' |
        Where-Object { $_ -notmatch 'still in use at exit|leaked at exit|Pages in use exist at exit' }
    if ($bad) { $bad; Fail $label }
}

$i = 0
foreach ($step in $m.steps) {
    $i++
    switch ($step.kind) {
        'manual' { Announce "step $i - manual, skipped: $($step.what)" }
        'import' { Invoke-Godot "step $i - import" @('--headless', '--path', '.', '--import') }
        'bake'   { Invoke-Godot "step $i - bake $sceneRel" @('--headless', '--path', '.', 'res://tools/bake_levels.tscn', '--', $sceneRel) }
        'script' { Invoke-Godot "step $i - --script $($step.path)" @('--headless', '--path', '.', '--script', $step.path) }
        'scene'  {
            $a = @('--headless', '--path', '.', [string]$step.path)
            if ($step.args) { $a += '--'; $a += ($step.args | ForEach-Object { [string]$_ }) }
            Invoke-Godot "step $i - $($step.path) $($step.args -join ' ')" $a
        }
    }
}

# --- diff report ---------------------------------------------------------------------------
# Does replaying land on the bytes already committed? A byte hash alone would cry wolf on a
# non-idempotent sculpt step, so a changed PNG is classified via tools/png_drift.gd against
# the manifest's optional "sculpt_drift" tolerances; no entry means zero tolerance.

# Returns $null when the two PNGs cannot be compared (size/format change - that is real drift).
function Get-PngDrift($beforePath, $afterPath) {
    $out = & $GODOT '--headless' '--path' '.' '--script' 'res://tools/png_drift.gd' '--' $beforePath $afterPath 2>&1 | Out-String
    $mm = [regex]::Match($out, 'DRIFT px=(\d+) max=(\d+) total=(\d+)')
    if (-not $mm.Success) { return $null }
    return @{ px = [int]$mm.Groups[1].Value; max = [int]$mm.Groups[2].Value; total = [int]$mm.Groups[3].Value }
}
if (-not $NoSnapshot) {
    Announce 'Diff against the pre-replay snapshot'
    $changed = 0        # real drift: judge it
    $tolerated = 0      # moved, but inside the manifest's declared sculpt tolerance
    $tol = $m.sculpt_drift
    foreach ($rel in $tracked) {
        $name = Split-Path -Leaf $rel
        $before = Join-Path $snapDir $name
        $after = Join-Path $repo $rel
        if (-not (Test-Path -LiteralPath $before)) { Write-Host ("  {0,-40} NEW" -f $name) -ForegroundColor Yellow; $changed++; continue }
        if (-not (Test-Path -LiteralPath $after)) { Write-Host ("  {0,-40} GONE" -f $name) -ForegroundColor Red; $changed++; continue }
        if ((Get-FileHash -LiteralPath $before).Hash -eq (Get-FileHash -LiteralPath $after).Hash) {
            Write-Host ("  {0,-40} identical" -f $name) -ForegroundColor Green
        } elseif ($name -notlike '*.png') {
            Write-Host ("  {0,-40} CHANGED" -f $name) -ForegroundColor Yellow
            $changed++
        } else {
            $d = Get-PngDrift $before $after
            if ($null -eq $d) {
                Write-Host ("  {0,-40} CHANGED (not comparable - size or format moved)" -f $name) -ForegroundColor Red
                $changed++
                continue
            }
            $allow = if ($tol) { $tol.$name } else { $null }
            $detail = "{0} px moved of {1}, max {2} step(s)" -f $d.px, $d.total, $d.max
            if ($allow -and $d.px -le [int]$allow.max_px -and $d.max -le [int]$allow.max_step) {
                Write-Host ("  {0,-40} drift within tolerance - {1}" -f $name, $detail) -ForegroundColor DarkGray
                $tolerated++
            } else {
                $limit = if ($allow) { " (tolerance: {0} px / {1} step(s))" -f $allow.max_px, $allow.max_step } else { ' (no tolerance declared)' }
                Write-Host ("  {0,-40} CHANGED - {1}{2}" -f $name, $detail, $limit) -ForegroundColor Yellow
                $changed++
            }
        }
    }
    if ($changed -eq 0 -and $tolerated -eq 0) {
        Write-Host "`nThe chain is a fixed point: replaying it reproduced every committed byte." -ForegroundColor Green
    } elseif ($changed -eq 0) {
        Write-Host "`n$tolerated file(s) moved, all inside the tolerance this manifest declares." -ForegroundColor Green
        Write-Host 'Keeping or discarding those bytes is equally correct - git checkout is the cheaper choice.'
    } else {
        Write-Host "`n$changed file(s) moved beyond tolerance. Restore with: git checkout -- $levelRel" -ForegroundColor Yellow
        Write-Host 'A moved .tscn can be harmless (PackedScene.pack is not byte-deterministic).'
        Write-Host 'A PNG past its declared tolerance is real drift - read the tool acceptance report before keeping it.'
    }
}

Write-Host "`nREBUILD DONE" -ForegroundColor Green
