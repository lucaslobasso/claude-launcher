# bundle.ps1: install (or remove) the whole set of Claude Code tools in one go.
#
#   irm https://raw.githubusercontent.com/lucaslobasso/claude-launcher/main/bundle.ps1 | iex
#
# With options:
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/lucaslobasso/claude-launcher/main/bundle.ps1))) -Only statusline,limit-revive
#   ... -Skip launcher,taskbar     everything except these
#   ... -List                      what is installed, nothing changed
#   ... -Uninstall                 remove (combine with -Only / -Skip)
#
# Tools: launcher and taskbar (Windows apps, through their own bootstrap.ps1), and the plugins boxed-messages,
# statusline, limit-revive and language-spinner (through `claude plugin`). Each tool also installs on its own; see
# its README. The plugins work on macOS and Linux too, with the `claude plugin` commands in their READMEs.
param(
    [string[]]$Only,
    [string[]]$Skip,
    [switch]$Uninstall,
    [switch]$List
)

$ErrorActionPreference = 'Stop'

$BundleTools = [ordered]@{
    'launcher'         = @{ Kind = 'app'; Repo = 'claude-launcher'; What = 'One click into Claude Code, Claude icon, loading spinner' }
    'taskbar'          = @{ Kind = 'app'; Repo = 'claude-taskbar'; What = 'Sessions and usage on the Windows taskbar' }
    'boxed-messages'   = @{ Kind = 'plugin'; Repo = 'claude-boxed-messages'; What = 'Colored boxes around messages' }
    'statusline'       = @{ Kind = 'plugin'; Repo = 'claude-statusline'; What = 'Status line, usage only when it gets high'; Needs = 'node' }
    'limit-revive'     = @{ Kind = 'plugin'; Repo = 'claude-limit-revive'; What = 'Resumes unfinished work after the usage limit resets' }
    'language-spinner' = @{ Kind = 'plugin'; Repo = 'claude-language-spinner'; What = 'Spinner words in a language you are learning' }
}

function Resolve-BundleSelection {
    <# The tool names to act on, in install order. -Only and -Skip take names or comma lists. #>
    param([string[]]$Only, [string[]]$Skip)
    $split = { param($list) @($list | ForEach-Object { "$_" -split '[,\s]+' } | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() }) }
    $only = @(& $split $Only)
    $skip = @(& $split $Skip)
    $unknown = @($only + $skip | Where-Object { -not $BundleTools.Contains($_) })
    if ($unknown) {
        throw "Unknown tool: $($unknown -join ', '). Pick from: $($BundleTools.Keys -join ', ')."
    }
    @($BundleTools.Keys | Where-Object { (-not $only -or $only -contains $_) -and $skip -notcontains $_ })
}

function Get-PluginId([string]$Name) { "$Name@$($BundleTools[$Name].Repo)" }

function Get-ConfigDir {
    if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
}

function Get-InstalledPlugins {
    try { @(claude plugin list --json 2>$null | ConvertFrom-Json) } catch { @() }
}

function Test-AppInstalled([string]$Name) {
    switch ($Name) {
        'launcher' { Test-Path (Join-Path $HOME '.claude\launcher\ClaudeLauncher.exe') }
        'taskbar' { Test-Path (Join-Path (Get-ConfigDir) 'taskbar\ClaudeTaskbar.exe') }
    }
}

function Get-StatusLineEntry {
    $file = Join-Path (Get-ConfigDir) 'settings.json'
    try { (Get-Content $file -Raw | ConvertFrom-Json).statusLine } catch { $null }
}

function Restore-StatusLineEntry($Entry) {
    <# `claude plugin` commands have been seen to drop statusLine while rewriting settings.json: put it back. #>
    if (-not $Entry -or (Get-StatusLineEntry)) { return }
    $file = Join-Path (Get-ConfigDir) 'settings.json'
    $settings = Get-Content $file -Raw | ConvertFrom-Json
    $settings | Add-Member -NotePropertyName statusLine -NotePropertyValue $Entry -Force
    Copy-Item $file "$file.bak-bundle" -Force
    [IO.File]::WriteAllText($file, ($settings | ConvertTo-Json -Depth 32) + "`n")
    Write-Host '  statusLine was dropped by a plugin command; restored it (backup: settings.json.bak-bundle).' -ForegroundColor Yellow
}

function Remove-StatuslinePluginEntry {
    <# Plugins get no uninstall hook, so remove the statusline plugin's own entry (only that one) before uninstalling it. #>
    $file = Join-Path (Get-ConfigDir) 'settings.json'
    $entry = Get-StatusLineEntry
    if (-not $entry -or "$($entry.command)" -notmatch 'claude-statusline[^"]*[\\/]statusline\.mjs') { return }
    $settings = Get-Content $file -Raw | ConvertFrom-Json
    $settings.PSObject.Properties.Remove('statusLine')
    Copy-Item $file "$file.bak-bundle" -Force
    [IO.File]::WriteAllText($file, ($settings | ConvertTo-Json -Depth 32) + "`n")
}

