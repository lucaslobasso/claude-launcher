# claude-launcher

Windows and macOS launcher (macOS: see the macOS group below). Windows: shortcut -> `ClaudeLauncher.exe` (src/ClaudeLauncher.cs, compiled by install.ps1 with the .NET
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
- macOS:
  - Flow: `~/Applications/<Name>.app` (stub from `src/mac/app-stub.sh`, built by `install.sh`) -> Terminal/iTerm/Ghostty
    (`terminal` in launcher.json) -> `src/mac/claude-launch.sh` (loading screen, trust, runs claude). Settings in
    `~/.claude/launcher/launcher.json`. Also `bootstrap.sh`, `uninstall.sh`.
  - JSON goes through `src/mac/json.js` (osascript JXA): no dependencies, and the scripts stay bash 3.2 compatible.
  - Checks: `shellcheck -x install.sh uninstall.sh bootstrap.sh src/mac/*.sh` and `bats tests/mac`; CI has a macOS job
    (`macos-latest`).
  - Version lives in two places: `$LauncherVersion` in src/launcher-lib.ps1 and `LAUNCHER_VERSION` in
    src/mac/launcher-lib.sh. A test checks they match.
  - On Windows, new `.sh` files need `git update-index --chmod=+x <file>` so they are executable on the Mac.
  - A change to `docs/bundle-section.md` must still be copied into the other five READMEs (follow-up for the 1.3.0 change).
- README layout is shared with those repos: badges, hero, pitch, unofficial note, nav, Requirements, Install, Settings,
  How it looks, Update, How it works, Troubleshooting, Uninstall, Install the whole set, Contributing, License.
