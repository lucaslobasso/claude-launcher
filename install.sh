#!/usr/bin/env bash
# install.sh: installs Claude Launcher on macOS: an app (Launchpad, Spotlight, Dock) that opens Claude Code in
# Terminal (or iTerm / Ghostty) with an orange loading animation and no trust prompt.
#
#   ./install.sh
#   ./install.sh --folder ~/code --claude-args "agents --permission-mode plan"
#   ./install.sh --claude-args ""        # a plain `claude` session instead of the agent view
#   ./install.sh --update                # git pull, then reinstall with the same settings
#
# Run ./install.sh --help for all options.
set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=src/mac/launcher-lib.sh
. "$REPO_DIR/src/mac/launcher-lib.sh"

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

usage() {
    cat <<'EOF'
Usage: install.sh [options]

  --folder <dir>          Folder Claude opens in (and is pre-trusted). Default: your home folder,
                          or the value from a previous install.
  --claude-args <args>    Arguments for claude. Default: "agents" (agent view), or the value from a
                          previous install. "" = a plain claude session.
  --keep-shell-open       When Claude exits, stay at a shell prompt. --keep-shell-open=false turns it off.
  --terminal <app>        terminal (default), iterm or ghostty.
  --name <name>           Name of the app (Launchpad, Spotlight, Dock) and the window title.
                          Default: "Claude Code".
  --install-dir <dir>     Where the launcher files go. Default: ~/.claude/launcher.
  --apps-dir <dir>        Where the app goes. Default: ~/Applications.
  --update                Pull the latest version first (git checkout only), then install.
  -h, --help              Show this help.

Only the settings you pass change; the rest keep the values in launcher.json.
EOF
}

die() {
    printf 'install.sh: %s\n' "$1" >&2
    exit 1
}
warn() {
    printf '\033[33mWarning: %s\033[0m\n' "$1" >&2
}
need_value() {
    [ "$2" -ge 2 ] || die "$1 needs a value (see --help)."
}

# ---- Options ----
name='Claude Code'
install_dir=$HOME/.claude/launcher
apps_dir=$HOME/Applications
update=0
sets=()
rest=()  # every option except --update, for the rerun after git pull
folder=''
have_folder=0
while [ $# -gt 0 ]; do
    arg=$1
    case $arg in
        -h | --help) usage; exit 0 ;;
        --update) update=1; shift; continue ;;
        --folder) need_value "$arg" $#; folder=$2; have_folder=1 ;;
        --folder=*) folder=${arg#*=}; have_folder=1 ;;
        --claude-args) need_value "$arg" $#; sets+=("claudeArgs=$2") ;;
        --claude-args=*) sets+=("claudeArgs=${arg#*=}") ;;
        --keep-shell-open) sets+=('keepShellOpen=true') ;;
        --keep-shell-open=*)
            case ${arg#*=} in
                true | 1 | yes) sets+=('keepShellOpen=true') ;;
                false | 0 | no) sets+=('keepShellOpen=false') ;;
                *) die "--keep-shell-open takes true or false, not '${arg#*=}'." ;;
            esac
            ;;
        --terminal | --terminal=*)
            if [ "$arg" = --terminal ]; then need_value "$arg" $#; t=$2; else t=${arg#*=}; fi
            t=$(printf '%s' "$t" | tr '[:upper:]' '[:lower:]')
            case $t in
                terminal | iterm | ghostty) sets+=("terminal=$t") ;;
                *) die "--terminal must be terminal, iterm or ghostty, not '$t'." ;;
            esac
            ;;
        --name) need_value "$arg" $#; name=$2 ;;
        --name=*) name=${arg#*=} ;;
        --install-dir) need_value "$arg" $#; install_dir=$2 ;;
        --install-dir=*) install_dir=${arg#*=} ;;
        --apps-dir) need_value "$arg" $#; apps_dir=$2 ;;
        --apps-dir=*) apps_dir=${arg#*=} ;;
        *) die "unknown option '$arg' (see --help)." ;;
    esac
    case $arg in
        --*=* | --keep-shell-open) rest+=("$arg"); shift ;;
        *) rest+=("$arg" "$2"); shift 2 ;;
    esac
done

[ "$(uname -s)" = Darwin ] || die 'this installer is for macOS. On Windows, use install.ps1.'

if [ "$update" = 1 ]; then
    [ -d "$REPO_DIR/.git" ] || die '--update needs a git checkout. Download the latest release instead (see README).'
    git -C "$REPO_DIR" pull --ff-only || die 'git pull failed (see above).'
    exec bash "$REPO_DIR/install.sh" ${rest[@]+"${rest[@]}"}
fi

