#Requires -Version 7
<#
.SYNOPSIS
  Removes Claude Launcher: its shortcuts (Desktop, Start menu, taskbar pins), the Windows Terminal profile and the
  installed files. Claude Code itself and your Claude settings are not touched.
.PARAMETER InstallDir
  Where it was installed. Default: read from the Windows Terminal profile, else %USERPROFILE%\.claude\launcher.
.PARAMETER KeepSettings
  Keep launcher.json (folder / arguments) for a later reinstall.
#>
param(
    [string]$InstallDir,
    [switch]$KeepSettings
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'src\common.ps1')

$fragmentDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\ClaudeLauncher'
$fragmentFile = Join-Path $fragmentDir 'claude.json'

# The profile's command line names the installed claude-launch.ps1, so a custom -InstallDir is found without asking.
if (-not $InstallDir -and (Test-Path $fragmentFile)) {
    try {
        $cmd = (Get-Content -Raw $fragmentFile | ConvertFrom-Json).profiles[0].commandline
        if ($cmd -match '-File "([^"]+)\\claude-launch\.ps1"') { $InstallDir = $Matches[1] }
    }
    catch {}
}
if (-not $InstallDir) { $InstallDir = Join-Path $env:USERPROFILE '.claude\launcher' }
Write-Host "Install folder: $InstallDir"

$exe = Join-Path $InstallDir 'ClaudeLauncher.exe'
$failed = 0
function Remove-Quietly([string]$Path, [string]$Label) {
    try { Remove-Item -LiteralPath $Path -Recurse -Force; Write-Host "Removed $Label" }
    catch { Write-Warning "Couldn't remove $Label ($($_.Exception.Message))"; $script:failed++ }
}

# Only shortcuts that point at this launcher are removed.
$dirs = @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'))
$pins = @(Get-LauncherPins $exe)
foreach ($lnk in @($dirs | ForEach-Object { Get-LauncherShortcuts $_ $exe }) + $pins) { Remove-Quietly $lnk.FullName $lnk.FullName }

if (Test-Path $fragmentDir) { Remove-Quietly $fragmentDir 'the Windows Terminal profile' }

$files = @('ClaudeLauncher.exe', 'claude-launch.ps1', 'launcher-lib.ps1', 'claude.ico', 'ClaudeLauncher.log', 'spinner.log')
if (-not $KeepSettings) { $files += 'launcher.json' }
foreach ($f in $files) {
    $p = Join-Path $InstallDir $f
    if (Test-Path $p) { Remove-Quietly $p $p }
}
if ((Test-Path $InstallDir) -and -not (Get-ChildItem $InstallDir -Force)) { Remove-Quietly $InstallDir $InstallDir }
elseif (Test-Path $InstallDir) { Write-Host "Left $InstallDir in place: it holds files the launcher didn't create." }

Write-Host ''
if ($pins.Count) { Write-Host 'If an empty taskbar button stays behind, unpin it or restart Explorer.' }
Write-Host 'The folder trust entry in ~/.claude.json is kept (Claude Code uses it too).'
if ($failed) { Write-Host "Claude Launcher uninstalled, but $failed item(s) couldn't be removed (see above)." -ForegroundColor Yellow }
else { Write-Host 'Claude Launcher uninstalled.' -ForegroundColor Green }
