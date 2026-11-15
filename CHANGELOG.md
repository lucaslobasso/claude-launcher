# Changelog

All notable changes to this project. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [1.1.0] - 2026-11-15

### Added
- One-line install with no git: `irm …/bootstrap.ps1 | iex`. It installs from the latest release (or `main`), and `-Uninstall` removes it again.
- `install.ps1 -Update`: `git pull`, then reinstall with the same settings. The installer prints the version.
- `keepShellOpen` setting (`-KeepShellOpen`). By default the tab now closes when Claude exits, instead of leaving a PowerShell prompt.
- The exe has an icon of its own (`assets/claude-launcher.ico`). It's used when `claude.exe` isn't found, for example with an npm install, instead of a blank one.
- An error dialog when Windows Terminal can't be started. Before, clicking the shortcut silently did nothing.
- Pester tests, PSScriptAnalyzer, CI that compiles the exe, a release workflow and a CHANGELOG.

### Fixed
- `claudeArgs: ""` (or `-ClaudeArgs ""`) now starts a plain `claude` session, as documented. It used to fall back to `agents`.
- `claudeArgs` honors quotes: `--append-system-prompt "be brief"` reaches claude as two arguments, not three.
- `wt.exe`, `claude` and `csc.exe` are also looked up on `PATH` or in `Framework\` when they aren't in the usual place.
- Files from a downloaded ZIP are unblocked, and the Terminal profile runs the launch script with `-ExecutionPolicy Bypass`, so a RemoteSigned or strict policy no longer shows a red error on every launch.
- `#Requires -Version 7` on every script: running them from Windows PowerShell 5.1 gives a clear message instead of failing halfway on a re-install.
- `-ShortcutName` now also names the Terminal profile and the taskbar button. Shortcuts under an old name, or a Desktop shortcut after `-NoDesktopShortcut`, are removed, and existing taskbar pins are updated.
- The folder trust entry in `~/.claude.json` is written only when missing, and dates in that file are kept as text (PowerShell 7.5+).
- A broken `launcher.json` gives a warning and the defaults instead of an error.
- `uninstall.ps1` finds a custom install folder from the Terminal profile, carries on past an item it can't remove, and says what it left behind.
- The exe is built as AnyCPU (native on ARM64).

## [1.0.0] - 2026-11-13
### Added
- First release: shortcut → `ClaudeLauncher.exe` → Windows Terminal window with its own taskbar identity → orange loading screen → `claude agents`.

[1.1.0]: https://github.com/lucaslobasso/claude-launcher/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/lucaslobasso/claude-launcher/releases/tag/v1.0.0
