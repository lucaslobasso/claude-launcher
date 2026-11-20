# shellcheck shell=bash
# launcher-lib.sh: helpers shared by claude-launch.sh, the app stub, install.sh and uninstall.sh (and tested in
# tests/mac/). Installed next to claude-launch.sh. Sourced, never run. Written for bash 3.2 (macOS /bin/bash):
# no associative arrays, no mapfile, no ${var,,}.
#
# Environment hooks (for tests):
#   LAUNCHER_OSASCRIPT   command used to run json.js (default: osascript)
#   LAUNCHER_JSON_JS     path of json.js (default: next to this file)

# Keep in sync with $LauncherVersion in src/launcher-lib.ps1 (a test checks it).
# shellcheck disable=SC2034  # used by the scripts that source this file
LAUNCHER_VERSION='1.3.0'
# shellcheck disable=SC2034
BUNDLE_ID='io.github.lucaslobasso.claude-launcher'

LAUNCHER_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# ---- Strings ----

# str_replace_all <text> <find> <replacement>: every literal <find> replaced (no glob or & surprises).
str_replace_all() {
    local s=$1 find=$2 rep=$3 out=''
    if [ -z "$find" ]; then printf '%s' "$s"; return; fi
    while [[ $s == *"$find"* ]]; do
        out+=${s%%"$find"*}$rep
        s=${s#*"$find"}
    done
    printf '%s' "$out$s"
}

# xml_escape <text>: safe inside an XML element (Info.plist).
xml_escape() {
    local s=$1
    s=$(str_replace_all "$s" '&' '&amp;')
    s=$(str_replace_all "$s" '<' '&lt;')
    s=$(str_replace_all "$s" '>' '&gt;')
    s=$(str_replace_all "$s" '"' '&quot;')
    s=$(str_replace_all "$s" "'" '&apos;')
    printf '%s' "$s"
}

# sh_quote <text>: one single-quoted shell word ('it'\''s').
sh_quote() {
    printf "'%s'" "$(str_replace_all "$1" "'" "'\\''")"
}

# ---- Arguments ----

# split_claude_args <line>: splits an argument line the way you'd type it, into the array SPLIT_ARGS.
# Spaces separate, "double" or 'single' quotes group, backslashes are kept as they are. Same rules as
# Split-ClaudeArgs in launcher-lib.ps1 (the regex "([^"]*)"|'([^']*)'|(\S+)): a quote with no closing quote is
# just part of a word, and a quoted part ends the word ("a b"c is two arguments: `a b` and `c`). "" is an
# empty argument.
#   split_claude_args 'agents --append-system-prompt "be brief"'   ->  agents | --append-system-prompt | be brief
# Use it as: split_claude_args "$line"; "$claude" ${SPLIT_ARGS[@]+"${SPLIT_ARGS[@]}"}
split_claude_args() {
    SPLIT_ARGS=()
    local rest=$1 c tail tok
    while [ -n "$rest" ]; do
        c=${rest:0:1}
        case $c in
            [[:space:]])
                rest=${rest:1}
                continue
                ;;
            '"' | "'")
                tail=${rest:1}
                if [[ $tail == *"$c"* ]]; then
                    tok=${tail%%"$c"*}
                    SPLIT_ARGS+=("$tok")
                    rest=${tail#*"$c"}
                    continue
                fi
                ;;
        esac
        tok=${rest%%[[:space:]]*}
        SPLIT_ARGS+=("$tok")
        rest=${rest:${#tok}}
    done
}

# ---- Paths ----

# expand_folder <folder>: ~, ~/..., $HOME, ${HOME} and %USERPROFILE% (from a Windows launcher.json) all mean $HOME.
expand_folder() {
    local f=$1
    f=$(str_replace_all "$f" '%USERPROFILE%' "$HOME")
    # shellcheck disable=SC2016  # the literal text $HOME / ${HOME} is what's replaced
    f=$(str_replace_all "$f" '${HOME}' "$HOME")
    # shellcheck disable=SC2016
    f=$(str_replace_all "$f" '$HOME' "$HOME")
    case $f in
        \~) f=$HOME ;;
        \~/*) f=$HOME/${f#\~/} ;;
    esac
    printf '%s' "$f"
}

# find_claude: prints the path of the claude CLI, or returns 1.
# ~/.local/bin/claude (the native installer), then PATH, then Homebrew's two prefixes.
find_claude() {
    local p
    p=$HOME/.local/bin/claude
    if [ -f "$p" ] && [ -x "$p" ]; then printf '%s\n' "$p"; return 0; fi
    p=$(type -P claude 2>/dev/null) && [ -n "$p" ] && { printf '%s\n' "$p"; return 0; }
    for p in /opt/homebrew/bin/claude /usr/local/bin/claude; do
        if [ -f "$p" ] && [ -x "$p" ]; then printf '%s\n' "$p"; return 0; fi
    done
    return 1
}

# ---- JSON (src/mac/json.js through osascript) ----

json_js() {
    "${LAUNCHER_OSASCRIPT:-osascript}" -l JavaScript "${LAUNCHER_JSON_JS:-$LAUNCHER_LIB_DIR/json.js}" "$@"
}

# read_settings <launcher.json>: sets S_FOLDER, S_CLAUDE_ARGS, S_KEEP_SHELL_OPEN (true/false) and S_TERMINAL.
# Same rules as Read-LauncherSettings: a missing file gives the defaults, a key that is present wins even when
# empty, a file that doesn't parse gives the defaults and a warning (from json.js, on stderr). If osascript
# itself fails, the defaults are kept.
read_settings() {
    S_FOLDER='~'
    S_CLAUDE_ARGS='agents'
    S_KEEP_SHELL_OPEN=false
    S_TERMINAL=terminal
    local out line key val
    out=$(json_js get "$1") || return 0
    while IFS= read -r line; do
        key=${line%%=*}
        val=${line#*=}
        case $key in
            folder) S_FOLDER=$val ;;
            claudeArgs) S_CLAUDE_ARGS=$val ;;
            keepShellOpen) if [ "$val" = true ]; then S_KEEP_SHELL_OPEN=true; else S_KEEP_SHELL_OPEN=false; fi ;;
            terminal) S_TERMINAL=$val ;;
        esac
    done <<EOF
$out
EOF
}

# write_settings <launcher.json> [key=value ...]: merges the pairs into the file (other values are kept).
write_settings() {
    json_js set "$@"
}

# trust_folder <claude.json> <absolute path>: pre-accepts Claude Code's trust prompt for the folder.
# Best effort: warnings go to stderr, it never fails.
trust_folder() {
    json_js trust "$1" "$2" || true
}
