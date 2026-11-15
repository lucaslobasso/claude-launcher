#Requires -Version 7
<#
.SYNOPSIS
  Installs Claude Launcher: a shortcut that opens Claude Code in Windows Terminal with its own taskbar icon,
  an orange loading animation and no trust prompt.

.EXAMPLE
  pwsh -File install.ps1
  pwsh -File install.ps1 -Folder D:\code -ClaudeArgs "agents --permission-mode plan"
  pwsh -File install.ps1 -ClaudeArgs ""       # a plain `claude` session instead of the agent view
  pwsh -File install.ps1 -Update              # git pull, then reinstall with the same settings

.PARAMETER Folder
  Folder Claude opens in (and is pre-trusted). Default: your user folder, or the value from a previous install.
.PARAMETER ClaudeArgs
  Arguments for claude. Default: "agents" (agent view), or the value from a previous install. "" = plain claude.
.PARAMETER KeepShellOpen
  When Claude exits, stay at a PowerShell prompt instead of closing the tab. -KeepShellOpen:$false turns it off.
.PARAMETER ShortcutName
  Name of the shortcuts, the Windows Terminal profile and the taskbar button. Default: "Claude".
.PARAMETER InstallDir
  Where the launcher files go. Default: %USERPROFILE%\.claude\launcher.
.PARAMETER NoDesktopShortcut
  Only create the Start menu shortcut (an existing Desktop one is removed).
.PARAMETER Update
  Pull the latest version first (git checkout only), then install.
#>
param(
    [string]$Folder,
    [AllowEmptyString()][string]$ClaudeArgs,
    [switch]$KeepShellOpen,
    [string]$ShortcutName = 'Claude',
    [string]$InstallDir = (Join-Path $env:USERPROFILE '.claude\launcher'),
    [switch]$NoDesktopShortcut,
    [switch]$Update
)

$ErrorActionPreference = 'Stop'

if ($Update) {
    if (-not (Test-Path (Join-Path $PSScriptRoot '.git'))) { throw '-Update needs a git checkout. Download the latest release instead (see README).' }
    git -C $PSScriptRoot pull --ff-only
    if ($LASTEXITCODE -ne 0) { throw 'git pull failed (see above).' }
    $again = @{} + $PSBoundParameters
    $again.Remove('Update')
    & (Join-Path $PSScriptRoot 'install.ps1') @again
    return
}

# Files from a downloaded ZIP carry the "from the internet" mark, which a RemoteSigned policy refuses to run.
Get-ChildItem $PSScriptRoot -Recurse -File -Include *.ps1, *.cs | Unblock-File -ErrorAction SilentlyContinue

. (Join-Path $PSScriptRoot 'src\common.ps1')
. (Join-Path $PSScriptRoot 'src\launcher-lib.ps1')