case $name in
    '' | . | ..) die '--name must not be empty.' ;;
    */* | *:*) die "--name can't contain / or :" ;;
    .*) die "--name can't start with a dot (the app would be hidden)." ;;
esac
case $name in *[[:cntrl:]]*) die "--name can't contain control characters." ;; esac

install_dir=$(expand_folder "$install_dir")
apps_dir=$(expand_folder "$apps_dir")

if [ "$have_folder" = 1 ]; then
    f=$(expand_folder "$folder")
    [ -d "$f" ] || die "folder '$folder' is not a directory."
    sets+=("folder=$(cd "$f" && pwd)")
fi

# ---- Requirements ----
command -v osascript >/dev/null || die 'osascript was not found (it ships with macOS).'
find_claude >/dev/null || {
    warn 'claude was not found (in ~/.local/bin, on PATH, /opt/homebrew/bin or /usr/local/bin). Install Claude Code: https://code.claude.com/docs. The launcher looks again each time it starts.'
}

# Bundle id of an app, or nothing.
bundle_id_of() {
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist" 2>/dev/null || true
}

mkdir -p "$apps_dir"
apps_dir=$(cd "$apps_dir" && pwd)
app=$apps_dir/$name.app
if [ -e "$app" ] && [ "$(bundle_id_of "$app")" != "$BUNDLE_ID" ]; then
    die "$app already exists and isn't Claude Launcher. Pick another --name."
fi

# ---- Files ----
mkdir -p "$install_dir"
install_dir=$(cd "$install_dir" && pwd)
for f in claude-launch.sh launcher-lib.sh json.js; do
    cp "$REPO_DIR/src/mac/$f" "$install_dir/$f"
done
chmod 755 "$install_dir/claude-launch.sh"
chmod 644 "$install_dir/launcher-lib.sh" "$install_dir/json.js"

# Settings: keep what a previous install wrote, override with whatever was passed now.
settings_file=$install_dir/launcher.json
write_settings "$settings_file" ${sets[@]+"${sets[@]}"} || die "couldn't write $settings_file."
read_settings "$settings_file"

# Terminal runs a .command file in a new window with your default profile.
command_file=$install_dir/claude-launch.command
{
    printf '#!/bin/bash\n'
    printf '# Opened by the %s app (Claude Launcher). Written by install.sh.\n' "$name"
    printf 'exec /bin/bash %s --name %s\n' "$(sh_quote "$install_dir/claude-launch.sh")" "$(sh_quote "$name")"
} >"$command_file"
chmod 755 "$command_file"

# ---- The app ----
# AppIcon.icns from the PNG, with the sips and iconutil that ship with macOS.
make_icns() {
    local png=$1 out=$2 tmp s
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/claude-launcher-icon.XXXXXX") || return 1
    mkdir "$tmp/AppIcon.iconset" || { rm -rf "$tmp"; return 1; }
    for s in 16 32 128 256 512; do
        if ! sips -z "$s" "$s" "$png" --out "$tmp/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null 2>&1 ||
            ! sips -z $((s * 2)) $((s * 2)) "$png" --out "$tmp/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null 2>&1; then
            rm -rf "$tmp"
            return 1
        fi
    done
    iconutil -c icns "$tmp/AppIcon.iconset" -o "$out" >/dev/null 2>&1 || { rm -rf "$tmp"; return 1; }
    rm -rf "$tmp"
}

build=$(mktemp -d "${TMPDIR:-/tmp}/claude-launcher-app.XXXXXX")
trap 'rm -rf "$build"' EXIT
bundle=$build/$name.app
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"

# The stub, with the install folder filled in.
stub=$bundle/Contents/MacOS/claude-launcher
while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = 'LAUNCHER_DIR=@@INSTALL_DIR@@' ]; then
        printf 'LAUNCHER_DIR=%s\n' "$(sh_quote "$install_dir")"
    else
        printf '%s\n' "$line"
    fi
done <"$REPO_DIR/src/mac/app-stub.sh" >"$stub"
grep -q '@@INSTALL_DIR@@' "$stub" && die "couldn't fill in the install folder in the app stub."
chmod 755 "$stub"

plist=$(cat "$REPO_DIR/src/mac/Info.plist.in")
plist=$(str_replace_all "$plist" '@@NAME@@' "$(xml_escape "$name")")
plist=$(str_replace_all "$plist" '@@BUNDLE_ID@@' "$BUNDLE_ID")
plist=$(str_replace_all "$plist" '@@VERSION@@' "$LAUNCHER_VERSION")
plist=$(str_replace_all "$plist" '@@INSTALL_DIR@@' "$(xml_escape "$install_dir")")
printf '%s\n' "$plist" >"$bundle/Contents/Info.plist"
plutil -lint "$bundle/Contents/Info.plist" >/dev/null || die "the generated Info.plist isn't valid."
printf 'APPL????' >"$bundle/Contents/PkgInfo"

if ! make_icns "$REPO_DIR/assets/claude-launcher.png" "$bundle/Contents/Resources/AppIcon.icns"; then
    rm -f "$bundle/Contents/Resources/AppIcon.icns"
    warn "couldn't make the app icon (sips/iconutil failed); the app gets the generic icon."
fi

# Apps of this launcher under any name (a previous --name), found by bundle id, make way for the new one.
for old in "$apps_dir"/*.app; do
    [ -d "$old" ] || continue
    if [ "$(bundle_id_of "$old")" = "$BUNDLE_ID" ]; then
        rm -rf "$old"
        [ "$old" = "$app" ] || echo "Removed old app $old"
    fi
done
mv "$bundle" "$app"

# New bundles can show a blank icon until Launch Services notices them.
touch "$app"
"$LSREGISTER" -f "$app" >/dev/null 2>&1 || true

case $S_KEEP_SHELL_OPEN in true) on_exit='stay at a shell prompt' ;; *) on_exit='end the session (the window closes if your Terminal profile is set to)' ;; esac
echo
printf '\033[32mClaude Launcher %s installed to %s\033[0m\n' "$LAUNCHER_VERSION" "$install_dir"
echo "App:        $app"
echo "Opens in:   $(expand_folder "$S_FOLDER")"
echo "Runs:       claude $S_CLAUDE_ARGS"
echo "Terminal:   $S_TERMINAL"
echo "When Claude exits: $on_exit"
echo "Settings:   $settings_file (edit it any time, or re-run install.sh with --folder / --claude-args / --keep-shell-open / --terminal)"
echo "Open it from Launchpad or Spotlight ('$name'); drag it to the Dock to pin it."
