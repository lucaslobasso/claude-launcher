<#
.SYNOPSIS
  Removes Claude Launcher: its shortcuts (Desktop, Start menu, taskbar pins), the Windows Terminal "Claude" profile
  and the installed files. Claude Code itself and your Claude settings are not touched.
.PARAMETER InstallDir
  Where it was installed. Default: %USERPROFILE%\.claude\launcher.
.PARAMETER KeepSettings
  Keep launcher.json (folder / arguments) for a later reinstall.
#>
param(
    [string]$InstallDir = (Join-Path $env:USERPROFILE '.claude\launcher'),
    [switch]$KeepSettings
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'src\common.ps1')

$exe = Join-Path $InstallDir 'ClaudeLauncher.exe'

# Only shortcuts that point at this launcher are removed.
$dirs = @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'))
foreach ($lnk in @($dirs | ForEach-Object { Get-LauncherShortcuts $_ $exe }) + @(Get-LauncherPins $exe)) {
    Remove-Item $lnk.FullName
    Write-Host "Removed $($lnk.FullName)"
}

$fragmentDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\ClaudeLauncher'
if (Test-Path $fragmentDir) { Remove-Item -Recurse $fragmentDir; Write-Host 'Removed the Windows Terminal "Claude" profile' }

$files = @('ClaudeLauncher.exe', 'claude-launch.ps1', 'ClaudeLauncher.log', 'spinner.log')
if (-not $KeepSettings) { $files += 'launcher.json' }
foreach ($f in $files) {
    $p = Join-Path $InstallDir $f
    if (Test-Path $p) { Remove-Item $p; Write-Host "Removed $p" }
}
if ((Test-Path $InstallDir) -and -not (Get-ChildItem $InstallDir -Force)) { Remove-Item $InstallDir }

Write-Host 'Claude Launcher uninstalled.' -ForegroundColor Green