if ($ShortcutName -match '[\\/:*?"<>|]') { throw "-ShortcutName can't contain any of \ / : * ? `" < > |" }

# ---- Requirements ----
$wt = Find-Tool @((Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\wt.exe')) @('wt.exe')
if (-not $wt) { throw 'Windows Terminal (wt.exe) not found. Install it from the Microsoft Store (or: winget install Microsoft.WindowsTerminal).' }
$pwsh = (Get-Process -Id $PID).Path
$csc = Find-Tool @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')) @()
if (-not $csc) { throw "The C# compiler (csc.exe) that ships with Windows' .NET Framework 4 was not found under $env:WINDIR\Microsoft.NET." }
$claude = Find-Claude
if (-not $claude) { Write-Warning 'claude was not found (in %USERPROFILE%\.local\bin or on PATH). Install Claude Code; the launcher looks again each time it starts.' }

# ---- Files ----
New-Item -ItemType Directory -Force $InstallDir | Out-Null
foreach ($f in 'claude-launch.ps1', 'launcher-lib.ps1') { Copy-Item (Join-Path $PSScriptRoot "src\$f") $InstallDir -Force }

# Settings: keep what a previous install wrote, override with whatever was passed now.
$settingsFile = Join-Path $InstallDir 'launcher.json'
$settings = Read-LauncherSettings $settingsFile
if ($PSBoundParameters.ContainsKey('Folder')) {
    $resolved = (Resolve-Path $Folder -ErrorAction Stop).Path
    if (-not (Test-Path -PathType Container $resolved)) { throw "Folder '$Folder' is not a directory." }
    $settings.folder = $resolved
}
if ($PSBoundParameters.ContainsKey('ClaudeArgs')) { $settings.claudeArgs = $ClaudeArgs }
if ($PSBoundParameters.ContainsKey('KeepShellOpen')) { $settings.keepShellOpen = [bool]$KeepShellOpen }
Write-LauncherSettings $settingsFile $settings

# Launcher exe (built locally from src/ClaudeLauncher.cs; nothing is downloaded).
$exe = Join-Path $InstallDir 'ClaudeLauncher.exe'
& $csc -nologo -target:winexe -platform:anycpu "-win32icon:$(Join-Path $PSScriptRoot 'assets\claude-launcher.ico')" "-out:$exe" (Join-Path $PSScriptRoot 'src\ClaudeLauncher.cs')
if ($LASTEXITCODE -ne 0) { throw 'Building ClaudeLauncher.exe failed (see the errors above). Close any running Claude Launcher window and try again.' }

# ---- Windows Terminal profile (a fragment, with a fixed GUID so renaming it keeps it the same profile) ----
$icon = if ($claude -and $claude -like '*.exe') { $claude } else { $exe }
$fragmentDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\ClaudeLauncher'
New-Item -ItemType Directory -Force $fragmentDir | Out-Null
$profile_ = [ordered]@{
    guid              = $LauncherProfileGuid
    name              = $ShortcutName
    commandline       = "`"$pwsh`" -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $InstallDir 'claude-launch.ps1')`""
    startingDirectory = '%USERPROFILE%'
    icon              = $icon
    elevate           = $false
    hidden            = $false
}
$fragment = @{ profiles = @($profile_) } | ConvertTo-Json -Depth 5
[IO.File]::WriteAllText((Join-Path $fragmentDir 'claude.json'), $fragment + "`n", [Text.UTF8Encoding]::new($false))

# Terminal's settings.json is only touched when its own entry for the profile would override the fragment
# (e.g. "elevate": true for all profiles); see Update-TerminalProfileEntries. A backup is kept next to it.
foreach ($wtSettings in Get-TerminalSettingsFiles) {
    try {
        $wtJson = Get-Content -Raw -Encoding utf8 $wtSettings | ConvertFrom-Json -AsHashtable
        if (Update-TerminalProfileEntries $wtJson $LauncherProfileGuid $ShortcutName) {
            Copy-Item $wtSettings "$wtSettings.bak-launcher" -Force
            [IO.File]::WriteAllText($wtSettings, ($wtJson | ConvertTo-Json -Depth 64) + "`n", [Text.UTF8Encoding]::new($false))
            Write-Host "Updated the '$ShortcutName' profile in $wtSettings (backup: settings.json.bak-launcher)"
        }
    }
    catch { Write-Warning "Couldn't check $wtSettings ($($_.Exception.Message)). If Claude opens as admin, set `"elevate`": false on the '$ShortcutName' profile." }
}

# ---- Shortcuts ----
$places = @(Join-Path ([Environment]::GetFolderPath('Programs')) "$ShortcutName.lnk")
if (-not $NoDesktopShortcut) { $places += Join-Path ([Environment]::GetFolderPath('Desktop')) "$ShortcutName.lnk" }
# Shortcuts of this launcher under another name (a previous -ShortcutName) or a Desktop one with -NoDesktopShortcut.
foreach ($dir in [Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('Desktop')) {
    foreach ($old in Get-LauncherShortcuts $dir $exe) {
        if ($places -notcontains $old.FullName) { Remove-Item $old.FullName; Write-Host "Removed old shortcut $($old.FullName)" }
    }
}
foreach ($lnk in $places) {
    New-LauncherShortcut -Path $lnk -Target $exe -Arguments "`"$ShortcutName`"" -Icon "$icon,0"
    Write-Host "Shortcut: $lnk"
}
# Taskbar pins of this launcher (e.g. from an older install) get the current profile name and taskbar ID too.
$shell = New-Object -ComObject WScript.Shell
foreach ($pin in Get-LauncherPins $exe) {
    $l = $shell.CreateShortcut($pin.FullName)
    $l.Arguments = "`"$ShortcutName`""
    $l.IconLocation = "$icon,0"
    $l.Save()
    Set-ShortcutAumid $pin.FullName $LauncherAumid
}

Write-Host ''
Write-Host "Claude Launcher $LauncherVersion installed to $InstallDir" -ForegroundColor Green
Write-Host "Opens in:   $([Environment]::ExpandEnvironmentVariables([string]$settings.folder))"
Write-Host "Runs:       claude $($settings.claudeArgs)"
Write-Host "When Claude exits: $(if ($settings.keepShellOpen) { 'stay at a PowerShell prompt' } else { 'close the tab' })"
Write-Host "Settings:   $settingsFile (edit it any time, or re-run install.ps1 with -Folder / -ClaudeArgs / -KeepShellOpen)"
Write-Host "Pin it: open '$ShortcutName' from Start, right-click its taskbar button, Pin to taskbar."
