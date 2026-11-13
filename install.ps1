<#
.SYNOPSIS
  Installs Claude Launcher: a "Claude" shortcut that opens Claude Code in Windows Terminal with Claude's own
  taskbar icon, an orange loading animation and no trust prompt.

.EXAMPLE
  ./install.ps1
  ./install.ps1 -Folder D:\code -ClaudeArgs "agents --permission-mode plan"
  ./install.ps1 -Folder D:\code        # re-run any time to change a setting; the rest are kept

.PARAMETER Folder
  Folder Claude opens in. Default: your user folder (or the value from a previous install).
.PARAMETER ClaudeArgs
  Arguments for claude.exe. Default: "agents" (agent view), or the value from a previous install.
.PARAMETER ShortcutName
  Name of the Desktop / Start menu shortcuts. Default: "Claude".
.PARAMETER InstallDir
  Where the launcher files go. Default: %USERPROFILE%\.claude\launcher.
.PARAMETER NoDesktopShortcut
  Only create the Start menu shortcut.
#>
param(
    [string]$Folder,
    [string]$ClaudeArgs,
    [string]$ShortcutName = 'Claude',
    [string]$InstallDir = (Join-Path $env:USERPROFILE '.claude\launcher'),
    [switch]$NoDesktopShortcut
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'src\common.ps1')

# ---- Requirements ----
$wt = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\wt.exe'
if (-not (Test-Path $wt)) { throw 'Windows Terminal (wt.exe) not found. Install it from the Microsoft Store.' }
$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwsh) { throw 'PowerShell 7 (pwsh.exe) not found. Install it: winget install Microsoft.PowerShell' }
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { throw "C# compiler not found at $csc (it ships with Windows' .NET Framework 4)." }
$claudeExe = Join-Path $env:USERPROFILE '.local\bin\claude.exe'
if (-not (Test-Path $claudeExe)) {
    Write-Warning "claude.exe not found at $claudeExe. Install Claude Code first, or the launcher will look for 'claude' on PATH."
}

# ---- Files ----
New-Item -ItemType Directory -Force $InstallDir | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'src\claude-launch.ps1') $InstallDir -Force

# Settings: keep what a previous install wrote, override with whatever was passed now.
$settingsFile = Join-Path $InstallDir 'launcher.json'
$settings = [ordered]@{ folder = '%USERPROFILE%'; claudeArgs = 'agents' }
if (Test-Path $settingsFile) {
    $old = Get-Content -Raw -Encoding utf8 $settingsFile | ConvertFrom-Json -AsHashtable
    foreach ($k in @($settings.Keys)) { if ($old[$k]) { $settings[$k] = $old[$k] } }
}
if ($Folder) {
    $resolved = (Resolve-Path $Folder -ErrorAction Stop).Path
    if (-not (Test-Path -PathType Container $resolved)) { throw "Folder '$Folder' is not a directory." }
    $settings.folder = $resolved
}
if ($ClaudeArgs) { $settings.claudeArgs = $ClaudeArgs }
[IO.File]::WriteAllText($settingsFile, ($settings | ConvertTo-Json) + "`n", [Text.UTF8Encoding]::new($false))

# Launcher exe (built locally; nothing is downloaded).
$exe = Join-Path $InstallDir 'ClaudeLauncher.exe'
& $csc -nologo -target:winexe -platform:x64 "-out:$exe" (Join-Path $PSScriptRoot 'src\ClaudeLauncher.cs')
if ($LASTEXITCODE -ne 0) { throw 'Building ClaudeLauncher.exe failed (see the errors above).' }

# ---- Windows Terminal profile "Claude" (a fragment, so your settings.json is never edited) ----
$fragmentDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\ClaudeLauncher'
New-Item -ItemType Directory -Force $fragmentDir | Out-Null
$profile_ = [ordered]@{
    name              = 'Claude'
    commandline       = "`"$pwsh`" -NoLogo -NoProfile -NoExit -File `"$(Join-Path $InstallDir 'claude-launch.ps1')`""
    startingDirectory = '%USERPROFILE%'
    icon              = $(if (Test-Path $claudeExe) { $claudeExe } else { $exe })
    elevate           = $false
    hidden            = $false
}
$fragment = @{ profiles = @($profile_) } | ConvertTo-Json -Depth 5
[IO.File]::WriteAllText((Join-Path $fragmentDir 'claude.json'), $fragment + "`n", [Text.UTF8Encoding]::new($false))

# ---- Shortcuts ----
$iconLocation = "$(if (Test-Path $claudeExe) { $claudeExe } else { $exe }),0"
$places = @(Join-Path ([Environment]::GetFolderPath('Programs')) "$ShortcutName.lnk")
if (-not $NoDesktopShortcut) { $places += Join-Path ([Environment]::GetFolderPath('Desktop')) "$ShortcutName.lnk" }
foreach ($lnk in $places) {
    New-LauncherShortcut -Path $lnk -Target $exe -Icon $iconLocation
    Write-Host "Shortcut: $lnk"
}
# Taskbar pins of this launcher (e.g. from an older install) get the current taskbar ID too.
foreach ($pin in Get-LauncherPins $exe) { Set-ShortcutAumid $pin.FullName $LauncherAumid }

Write-Host ''
Write-Host "Installed to $InstallDir" -ForegroundColor Green
Write-Host "Opens in:   $($settings.folder)"
Write-Host "Runs:       claude $($settings.claudeArgs)"
Write-Host "Settings:   $settingsFile (edit it, or re-run install.ps1 with -Folder / -ClaudeArgs)"
Write-Host "Pin it: open '$ShortcutName' from Start, right-click its taskbar button, Pin to taskbar."
