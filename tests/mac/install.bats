#!/usr/bin/env bats
# install.sh / uninstall.sh into temp folders (nothing under the real HOME).
load helper

setup() {
    require_darwin
    setup_home
    I=$BATS_TEST_TMPDIR/files
    A=$BATS_TEST_TMPDIR/apps
    APP="$A/Claude Code.app"
    # shellcheck source=src/mac/launcher-lib.sh
    . "$REPO/src/mac/launcher-lib.sh"
}

install() { run bash "$REPO/install.sh" --install-dir "$I" --apps-dir "$A" "$@"; }

plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"; }

@test 'install builds a valid app and the files' {
    install --claude-args 'agents --permission-mode plan' --keep-shell-open --terminal iterm
    [ "$status" -eq 0 ]
    plutil -lint "$APP/Contents/Info.plist"
    [ "$(plist "$APP" CFBundleIdentifier)" = "$BUNDLE_ID" ]
    [ "$(plist "$APP" CFBundleName)" = 'Claude Code' ]
    [ -x "$APP/Contents/MacOS/claude-launcher" ]
    [ -s "$APP/Contents/Resources/AppIcon.icns" ]
    file "$APP/Contents/Resources/AppIcon.icns" | grep -qi icon
    [ -x "$I/claude-launch.command" ]
    [ -x "$I/claude-launch.sh" ]
    run json get "$I/launcher.json"
    [ "$output" = "$(printf 'folder=~\nclaudeArgs=agents --permission-mode plan\nkeepShellOpen=true\nterminal=iterm')" ]
}

@test 're-install with only --terminal keeps the earlier --claude-args' {
    install --claude-args 'agents --x'
    install --terminal ghostty
    [ "$status" -eq 0 ]
    run json get "$I/launcher.json"
    [[ $output == *'claudeArgs=agents --x'* ]]
    [[ $output == *'terminal=ghostty'* ]]
}

@test '--name rename removes the old app' {
    install
    install --name 'My Claude'
    [ "$status" -eq 0 ]
    [ ! -e "$APP" ]
    [ -d "$A/My Claude.app" ]
    [ "$(plist "$A/My Claude.app" CFBundleName)" = 'My Claude' ]
}

@test 'a foreign app with the same name makes install fail and stays untouched' {
    mkdir -p "$APP/Contents"
    cat >"$APP/Contents/Info.plist" <<'EOP'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.example.other</string></dict></plist>
EOP
    cp "$APP/Contents/Info.plist" "$BATS_TEST_TMPDIR/orig.plist"
    install
    [ "$status" -ne 0 ]
    [[ $output == *"isn't Claude Launcher"* ]]
    cmp "$APP/Contents/Info.plist" "$BATS_TEST_TMPDIR/orig.plist"
}

@test 'uninstall removes the app and files' {
    install
    run bash "$REPO/uninstall.sh" --install-dir "$I" --apps-dir "$A"
    [ "$status" -eq 0 ]
    [ ! -e "$APP" ]
    [ ! -e "$I" ]
}

@test 'uninstall --keep-settings keeps launcher.json only' {
    install
    run bash "$REPO/uninstall.sh" --install-dir "$I" --apps-dir "$A" --keep-settings
    [ "$status" -eq 0 ]
    [ ! -e "$APP" ]
    [ -f "$I/launcher.json" ]
    [ ! -e "$I/claude-launch.sh" ]
}
