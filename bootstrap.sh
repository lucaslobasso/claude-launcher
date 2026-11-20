#!/usr/bin/env bash
# bootstrap.sh: one-line install of Claude Launcher on macOS, no git needed.
#
#   curl -fsSL https://raw.githubusercontent.com/lucaslobasso/claude-launcher/main/bootstrap.sh | bash
#
# With install options:
#   curl -fsSL https://raw.githubusercontent.com/lucaslobasso/claude-launcher/main/bootstrap.sh | bash -s -- --folder ~/code
#
# Uninstall the same way:
#   curl -fsSL https://raw.githubusercontent.com/lucaslobasso/claude-launcher/main/bootstrap.sh | bash -s -- --uninstall
#
# Downloads the latest release's source (or main, when there is no release yet) to a temp folder and runs its
# install.sh (or uninstall.sh) there. The app is still built on your Mac from that source.
#
# Everything is inside main(), so bash has read the whole script before anything runs (it arrives through a pipe).
set -euo pipefail

main() {
    local repo=lucaslobasso/claude-launcher ua='User-Agent: claude-launcher-bootstrap'
    local script=install.sh a
    ARGS=()  # (a global: `local x=()` is shaky in bash 3.2)
    for a in "$@"; do
        case $a in
            --uninstall) script=uninstall.sh ;;
            *) ARGS+=("$a") ;;
        esac
    done

    if [ "$(uname -s)" != Darwin ]; then
        echo 'bootstrap.sh is for macOS. On Windows, use bootstrap.ps1 (see the README).' >&2
        exit 1
    fi

    local release tarball label
    release=$(curl -fsSL -H "$ua" -H 'Accept: application/vnd.github+json' "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null) || release=''
    tarball=$(printf '%s\n' "$release" | sed -n 's/^[[:space:]]*"tarball_url":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
    label=$(printf '%s\n' "$release" | sed -n 's/^[[:space:]]*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
    if [ -z "$tarball" ] || [ -z "$label" ]; then
        tarball=https://github.com/$repo/archive/refs/heads/main.tar.gz
        label=main
    fi

    WORK=$(mktemp -d "${TMPDIR:-/tmp}/claude-launcher.XXXXXX")
    trap 'rm -rf "$WORK"' EXIT
    echo "Downloading Claude Launcher ($label)..."
    curl -fsSL -H "$ua" "$tarball" -o "$WORK/src.tar.gz"
    mkdir "$WORK/src"
    tar -xzf "$WORK/src.tar.gz" -C "$WORK/src"
    local root
    for root in "$WORK"/src/*/; do break; done
    [ -f "$root$script" ] || { echo "bootstrap.sh: $script not found in the download." >&2; exit 1; }
    bash "$root$script" ${ARGS[@]+"${ARGS[@]}"} </dev/null
}

main "$@"
