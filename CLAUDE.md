# claude-launcher

Windows launcher: shortcut -> `ClaudeLauncher.exe` (src/ClaudeLauncher.cs, compiled by install.ps1 with the .NET
Framework 4 csc, C# 5 only) -> Windows Terminal fragment profile -> `src/claude-launch.ps1` (loading screen, trust,
runs claude). Settings: `%USERPROFILE%\.claude\launcher\launcher.json` (folder, claudeArgs, keepShellOpen).

- Shared logic + tests: `src/launcher-lib.ps1` (installed next to claude-launch.ps1), `tests/launcher.Tests.ps1` (Pester 5).
- Check: `Invoke-Pester tests` and `Invoke-ScriptAnalyzer -Path . -Recurse -Settings PSScriptAnalyzerSettings.psd1`.
- The AUMID string lives in two places: `$LauncherAumid` in src/common.ps1 and `Aumid` in ClaudeLauncher.cs.
- Version: `$LauncherVersion` in src/launcher-lib.ps1 + CHANGELOG. Release = push tag `vX.Y.Z` (release.yml publishes
  it; bootstrap.ps1 installs the latest release's source zip).
- Running install.ps1 on the dev machine replaces the live launcher (same fragment folder); keep a backup if needed.
- `bundle.ps1` installs the whole set (6 tools). `docs/bundle-section.md` is the canonical "Install the whole set"
  README block: edit it here, then copy it between the `bundle:start`/`bundle:end` markers of all six READMEs
  (claude-launcher, claude-taskbar, claude-boxed-messages, claude-statusline, claude-limit-revive, claude-language-spinner).
- README layout is shared with those repos: badges, hero, pitch, unofficial note, nav, Requirements, Install, Settings,
  How it looks, Update, How it works, Troubleshooting, Uninstall, Install the whole set, Contributing, License.
