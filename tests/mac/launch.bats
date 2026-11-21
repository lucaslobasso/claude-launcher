#!/usr/bin/env bats
# claude-launch.sh against a fake claude, with no TTY and no TERM.
load helper

setup() {
    require_darwin
    setup_home
    D=$BATS_TEST_TMPDIR/launcher
    mkdir -p "$D" "$HOME/.local/bin" "$HOME/proj"
    cp "$REPO/src/mac/claude-launch.sh" "$REPO/src/mac/launcher-lib.sh" "$REPO/src/mac/json.js" "$D/"
    REC=$BATS_TEST_TMPDIR/rec
    mkdir -p "$REC"
    cat >"$HOME/.local/bin/claude" <<EOS
#!/bin/bash
pwd -P >"$REC/pwd"
: >"$REC/args"
for a in "\$@"; do printf '%s\n' "\$a" >>"$REC/args"; done
env | sort >"$REC/env"
exit \${FAKE_CLAUDE_EXIT:-0}
EOS
    chmod +x "$HOME/.local/bin/claude"
    unset TERM
}

launch() {
    run env -u CLAUDECODE bash "$D/claude-launch.sh" "$@" </dev/null
}

settings() { printf '%s\n' "$1" >"$D/launcher.json"; }

@test 'args come from launcher.json, cwd is the folder, trust is written' {
    local real
    real=$(cd "$HOME/proj" && pwd -P)
    settings "{ \"folder\": \"$HOME/proj\", \"claudeArgs\": \"agents --append-system-prompt \\\"be brief\\\"\" }"
    echo '{ "keep": 1 }' >"$HOME/.claude.json"
    launch
    [ "$status" -eq 0 ]
    [ "$(cat "$REC/pwd")" = "$real" ]
    [ "$(cat "$REC/args")" = "$(printf 'agents\n--append-system-prompt\nbe brief')" ]
    grep -q '"hasTrustDialogAccepted": true' "$HOME/.claude.json"
    grep -q '"keep": 1' "$HOME/.claude.json"
}

@test "claude's exit code propagates" {
    FAKE_CLAUDE_EXIT=3 launch
    [ "$status" -eq 3 ]
}

@test '--claude-args "" passes no arguments' {
    settings '{ "claudeArgs": "agents" }'
    launch --claude-args ''
    [ "$status" -eq 0 ]
    [ ! -s "$REC/args" ]
}

@test 'a missing folder falls back to HOME' {
    local real
    real=$(cd "$HOME" && pwd -P)
    launch --folder "$HOME/nope"
    [ "$status" -eq 0 ]
    [ "$(cat "$REC/pwd")" = "$real" ]
    [[ $output == *'not found'* ]]
}

@test 'keepShellOpen runs the shell afterwards' {
    settings '{ "keepShellOpen": true }'
    SHELL=/usr/bin/true launch
    [ "$status" -eq 0 ]
    [ -f "$REC/pwd" ]
}

@test 'CLAUDECODE set: child-session env is stripped' {
    run env CLAUDECODE=1 NO_COLOR=1 CLAUDE_PID=1 CLAUDE_JOB_DIR=/x CLAUDE_CODE_FOO=1 KEEP_ME=1 \
        bash "$D/claude-launch.sh" </dev/null
    [ "$status" -eq 0 ]
    ! grep -qE '^(CLAUDECODE|NO_COLOR|CLAUDE_PID|CLAUDE_JOB_DIR|CLAUDE_CODE_FOO)=' "$REC/env"
    grep -q '^KEEP_ME=1' "$REC/env"
}

@test 'CLAUDECODE unset: env is left alone' {
    run env -u CLAUDECODE NO_COLOR=1 CLAUDE_CODE_FOO=1 bash "$D/claude-launch.sh" </dev/null
    [ "$status" -eq 0 ]
    grep -q '^NO_COLOR=1' "$REC/env"
    grep -q '^CLAUDE_CODE_FOO=1' "$REC/env"
}

@test '--demo exits 0 without calling claude and logs the spinner' {
    launch --demo 0.3
    [ "$status" -eq 0 ]
    [ ! -e "$REC/pwd" ]
    [ -s "$D/spinner.log" ]
    grep -q 'spinner ended' "$D/spinner.log"
}
