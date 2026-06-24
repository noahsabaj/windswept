#requires -Version 5.1
<#
.SYNOPSIS
    Link the Windswept dev repos into the local Garry's Mod install (directory junctions).

.DESCRIPTION
    Recreates the gamemode/addon junctions GMod needs so "Windswept Colony RP" shows up in
    the gamemode menu. Useful after a drive wipe or fresh checkout destroys them.

    Auto-detects the GMod install (the Steam library whose steamapps holds appmanifest_4000.acf)
    and the sibling repos relative to this script. Junctions need no admin. This script only
    CREATES missing junctions -- it never deletes, so it cannot touch your repos.

    After running, FULLY restart Garry's Mod: it compiles/caches gamemode Lua per session, so a
    gamemode switch or lua_refresh is not enough.

.PARAMETER GmodPath
    The GMod 'garrysmod' folder, e.g. 'D:\SteamLibrary\steamapps\common\GarrysMod\garrysmod'.
    Auto-detected if omitted.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\link-gmod.ps1
#>
param([string]$GmodPath)

$ErrorActionPreference = 'Stop'

# This script lives in <framework>/scripts/, so the repos are siblings of <framework>.
$framework = Split-Path -Parent $PSScriptRoot
$parent    = Split-Path -Parent $framework

function Find-GarrysmodDir {
    $roots = @("${env:ProgramFiles(x86)}\Steam", "$env:ProgramFiles\Steam", "C:\Steam") |
        Where-Object { $_ } | Select-Object -Unique
    $libs = [System.Collections.Generic.List[string]]::new()
    foreach ($r in $roots) {
        $libs.Add($r)
        $vdf = Join-Path $r 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"') |
                ForEach-Object { $libs.Add(($_.Groups[1].Value -replace '\\\\', '\')) }
        }
    }
    foreach ($lib in ($libs | Select-Object -Unique)) {
        if (Test-Path (Join-Path $lib 'steamapps\appmanifest_4000.acf')) {
            return (Join-Path $lib 'steamapps\common\GarrysMod\garrysmod')
        }
    }
    return $null
}

if (-not $GmodPath) { $GmodPath = Find-GarrysmodDir }
if (-not $GmodPath -or -not (Test-Path $GmodPath)) {
    throw "Could not find the GMod install. Re-run with -GmodPath '<...>\GarrysMod\garrysmod'."
}
Write-Host "GMod:   $GmodPath"
Write-Host "Repos:  $parent`n"

$links = @(
    @{ Link = 'gamemodes\windswept';   Target = $framework },
    @{ Link = 'gamemodes\windsweptrp'; Target = (Join-Path $parent 'windswept-colony') },
    @{ Link = 'addons\windswept-fire'; Target = (Join-Path $parent 'windswept-fire') }
)

$addons = Join-Path $GmodPath 'addons'
if (-not (Test-Path $addons)) { New-Item -ItemType Directory $addons | Out-Null }

foreach ($l in $links) {
    $link = Join-Path $GmodPath $l.Link
    if (-not (Test-Path $l.Target)) { Write-Warning "skip: repo not found at $($l.Target)"; continue }
    if (Test-Path $link) {
        $isJunction = [bool]((Get-Item $link -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)
        if ($isJunction) { Write-Host "ok:     $($l.Link) (already linked)" }
        else { Write-Warning "exists as a real folder, leaving alone: $link" }
        continue
    }
    New-Item -ItemType Junction -Path $link -Target $l.Target | Out-Null
    Write-Host "linked: $($l.Link)  ->  $($l.Target)"
}

Write-Host "`nDone. Fully restart Garry's Mod to load the gamemode." -ForegroundColor Green
