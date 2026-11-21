#!/bin/bash
# claude-launch.sh: runs inside the terminal window the Claude Launcher app opens (through claude-launch.command).
# Shows an orange loading animation, pre-accepts the folder trust prompt, then starts Claude Code.
#
# Settings live in launcher.json next to this script (written by install.sh, safe to edit by hand):
#   { "folder": "~", "claudeArgs": "agents", "keepShellOpen": false, "terminal": "terminal" }
#   folder         folder Claude opens in; ~, $HOME and %USERPROFILE% all mean your home folder
#   claudeArgs     arguments for claude ("" = a plain `claude` session); "double quotes" group words
#   keepShellOpen  true: when Claude exits, stay at a shell prompt in that folder instead of ending
#   terminal       which app the launcher opens (terminal, iterm, ghostty); read by the app, not here
# Flags override the file for one run:
#   --folder <dir>, --claude-args <args>   as above
#   --name <text>                          window title (install.sh passes the app's name)
#   --demo <s>                             only show the loading animation for <s> seconds, don't start Claude
#
# Works without a terminal too (tests): with no TTY or no TERM the animation falls back to 80x24 and the
# "press Enter" prompt returns at once.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=src/mac/launcher-lib.sh
. "$SCRIPT_DIR/launcher-lib.sh"

ESC=$'\033'
ORANGE="${ESC}[38;2;217;119;87m"  # #D97757
YELLOW="${ESC}[33m"
RESET="${ESC}[0m"

# ---- Flags ----
folder=''
have_folder=0
claude_args=''
have_args=0
demo=0
name='Claude Code'
while [ $# -gt 0 ]; do
    case $1 in
        --folder) folder=${2-}; have_folder=1; shift ;;
        --folder=*) folder=${1#*=}; have_folder=1 ;;
        --claude-args) claude_args=${2-}; have_args=1; shift ;;
        --claude-args=*) claude_args=${1#*=}; have_args=1 ;;
        --demo) demo=${2-}; shift ;;
        --demo=*) demo=${1#*=} ;;
        --name) name=${2-}; shift ;;
        --name=*) name=${1#*=} ;;
        *) printf '%sClaude Launcher: ignoring unknown option %s%s\n' "$YELLOW" "$1" "$RESET" >&2 ;;
    esac
    [ $# -gt 0 ] && shift
done
case $demo in
    '' | *[!0-9.]* | *.*.* | .) demo=0 ;;
esac

stop_with_message() {
    stop_spinner
    printf '%s[2J%s[H%s[?25h' "$ESC" "$ESC" "$ESC"
    printf '%sClaude Launcher: %s%s\n' "$YELLOW" "$1" "$RESET"
    read -r -p 'Press Enter to close ' _ || true
    exit 1
}

# ---- Settings ----
read_settings "$SCRIPT_DIR/launcher.json"
[ "$have_folder" = 1 ] || folder=$S_FOLDER
[ "$have_args" = 1 ] || claude_args=$S_CLAUDE_ARGS
folder=$(expand_folder "$folder")

printf '%s]0;%s\007' "$ESC" "$name"  # window title

