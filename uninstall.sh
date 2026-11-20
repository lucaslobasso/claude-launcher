#!/usr/bin/env bash
# uninstall.sh: removes Claude Launcher from macOS: its app (found by bundle id, whatever its name) and the
# installed files. Claude Code itself and your Claude settings are not touched.
#
#   ./uninstall.sh
#   ./uninstall.sh --keep-settings      # keep launcher.json for a later reinstall
set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=src/mac/launcher-lib.sh
. "$REPO_DIR/src/mac/launcher-lib.sh"

usage() {
    cat <<'EOF'
Usage: uninstall.sh [options]

  --install-dir <dir>   Where it was installed. Default: read from the installed app, else ~/.claude/launcher.
  --apps-dir <dir>      Where the app is. Default: ~/Applications (and /Applications is checked too).
  --keep-settings       Keep launcher.json (folder / arguments / terminal) for a later reinstall.
  -h, --help            Show this help.
EOF
}

die() {
    printf 'uninstall.sh: %s\n' "$1" >&2
    exit 1
}

install_dir=''
apps_dir=''
keep_settings=0
while [ $# -gt 0 ]; do
    case $1 in
        -h | --help) usage; exit 0 ;;
        --install-dir) [ $# -ge 2 ] || die '--install-dir needs a value.'; install_dir=$2; shift ;;
        --install-dir=*) install_dir=${1#*=} ;;
        --apps-dir) [ $# -ge 2 ] || die '--apps-dir needs a value.'; apps_dir=$2; shift ;;
        --apps-dir=*) apps_dir=${1#*=} ;;
        --keep-settings) keep_settings=1 ;;
        *) die "unknown option '$1' (see --help)." ;;
    esac
    shift
done

[ "$(uname -s)" = Darwin ] || die 'this uninstaller is for macOS. On Windows, use uninstall.ps1.'

# With --apps-dir only that folder is searched (tests); otherwise ~/Applications and /Applications.
search_dirs=()
if [ -n "$apps_dir" ]; then
    search_dirs+=("$(expand_folder "$apps_dir")")
else
    search_dirs+=("$HOME/Applications")
    [ -d /Applications ] && [ -w /Applications ] && search_dirs+=(/Applications)
fi

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null || true
}

apps=()
for dir in "${search_dirs[@]}"; do
    for app in "$dir"/*.app; do
        [ -d "$app" ] || continue
        [ "$(plist_value "$app" CFBundleIdentifier)" = "$BUNDLE_ID" ] && apps+=("$app")
    done
done

# The app records where its files are, so a custom --install-dir is found without asking.
if [ -z "$install_dir" ]; then
    for app in ${apps[@]+"${apps[@]}"}; do
        install_dir=$(plist_value "$app" ClaudeLauncherInstallDir)
        [ -n "$install_dir" ] && break
    done
fi
[ -n "$install_dir" ] || install_dir=$HOME/.claude/launcher
install_dir=$(expand_folder "$install_dir")
echo "Install folder: $install_dir"

failed=0
remove() {
    if rm -rf "$1" 2>/dev/null && [ ! -e "$1" ]; then
        echo "Removed $1"
    else
        printf '\033[33mWarning: couldn'"'"'t remove %s\033[0m\n' "$1" >&2
        failed=$((failed + 1))
    fi
}

for app in ${apps[@]+"${apps[@]}"}; do remove "$app"; done

files=(claude-launch.sh launcher-lib.sh json.js claude-launch.command spinner.log)
[ "$keep_settings" = 1 ] || files+=(launcher.json)
for f in "${files[@]}"; do
    [ -e "$install_dir/$f" ] && remove "$install_dir/$f"
done
if [ -d "$install_dir" ]; then
    if [ -z "$(ls -A "$install_dir")" ]; then
        remove "$install_dir"
    else
        echo "Left $install_dir in place: it holds files the launcher didn't create."
    fi
fi

echo
[ "${#apps[@]}" -gt 0 ] && echo 'If the app was pinned to the Dock, remove the pin by hand (right-click it, Options, Remove from Dock).'
echo 'The folder trust entry in ~/.claude.json is kept (Claude Code uses it too).'
if [ "$failed" -gt 0 ]; then
    printf '\033[33mClaude Launcher uninstalled, but %d item(s) couldn'"'"'t be removed (see above).\033[0m\n' "$failed"
else
    printf '\033[32mClaude Launcher uninstalled.\033[0m\n'
fi
