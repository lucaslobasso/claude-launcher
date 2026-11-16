# Changelog

All notable changes to this project. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [1.2.0] - 2026-11-16

### Added
- `bundle.ps1`: installs the whole set of tools in one line (launcher, Claude Taskbar, and the boxed-messages, statusline, limit-revive and language-spinner plugins), with `-Only`, `-Skip`, `-List` and `-Uninstall`. Plugin commands that drop the `statusLine` entry from `settings.json` get it put back. Pester tests.
- `docs/bundle-section.md`: the "Install the whole set" README section shared by all six repos.

### Changed
- README in the layout shared by the set: release and platform badges, a "How it looks" section, the whole-set section.

### Fixed
- The README said `ClaudeLauncher.exe "<profile>"` opens any Terminal profile; the argument only names the taskbar button.

## [1.1.1] - 2026-11-15

### Fixed
- Re-installing with a different `-ShortcutName` no longer makes Claude open as admin with Terminal's icon. Renaming used to create a new Terminal profile, which lost the `"elevate": false` that overrides a Terminal set to run every profile as admin. The profile now has a fixed GUID, and the installer adds `"elevate": false` to Terminal's `settings.json` when `profiles.defaults` says `"elevate": true`. A backup is kept as `settings.json.bak-launcher`.
- `ClaudeLauncher.exe` run with no arguments (e.g. by another tool) opens the launcher profile again, instead of Terminal's default shell. It now picks the profile by GUID, not by name.
- Profile entries that Terminal kept for an older name are removed, so they no longer show up as dead profiles.

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

[1.2.0]: https://github.com/lucaslobasso/claude-launcher/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/lucaslobasso/claude-launcher/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/lucaslobasso/claude-launcher/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/lucaslobasso/claude-launcher/releases/tag/v1.0.0