# ---- Loading animation: orange "Starting Claude" with dots, centered, in a background subshell ----
# It stops when told to (SIGTERM, handled between frames so a frame is never cut in half), when this script is
# gone, or after its time limit. bash can't watch for Claude's first draw the way the Windows version does
# (reading the cursor position would steal Claude's input), so it is stopped just before Claude starts.
SPINNER_PID=''
FRAMES=('   ' '.  ' '.. ' '...')  # fixed width so the text stays centered
spinner_size() {
    local r c
    r=$(tput lines 2>/dev/null) || r=''
    c=$(tput cols 2>/dev/null) || c=''
    case $r in '' | *[!0-9]* | 0) r=24 ;; esac
    case $c in '' | *[!0-9]* | 0) c=80 ;; esac
    ROWS=$r
    COLS=$c
}
spinner_loop() {
    local log=$1 max_ticks=$2 parent=$3
    local text row col
    TICKS=0
    WHY=timeout
    STOP=''
    trap 'STOP=1' TERM
    while [ "$TICKS" -lt "$max_ticks" ]; do
        if [ -n "$STOP" ]; then WHY=stopped; break; fi
        if ! kill -0 "$parent" 2>/dev/null; then WHY='launcher exited'; break; fi
        text="Starting Claude${FRAMES[$(((TICKS / 2 + 2) % 4))]}"  # starts at 2 dots, steps every 200 ms
        spinner_size
        row=$((ROWS / 2)); [ "$row" -lt 1 ] && row=1
        col=$(((COLS - ${#text}) / 2 + 1)); [ "$col" -lt 1 ] && col=1
        printf '%s[%d;%dH%s%s%s' "$ESC" "$row" "$col" "$ORANGE" "$text" "$RESET"
        TICKS=$((TICKS + 1))
        sleep 0.1
    done
    [ -n "$STOP" ] && WHY=stopped
    { printf '%s spinner ended after ~%d ms (%s)\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$((TICKS * 100))" "$WHY" >>"$log"; } 2>/dev/null
}
stop_spinner() {
    if [ -n "$SPINNER_PID" ]; then
        kill -TERM "$SPINNER_PID" 2>/dev/null
        wait "$SPINNER_PID" 2>/dev/null
        SPINNER_PID=''
    fi
}
# shellcheck disable=SC2329  # run by the EXIT trap below
on_exit() {
    stop_spinner
    printf '%s[?25h' "$ESC"  # show the cursor again
}
trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# The limit (like the Windows version): 10 s, or the demo length + 1 s.
max_ticks=$(awk -v d="$demo" 'BEGIN { t = int(d * 10) + 10; if (t < 100) t = 100; print t }')
printf '%s[?25l%s[2J%s[H' "$ESC" "$ESC" "$ESC"  # hide cursor, clear screen
spinner_loop "$SCRIPT_DIR/spinner.log" "$max_ticks" "$$" &
SPINNER_PID=$!

if [ "$demo" != 0 ] && awk -v d="$demo" 'BEGIN { exit !(d > 0) }'; then
    sleep "$demo"
    stop_spinner
    printf '%s[2J%s[H%s[?25h' "$ESC" "$ESC" "$ESC"
    exit 0
fi

# ---- Clean environment: if started from inside another Claude session, drop what it passes down ----
# (NO_COLOR=1 strips all color, CLAUDECODE/CLAUDE_CODE_* mark a child session). CLAUDECODE is the sign of that;
# without it nothing is touched, so CLAUDE_CODE_* settings from your shell profile (Bedrock, Vertex, ...) stay.
if [ -n "${CLAUDECODE+set}" ]; then
    unset NO_COLOR CLAUDECODE CLAUDE_PID CLAUDE_JOB_DIR
    for v in $(compgen -v CLAUDE_CODE_); do unset "$v"; done
fi

# ---- Folder ----
folder_warning=''
if [ -z "$folder" ] || [ ! -d "$folder" ] || ! cd "$folder" 2>/dev/null; then
    folder_warning="folder '$folder' not found; opening in your home folder instead."
    cd "$HOME" || cd /
fi

# ---- Pre-accept the trust prompt (Claude Code keys projects by the real path, symlinks resolved) ----
# Warnings are kept for after the animation (json.js prints nothing else).
trust_warning=$(trust_folder "${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json" "$(pwd -P)" 2>&1)

# ---- Start Claude ----
claude=$(find_claude) || stop_with_message 'claude was not found (looked in ~/.local/bin, on PATH, /opt/homebrew/bin and /usr/local/bin). Install Claude Code: https://code.claude.com/docs'

split_claude_args "$claude_args"
stop_spinner
printf '%s[2J%s[H%s[?25h' "$ESC" "$ESC" "$ESC"  # clear, show the cursor
[ -n "$folder_warning" ] && printf '%sClaude Launcher: %s%s\n' "$YELLOW" "$folder_warning" "$RESET"
[ -n "$trust_warning" ] && printf '%s%s%s\n' "$YELLOW" "$trust_warning" "$RESET"

trap - INT TERM HUP  # Claude handles Ctrl+C itself; this script just waits for it
"$claude" ${SPLIT_ARGS[@]+"${SPLIT_ARGS[@]}"}
status=$?
printf '%s[?25h' "$ESC"

if [ "$S_KEEP_SHELL_OPEN" = true ]; then
    trap - EXIT
    exec "${SHELL:-/bin/zsh}" -l
fi
exit "$status"
