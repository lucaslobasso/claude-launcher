# launcher-lib.ps1: small helpers shared by claude-launch.ps1 and install.ps1 (and tested in tests/).
# Installed next to claude-launch.ps1.

$LauncherVersion = '1.1.0'

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

function Find-Claude {
    Find-Tool @((Join-Path $env:USERPROFILE '.local\bin\claude.exe')) @('claude.exe', 'claude')
}
