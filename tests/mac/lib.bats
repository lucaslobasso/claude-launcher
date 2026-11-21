#!/usr/bin/env bats
load helper

setup() {
    setup_home
    # shellcheck source=src/mac/launcher-lib.sh
    . "$REPO/src/mac/launcher-lib.sh"
}

# Joins SPLIT_ARGS with | so one string shows the result.
split() {
    split_claude_args "$1"
    local IFS='|'
    printf '%s' "${SPLIT_ARGS[*]-}"
}

@test 'split: spaces separate' {
    [ "$(split 'agents --permission-mode plan')" = 'agents|--permission-mode|plan' ]
}

@test 'split: quotes group words' {
    [ "$(split "agents --append-system-prompt \"be brief\" --x 'a b'")" = 'agents|--append-system-prompt|be brief|--x|a b' ]
}

@test 'split: backslashes are kept' {
    [ "$(split '--add-dir "C:\My Code\repo" D:\x')" = '--add-dir|C:\My Code\repo|D:\x' ]
}

@test 'split: empty and blank lines give nothing' {
    split_claude_args ''
    [ "${#SPLIT_ARGS[@]}" -eq 0 ]
    split_claude_args '   '
    [ "${#SPLIT_ARGS[@]}" -eq 0 ]
}

@test 'split: empty quotes are an empty argument, an unclosed quote is part of the word' {
    split_claude_args 'a "" b'
    [ "${#SPLIT_ARGS[@]}" -eq 3 ]
    [ -z "${SPLIT_ARGS[1]}" ]
    [ "$(split 'say "hi there')" = 'say|"hi|there' ]
}

@test 'split: a quoted part ends the word' {
    [ "$(split '"a b"c')" = 'a b|c' ]
}

@test 'expand_folder: tilde, HOME variable and USERPROFILE' {
    [ "$(expand_folder '~')" = "$HOME" ]
    [ "$(expand_folder '~/x')" = "$HOME/x" ]
    # shellcheck disable=SC2016
    [ "$(expand_folder '$HOME/code')" = "$HOME/code" ]
    # shellcheck disable=SC2016
    [ "$(expand_folder '${HOME}/code')" = "$HOME/code" ]
    [ "$(expand_folder '%USERPROFILE%')" = "$HOME" ]
    [ "$(expand_folder '/abs/path')" = '/abs/path' ]
}

@test 'xml_escape escapes the five characters' {
    [ "$(xml_escape "a&b<c>d\"e'f")" = 'a&amp;b&lt;c&gt;d&quot;e&apos;f' ]
}

@test 'sh_quote survives a single quote' {
    local q
    q=$(sh_quote "it's here")
    [ "$(eval "printf '%s' $q")" = "it's here" ]
}

@test 'LAUNCHER_VERSION matches the version in launcher-lib.ps1' {
    local ps
    ps=$(grep -m1 '^\$LauncherVersion' "$REPO/src/launcher-lib.ps1" | cut -d"'" -f2)
    [ -n "$ps" ]
    [ "$ps" = "$LAUNCHER_VERSION" ]
}