function Invoke-AppBootstrap([string]$Name, [switch]$Remove) {
    $url = "https://raw.githubusercontent.com/lucaslobasso/$($BundleTools[$Name].Repo)/main/bootstrap.ps1"
    $script = [scriptblock]::Create((Invoke-RestMethod $url -Headers @{ 'User-Agent' = 'claude-bundle' }))
    if ($Remove) { & $script -Uninstall } else { & $script }
}

function Invoke-Claude {
    & claude @args 2>&1 | ForEach-Object { "    $_" } | Write-Host
    $LASTEXITCODE
}

function Install-BundlePlugin([string]$Name, $Installed) {
    $id = Get-PluginId $Name
    $repo = "lucaslobasso/$($BundleTools[$Name].Repo)"
    if ($Installed | Where-Object id -EQ $id) {
        Invoke-Claude plugin marketplace update $BundleTools[$Name].Repo | Out-Null
        return (Invoke-Claude plugin update $id) -eq 0
    }
    Invoke-Claude plugin marketplace add $repo | Out-Null
    (Invoke-Claude plugin install $id --scope user) -eq 0
}

function Uninstall-BundlePlugin([string]$Name, $Installed) {
    $id = Get-PluginId $Name
    if (-not ($Installed | Where-Object id -EQ $id)) { return $true }
    if ($Name -eq 'statusline') { Remove-StatuslinePluginEntry }
    $ok = (Invoke-Claude plugin uninstall $id) -eq 0
    Invoke-Claude plugin marketplace remove $BundleTools[$Name].Repo | Out-Null
    $ok
}

function Invoke-Bundle {
    param([string[]]$Only, [string[]]$Skip, [switch]$Uninstall, [switch]$List)
    $names = Resolve-BundleSelection -Only $Only -Skip $Skip
    $onWindows = $PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows
    $hasClaude = [bool](Get-Command claude -ErrorAction SilentlyContinue)
    $installed = if ($hasClaude) { Get-InstalledPlugins } else { @() }

    if ($List) {
        foreach ($name in $BundleTools.Keys) {
            $tool = $BundleTools[$name]
            $state = if ($tool.Kind -eq 'app') { if (Test-AppInstalled $name) { 'installed' } else { '-' } }
            else { $p = $installed | Where-Object id -EQ (Get-PluginId $name); if ($p) { "installed $($p.version)" } else { '-' } }
            Write-Host ('{0,-18} {1,-16} {2}' -f $name, $state, $tool.What)
        }
        return
    }

    $results = [ordered]@{}
    $statusLine = Get-StatusLineEntry
    foreach ($name in $names) {
        $tool = $BundleTools[$name]
        $verb = if ($Uninstall) { 'Removing' } else { 'Installing' }
        Write-Host "`n== $verb $name" -ForegroundColor Cyan
        if ($tool.Kind -eq 'app' -and -not $onWindows) { $results[$name] = 'skipped (Windows only)'; continue }
        if ($tool.Kind -eq 'app' -and $PSVersionTable.PSVersion.Major -lt 7) {
            $results[$name] = 'skipped (needs PowerShell 7: winget install Microsoft.PowerShell, then run this from pwsh)'; continue
        }
        if ($tool.Kind -eq 'plugin' -and -not $hasClaude) { $results[$name] = 'skipped (claude is not on PATH)'; continue }
        if (-not $Uninstall -and $tool.Needs -and -not (Get-Command $tool.Needs -ErrorAction SilentlyContinue)) {
            Write-Host "  Note: $name needs $($tool.Needs) on PATH to run." -ForegroundColor Yellow
        }
        try {
            if ($tool.Kind -eq 'app') {
                Invoke-AppBootstrap $name -Remove:$Uninstall
                $ok = $true
            }
            elseif ($Uninstall) { $ok = Uninstall-BundlePlugin $name $installed }
            else { $ok = Install-BundlePlugin $name $installed }
            $results[$name] = if ($ok) { if ($Uninstall) { 'removed' } else { 'installed' } } else { 'failed (see above)' }
        }
        catch {
            $results[$name] = "failed: $($_.Exception.Message)"
        }
        if ($tool.Kind -eq 'plugin' -and -not ($Uninstall -and $name -eq 'statusline')) { Restore-StatusLineEntry $statusLine }
    }

    Write-Host "`n== Summary" -ForegroundColor Cyan
    foreach ($name in $results.Keys) { Write-Host ('{0,-18} {1}' -f $name, $results[$name]) }
    if (-not $Uninstall -and ($results.Values -contains 'installed')) {
        Write-Host "`nPlugins take effect in new Claude Code sessions." -ForegroundColor Green
    }
}

if (-not $env:CLAUDE_BUNDLE_TEST) {
    Invoke-Bundle -Only $Only -Skip $Skip -Uninstall:$Uninstall -List:$List
}
