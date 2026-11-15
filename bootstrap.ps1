# bootstrap.ps1: one-line install of Claude Launcher, no git needed.
#
#   irm https://raw.githubusercontent.com/lucaslobasso/claude-launcher/main/bootstrap.ps1 | iex
#
# With install options:
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/lucaslobasso/claude-launcher/main/bootstrap.ps1))) -Folder D:\code
#
# Uninstall the same way:
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/lucaslobasso/claude-launcher/main/bootstrap.ps1))) -Uninstall
#
# Downloads the latest release's source (or main, when there is no release yet) to a temp folder and runs its
# install.ps1 (or uninstall.ps1) there. The launcher exe is still compiled on your machine from that source.
param(
    [switch]$Uninstall,
    [Parameter(ValueFromRemainingArguments)] $InstallArgs
)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host 'Claude Launcher needs PowerShell 7. Install it (winget install Microsoft.PowerShell), then run this again from "pwsh".' -ForegroundColor Yellow
    return
}

$repo = 'lucaslobasso/claude-launcher'
try {
    $release = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = 'claude-launcher-bootstrap' }
    $zipUrl = $release.zipball_url
    $label = $release.tag_name
}
catch {
    $zipUrl = "https://github.com/$repo/archive/refs/heads/main.zip"
    $label = 'main'
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("claude-launcher-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory $work | Out-Null
try {
    Write-Host "Downloading Claude Launcher ($label)..."
    $zip = Join-Path $work 'src.zip'
    Invoke-WebRequest $zipUrl -OutFile $zip -Headers @{ 'User-Agent' = 'claude-launcher-bootstrap' }
    Expand-Archive $zip -DestinationPath $work
    $root = Get-ChildItem $work -Directory | Select-Object -First 1
    Get-ChildItem $root.FullName -Recurse -File | Unblock-File
    & (Join-Path $root.FullName $(if ($Uninstall) { 'uninstall.ps1' } else { 'install.ps1' })) @InstallArgs
}
finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
