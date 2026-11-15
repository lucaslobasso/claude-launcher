#Requires -Version 7
# claude-launch.ps1: runs inside the Windows Terminal profile install.ps1 creates.
# Shows an orange loading animation, pre-accepts the folder trust prompt, then starts Claude Code.
#
# Settings live in launcher.json next to this script (written by install.ps1, safe to edit by hand):
#   { "folder": "%USERPROFILE%", "claudeArgs": "agents", "keepShellOpen": false }
#   folder         folder Claude opens in; "%USERPROFILE%"-style variables work
#   claudeArgs     arguments for claude ("" = a plain `claude` session); "double quotes" group words
#   keepShellOpen  true: when Claude exits, stay in a PowerShell prompt in that folder instead of closing the tab
# Parameters override the file for one run:
#   -Folder, -ClaudeArgs   as above
#   -Demo <s>              only show the loading animation for <s> seconds, don't start Claude (screenshots/testing)

param(
    [string]$Folder,
    [string]$ClaudeArgs,
    [double]$Demo = 0
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'launcher-lib.ps1')

function Stop-WithMessage([string]$Text) {
    [Console]::Write("`e[2J`e[H`e[?25h")
    Write-Host "Claude Launcher: $Text" -ForegroundColor Yellow
    Read-Host 'Press Enter to close'
    exit 1
}

$settings = Read-LauncherSettings (Join-Path $PSScriptRoot 'launcher.json')
if (-not $PSBoundParameters.ContainsKey('Folder')) { $Folder = [Environment]::ExpandEnvironmentVariables([string]$settings.folder) }
if (-not $PSBoundParameters.ContainsKey('ClaudeArgs')) { $ClaudeArgs = [string]$settings.claudeArgs }
if (-not $Folder -or -not (Test-Path -PathType Container $Folder)) {
    Write-Host "Claude Launcher: folder '$Folder' not found; opening in your user folder instead." -ForegroundColor Yellow
    $Folder = $env:USERPROFILE
}
Set-Location $Folder

# ---- Loading animation: orange "Starting Claude" with dots, centered, until Claude starts drawing ----
[Console]::OutputEncoding = [Text.Encoding]::UTF8
[Console]::Write("`e[?25l`e[2J`e[H")  # hide cursor, clear screen
$spinner = [hashtable]::Synchronized(@{ Run = $true })
$spinnerPs = [powershell]::Create().AddScript({
    param($state, $logPath, $maxMs)
    # Stops as soon as the cursor is no longer where the last frame left it (Claude has started drawing),
    # when told to, or after $maxMs.
    $frames = @('   ', '.  ', '.. ', '...')  # fixed width so the text stays centered
    $orange = "`e[38;2;217;119;87m"; $reset = "`e[0m"
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $i = 0; $expect = $null; $why = 'timeout'
    while ($clock.ElapsedMilliseconds -lt $maxMs) {
        if (-not $state.Run) { $why = 'stopped'; break }
        if ($expect -and ([Console]::CursorLeft -ne $expect[0] -or [Console]::CursorTop -ne $expect[1])) { $why = 'claude drew'; break }
        $text = "Starting Claude$($frames[([int][Math]::Floor($i / 2) + 2) % $frames.Count])"  # starts at 2 dots, steps every 200 ms
        $row = [Math]::Max(1, [int]([Console]::WindowHeight / 2))
        $col = [Math]::Max(1, [int](([Console]::WindowWidth - $text.Length) / 2) + 1)
        [Console]::Write("`e[$row;${col}H$orange$text$reset")
        $expect = @(($col - 1 + $text.Length), ($row - 1))
        $i++
        Start-Sleep -Milliseconds 100
    }
    try { Add-Content $logPath ("{0:yyyy-MM-dd HH:mm:ss.fff} spinner ended after {1} ms ({2})" -f (Get-Date), $clock.ElapsedMilliseconds, $why) } catch {}
}).AddArgument($spinner).AddArgument("$PSScriptRoot\spinner.log").AddArgument([Math]::Max(10000, $Demo * 1000 + 1000))
$spinnerJob = $spinnerPs.BeginInvoke()

if ($Demo -gt 0) {
    Start-Sleep -Milliseconds ($Demo * 1000)
    $spinner.Run = $false
    $null = $spinnerPs.EndInvoke($spinnerJob)
    [Console]::Write("`e[2J`e[H`e[?25h")
    return
}

# ---- Clean environment: if started from inside another Claude session, drop what it passes down ----
# (NO_COLOR=1 strips all color, CLAUDECODE/CLAUDE_CODE_* mark a child session). Vars you set in Windows are kept.
$userEnv = [Environment]::GetEnvironmentVariables('User')
$machineEnv = [Environment]::GetEnvironmentVariables('Machine')
Get-ChildItem env: |
    Where-Object { $_.Name -match '^(NO_COLOR|CLAUDECODE|CLAUDE_PID|CLAUDE_JOB_DIR|CLAUDE_CODE_.+)$' } |
    Where-Object { -not $userEnv.Contains($_.Name) -and -not $machineEnv.Contains($_.Name) } |
    ForEach-Object { Remove-Item "env:$($_.Name)" }

# ---- Pre-accept the trust prompt for the configured folder (Claude Code doesn't remember it for your user folder) ----
# Only written when the entry is missing; dates are kept as text so the rest of the file round-trips unchanged.
$config = Join-Path $env:USERPROFILE '.claude.json'
$projectKey = (Resolve-Path $Folder).Path.TrimEnd('\') -replace '\\', '/'
try {
    if (Test-Path $config) {
        $raw = Get-Content -Raw -Encoding utf8 $config
        $data = if ($PSVersionTable.PSVersion -ge [version]'7.5') { $raw | ConvertFrom-Json -AsHashtable -DateKind String } else { $raw | ConvertFrom-Json -AsHashtable }
        if ($null -eq $data['projects']) { $data['projects'] = [ordered]@{} }
        $proj = $data['projects'][$projectKey]
        if ($null -eq $proj -or $proj['hasTrustDialogAccepted'] -ne $true) {
            if ($null -eq $proj) { $proj = [ordered]@{}; $data['projects'][$projectKey] = $proj }
            $proj['hasTrustDialogAccepted'] = $true
            $tmp = "$config.launcher-tmp"
            [IO.File]::WriteAllText($tmp, ($data | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
            Move-Item -Force $tmp $config
        }
    }
}
catch {
    Write-Host "Claude Launcher: couldn't pre-trust the folder ($($_.Exception.Message)). You may see the trust prompt." -ForegroundColor Yellow
}

# ---- Start Claude; the animation keeps going until Claude starts drawing ----
$claude = Find-Claude
if (-not $claude) {
    $spinner.Run = $false
    Stop-WithMessage 'claude was not found (looked in %USERPROFILE%\.local\bin and on PATH). Install Claude Code: https://code.claude.com/docs'
}

try {
    & $claude @(Split-ClaudeArgs $ClaudeArgs)
}
finally {
    $spinner.Run = $false
    [Console]::Write("`e[?25h")
}

if ($settings.keepShellOpen -eq $true) {
    & (Get-Process -Id $PID).Path -NoLogo
}
