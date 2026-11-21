#!/bin/bash
# app-stub.sh: the executable of the Claude Launcher app (<Name>.app/Contents/MacOS/claude-launcher).
# install.sh fills in the install folder below. It opens the terminal chosen in launcher.json ("terminal":
# terminal, iterm or ghostty) running claude-launch.command, which runs claude-launch.sh. Then it exits; the app
# has LSUIElement set, so it never shows in the Dock itself.
#
# LAUNCHER_DRY_RUN=1 prints the commands (one argument per line, a blank line after each) instead of running them.

# install.sh replaces the next line with the install folder, shell-quoted.
LAUNCHER_DIR=@@INSTALL_DIR@@
LAUNCHER_DIR=${LAUNCHER_STUB_DIR:-$LAUNCHER_DIR}  # tests point it elsewhere

COMMAND_FILE=$LAUNCHER_DIR/claude-launch.command

run() {
    if [ "${LAUNCHER_DRY_RUN-}" = 1 ]; then
        printf '%s\n' "$@" ''
        return 0
    fi
    "$@"
}

# A dialog from the stub (osascript's own, needs no permission). The text is passed as an argument, not quoted
# into the script.
dialog() {
    local out=/dev/null
    [ "${LAUNCHER_DRY_RUN-}" = 1 ] && out=/dev/stdout
    run osascript -e 'on run argv' \
        -e 'display dialog (item 1 of argv) with title "Claude Launcher" buttons {"OK"} default button 1 with icon caution giving up after 30' \
        -e 'end run' "$1" >"$out" 2>&1
}

if [ ! -f "$LAUNCHER_DIR/launcher-lib.sh" ] || [ ! -f "$COMMAND_FILE" ]; then
    dialog "Claude Launcher's files are missing from $LAUNCHER_DIR. Run install.sh again."
    exit 1
fi

# shellcheck source=src/mac/launcher-lib.sh
. "$LAUNCHER_DIR/launcher-lib.sh"
read_settings "$LAUNCHER_DIR/launcher.json" 2>/dev/null

open_terminal_app() {
    run open -a Terminal "$COMMAND_FILE"
}

# `open -Ra` finds an app by name without starting it.
app_installed() {
    if [ "${LAUNCHER_DRY_RUN-}" = 1 ] && [ -n "${LAUNCHER_FAKE_APPS+set}" ]; then
        case " $LAUNCHER_FAKE_APPS " in *" $1 "*) return 0 ;; *) return 1 ;; esac
    fi
    open -Ra "$1" >/dev/null 2>&1
}

case $S_TERMINAL in
    terminal | '')
        open_terminal_app
        ;;
    iterm | iterm2)
        if app_installed iTerm; then
            run osascript -e 'on run argv' \
                -e 'tell application "iTerm"' \
                -e 'activate' \
                -e 'create window with default profile command (quoted form of (item 1 of argv))' \
                -e 'end tell' \
                -e 'end run' "$COMMAND_FILE"
        else
            dialog 'launcher.json says "terminal": "iterm", but iTerm isn'"'"'t installed. Opening Terminal instead.'
            open_terminal_app
        fi
        ;;
    ghostty)
        if app_installed Ghostty; then
            run open -na Ghostty --args -e "$COMMAND_FILE"
        else
            dialog 'launcher.json says "terminal": "ghostty", but Ghostty isn'"'"'t installed. Opening Terminal instead.'
            open_terminal_app
        fi
        ;;
    *)
        dialog "launcher.json says \"terminal\": \"$S_TERMINAL\", which isn't one of terminal, iterm or ghostty. Opening Terminal instead."
        open_terminal_app
        ;;
esac
