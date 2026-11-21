#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load helper

setup() {
    require_darwin
    setup_home
    F=$BATS_TEST_TMPDIR/launcher.json
    C=$BATS_TEST_TMPDIR/claude.json
}

@test 'get: defaults without a file' {
    run json get "$F"
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf 'folder=~\nclaudeArgs=agents\nkeepShellOpen=false\nterminal=terminal')" ]
}

@test 'get: an empty claudeArgs is kept' {
    echo '{ "claudeArgs": "" }' >"$F"
    run json get "$F"
    [[ $output == *$'claudeArgs=\n'* ]]
}

@test 'get: missing keys are filled in' {
    echo '{ "folder": "/x", "keepShellOpen": true, "terminal": "iTerm" }' >"$F"
    run json get "$F"
    [ "$output" = "$(printf 'folder=/x\nclaudeArgs=agents\nkeepShellOpen=true\nterminal=iterm')" ]
}

@test 'get: bad JSON gives the defaults and a warning' {
    echo '{ not json' >"$F"
    run --separate-stderr json get "$F"
    [ "$status" -eq 0 ]
    [[ $output == *'claudeArgs=agents'* ]]
    [[ $stderr == *"couldn't read"* ]]
}

@test 'set: merges, keeps unknown keys, stores a boolean' {
    echo '{ "folder": "/x", "extra": 1 }' >"$F"
    run json set "$F" claudeArgs='a b' keepShellOpen=true
    [ "$status" -eq 0 ]
    grep -q '"folder": "/x"' "$F"
    grep -q '"claudeArgs": "a b"' "$F"
    grep -q '"keepShellOpen": true' "$F"
    grep -q '"extra": 1' "$F"
}

@test 'set: an unknown key exits 2' {
    run --separate-stderr json set "$F" nope=1
    [ "$status" -eq 2 ]
    [[ $stderr == *'unknown setting'* ]]
}

@test 'trust: adds the folder, keeps other keys' {
    echo '{ "numStartups": 5, "projects": { "/other": { "x": 1 } } }' >"$C"
    run json trust "$C" /my/dir
    [ "$status" -eq 0 ]
    grep -q '"numStartups": 5' "$C"
    grep -q '"/other"' "$C"
    tr -d ' \n' <"$C" | grep -q '"/my/dir":{"hasTrustDialogAccepted":true}'
}

@test 'trust: no rewrite when already trusted' {
    printf '{"projects":{"/my/dir":{"hasTrustDialogAccepted":true}}}' >"$C"
    cp "$C" "$C.orig"
    run json trust "$C" /my/dir
    [ "$status" -eq 0 ]
    cmp "$C" "$C.orig"
}

@test 'trust: a bad file is left byte-identical, with a warning' {
    printf '{ broken' >"$C"
    cp "$C" "$C.orig"
    run --separate-stderr json trust "$C" /my/dir
    [ "$status" -eq 0 ]
    cmp "$C" "$C.orig"
    [[ $stderr == *"couldn't pre-trust"* ]]
}

@test 'trust: a missing file is a no-op' {
    run json trust "$BATS_TEST_TMPDIR/none.json" /my/dir
    [ "$status" -eq 0 ]
    [ ! -e "$BATS_TEST_TMPDIR/none.json" ]
}
