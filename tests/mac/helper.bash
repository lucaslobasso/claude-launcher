# Shared by the bats files. Source with: load helper
REPO=$(cd "$BATS_TEST_DIRNAME/../.." && pwd)

# A temp HOME so nothing touches the real one; env that would leak from an outer Claude session is cleared.
setup_home() {
    export HOME=$BATS_TEST_TMPDIR/home
    mkdir -p "$HOME"
    unset CLAUDE_CONFIG_DIR LAUNCHER_OSASCRIPT LAUNCHER_JSON_JS LAUNCHER_STUB_DIR LAUNCHER_DRY_RUN LAUNCHER_FAKE_APPS
}

require_darwin() {
    [ "$(uname -s)" = Darwin ] || skip 'needs macOS (osascript)'
}

# Runs json.js with the real osascript.
json() {
    osascript -l JavaScript "$REPO/src/mac/json.js" "$@"
}
