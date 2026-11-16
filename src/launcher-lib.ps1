# launcher-lib.ps1: small helpers shared by claude-launch.ps1 and install.ps1 (and tested in tests/).
# Installed next to claude-launch.ps1.

$LauncherVersion = '1.2.0'

# The Windows Terminal profile's fixed GUID. Without one, Terminal derives it from the profile name, so renaming
# (-ShortcutName) made a new profile: per-profile overrides in settings.json stopped applying and anything that
# still asked for the old name got Terminal's default profile instead. Keep in sync with src/ClaudeLauncher.cs.
$LauncherProfileGuid = '{4d0d2583-2c71-5809-98e7-a26fa8ae2100}'

$LauncherDefaults = [ordered]@{
    folder        = '%USERPROFILE%'
    claudeArgs    = 'agents'
    keepShellOpen = $false
}

# Splits an argument line the way you'd type it: spaces separate, "double" or 'single' quotes group,
# backslashes are kept as they are (Windows paths).
#   Split-ClaudeArgs 'agents --append-system-prompt "be brief"'  ->  agents, --append-system-prompt, be brief
function Split-ClaudeArgs([string]$Line) {
    if ([string]::IsNullOrWhiteSpace($Line)) { return }
    $out = [Collections.Generic.List[string]]::new()
    foreach ($m in [regex]::Matches($Line, '"([^"]*)"|''([^'']*)''|(\S+)')) {
        $out.Add($(if ($m.Groups[1].Success) { $m.Groups[1].Value } elseif ($m.Groups[2].Success) { $m.Groups[2].Value } else { $m.Groups[3].Value }))
    }
    return $out.ToArray()  # unrolled: callers collect it with @(...)
}

# launcher.json as an ordered hashtable over the defaults. A key that is present wins, even when it is empty
# (claudeArgs "" means plain `claude`). A file that doesn't parse gives the defaults and a warning.
function Read-LauncherSettings([string]$Path) {
    $settings = [ordered]@{}
    foreach ($k in $LauncherDefaults.Keys) { $settings[$k] = $LauncherDefaults[$k] }
    if (-not (Test-Path $Path)) { return $settings }
    try {
        $raw = Get-Content -Raw -Encoding utf8 $Path
        $file = if ([string]::IsNullOrWhiteSpace($raw)) { @{} } else { $raw | ConvertFrom-Json -AsHashtable }
    }
    catch {
        Write-Warning "Couldn't read $Path ($($_.Exception.Message)); using the defaults."
        return $settings
    }
    foreach ($k in @($LauncherDefaults.Keys)) {
        if ($file.ContainsKey($k) -and $null -ne $file[$k]) { $settings[$k] = $file[$k] }
    }
    return $settings
}

function Write-LauncherSettings([string]$Path, $Settings) {
    [IO.File]::WriteAllText($Path, ($Settings | ConvertTo-Json) + "`n", [Text.UTF8Encoding]::new($false))
}

# First existing path, else the first hit on PATH for one of the names, else $null.
function Find-Tool([string[]]$Paths, [string[]]$Names) {
    foreach ($p in $Paths) { if ($p -and (Test-Path -PathType Leaf $p)) { return $p } }
    foreach ($n in $Names) {
        $c = Get-Command $n -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($c) { return $c.Source }
    }
    return $null
}

# Fixes up a parsed Windows Terminal settings.json (hashtable) for the launcher profile; returns $true if it changed.
# Entries in the user's profiles.list outrank the fragment, so Terminal's own copy of our profile can override it:
#  - "profiles.defaults.elevate": true (every tab as admin) beats the fragment's "elevate": false. An elevated
#    window can't be relabelled by the non-admin ClaudeLauncher.exe (Terminal's icon, and Claude runs as admin),
#    so our entry gets "elevate": false.
#  - A "name" left from an earlier -ShortcutName beats the fragment's name; it's updated.
#  - Entries Terminal kept for the profile under an older GUID are dropped (they'd show as dead profiles).
function Update-TerminalProfileEntries($Settings, [string]$Guid, [string]$Name) {
    $changed = $false
    $profiles = $Settings['profiles']
    if ($profiles -isnot [Collections.IDictionary]) { return $false }  # the old array form: nothing of ours to fix
    $list = @($profiles['list'] | Where-Object { $_ -is [Collections.IDictionary] })
    $keep = @($list | Where-Object { $_['source'] -ne 'ClaudeLauncher' -or $_['guid'] -eq $Guid })
    if ($keep.Count -ne $list.Count) { $changed = $true }
    $mine = $keep | Where-Object { $_['guid'] -eq $Guid } | Select-Object -First 1
    $defaults = $profiles['defaults']
    $elevatedByDefault = $defaults -is [Collections.IDictionary] -and $defaults['elevate'] -eq $true
    if (-not $mine -and $elevatedByDefault) {
        $mine = [ordered]@{ guid = $Guid; source = 'ClaudeLauncher' }
        $keep += $mine
        $changed = $true
    }
    if ($mine) {
        if ($elevatedByDefault -and $mine['elevate'] -ne $false) { $mine['elevate'] = $false; $changed = $true }
        if ($mine.Contains('name') -and $mine['name'] -ne $Name) { $mine['name'] = $Name; $changed = $true }
    }
    if ($changed) { $profiles['list'] = $keep }
    return $changed
}

# settings.json of each installed Windows Terminal (Store, Preview, unpackaged).
function Get-TerminalSettingsFiles {
    @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    ) | Where-Object { Test-Path -PathType Leaf $_ }
}

function Find-Claude {
    Find-Tool @((Join-Path $env:USERPROFILE '.local\bin\claude.exe')) @('claude.exe', 'claude')
}
