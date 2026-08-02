# Shared Godot-binary resolution for the PowerShell tooling.
# Dot-source it, then call Resolve-GodotBin.
#
# Order: $env:GODOT_BIN -> `git config carlito.godotbin` -> `godot` on PATH -> hard error.
# The git-config fallback is the one that works from hooks: git runs them with a bare
# environment, so a $GODOT_BIN set in your shell is NOT visible there.
# Use the *console* build on Windows (Godot_v<ver>-stable_win64_console.exe) — the plain
# exe swallows print/push_error, so headless runs come back silent.

function Resolve-GodotBin {
    $bin = $env:GODOT_BIN
    if (-not $bin) { $bin = (git config --get carlito.godotbin) }
    if ($bin) {
        if (Test-Path -LiteralPath $bin) { return $bin }
        Write-Host "Configured Godot binary does not exist: $bin" -ForegroundColor Red
        exit 1
    }
    $onPath = Get-Command godot -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    Write-Host 'Godot binary not found. Set it once for this clone with:' -ForegroundColor Red
    Write-Host "  git config carlito.godotbin '<path>\Godot_v4.7.1-stable_win64_console.exe'" -ForegroundColor Red
    Write-Host '(or set $env:GODOT_BIN, or put `godot` on PATH)' -ForegroundColor Red
    exit 1
}
