#!/usr/bin/env bats
# The app stub in dry-run mode. osascript is faked (it only has to answer `get`), so this runs anywhere.
load helper

setup() {
    setup_home
    export LAUNCHER_STUB_DIR=$BATS_TEST_TMPDIR/launcher
    mkdir -p "$LAUNCHER_STUB_DIR"
    cp "$REPO/src/mac/launcher-lib.sh" "$LAUNCHER_STUB_DIR/"
    : >"$LAUNCHER_STUB_DIR/claude-launch.command"
    cat >"$BATS_TEST_TMPDIR/fake-osascript" <<'EOS'
#!/bin/sh
# called as: -l JavaScript <json.js> get <file>
printf 'folder=~\nclaudeArgs=agents\nkeepShellOpen=false\nterminal=%s\n' "$FAKE_TERMINAL"
EOS
    chmod +x "$BATS_TEST_TMPDIR/fake-osascript"
    export LAUNCHER_OSASCRIPT=$BATS_TEST_TMPDIR/fake-osascript
    export LAUNCHER_DRY_RUN=1
    export LAUNCHER_FAKE_APPS=''
}

stub() {
    FAKE_TERMINAL=$1 run bash "$REPO/src/mac/app-stub.sh"
}

@test 'terminal opens Terminal with the command file' {
    stub terminal
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf 'open\n-a\nTerminal\n%s/claude-launch.command\n' "$LAUNCHER_STUB_DIR")" ]
}

@test 'iterm (installed) goes through osascript' {
    export LAUNCHER_FAKE_APPS='iTerm Ghostty'
    stub iterm
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = osascript ]
    [[ $output == *'tell application "iTerm"'* ]]
    [[ $output == *"$LAUNCHER_STUB_DIR/claude-launch.command"* ]]
}

@test 'ghostty (installed) uses open -na Ghostty --args -e' {
    export LAUNCHER_FAKE_APPS='iTerm Ghostty'
    stub ghostty
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf 'open\n-na\nGhostty\n--args\n-e\n%s/claude-launch.command\n' "$LAUNCHER_STUB_DIR")" ]
}

@test 'iterm missing shows a dialog and falls back to Terminal' {
    stub iterm
    [ "$status" -eq 0 ]
    [[ $output == *"iTerm isn't installed"* ]]
    [[ $output == *"Terminal"* ]]
    [[ $output != *'tell application "iTerm"'* ]]
}

@test 'missing files give a dialog and exit 1' {
    rm "$LAUNCHER_STUB_DIR/claude-launch.command"
    stub terminal
    [ "$status" -eq 1 ]
    [[ $output == *'files are missing'* ]]
}
