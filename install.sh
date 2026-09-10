#!/usr/bin/env bash
#
# Install the latest Konsole AppImage.
#
#   curl -fsSL https://raw.githubusercontent.com/thereisnotime/konsole-appimage/master/install.sh | bash
#
# Environment:
#   INSTALL_DIR   where to put the AppImage   (default: ~/AppImages)
#   VERSION       specific tag, e.g. v26.08.0 (default: latest)
#   NO_DESKTOP    set to 1 to skip the .desktop entry
#
set -euo pipefail

REPO="thereisnotime/konsole-appimage"
INSTALL_DIR="${INSTALL_DIR:-$HOME/AppImages}"
VERSION="${VERSION:-latest}"
ASSET="Konsole-x86_64.AppImage"

die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

[ "$(uname -m)" = "x86_64" ] || die "only x86_64 is published (this is $(uname -m))"

# glibc 2.38+ is required; the bundle is built on noble.
# getconf is authoritative and prints exactly "glibc X.Y"; ldd's banner varies
# between distributions ("2.39", "2.42.0", vendor-patched strings) and is only
# a fallback.
detect_glibc() {
    local v=""
    v="$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $NF}')"
    if [ -z "$v" ] && command -v ldd >/dev/null 2>&1; then
        v="$(ldd --version 2>/dev/null | head -1 \
             | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | tail -1)"
    fi
    printf '%s' "$v"
}

have="$(detect_glibc)"
if [ -n "$have" ]; then
    # Compare major.minor numerically. String sorting gets this wrong.
    if ! awk -v have="$have" -v need="2.38" 'BEGIN {
            split(have, h, "."); split(need, n, ".");
            exit !((h[1] > n[1]) || (h[1] == n[1] && h[2] >= n[2]))
        }'; then
        die "glibc $have is too old, need 2.38 or newer"
    fi
else
    log "Could not detect glibc version, continuing anyway"
fi

if [ "$VERSION" = "latest" ]; then
    BASE="https://github.com/$REPO/releases/latest/download"
else
    BASE="https://github.com/$REPO/releases/download/$VERSION"
fi

fetch() {
    if command -v curl >/dev/null 2>&1; then curl -fsSL "$1" -o "$2"
    elif command -v wget >/dev/null 2>&1; then wget -qO "$2" "$1"
    else die "need curl or wget"; fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

log "Downloading $ASSET ($VERSION)"
fetch "$BASE/$ASSET" "$tmp/$ASSET" || die "download failed -- does the release exist?"

log "Verifying checksum"
if fetch "$BASE/SHA256SUMS" "$tmp/SHA256SUMS" 2>/dev/null; then
    want="$(grep -F "$ASSET" "$tmp/SHA256SUMS" | awk '{print $1}' | head -1)"
    if [ -n "$want" ]; then
        got="$(sha256sum "$tmp/$ASSET" | awk '{print $1}')"
        [ "$want" = "$got" ] || die "checksum mismatch: expected $want, got $got"
        log "Checksum OK"
    else
        log "No entry for $ASSET in SHA256SUMS, skipping"
    fi
else
    log "SHA256SUMS unavailable, skipping verification"
fi

mkdir -p "$INSTALL_DIR"
install -m 0755 "$tmp/$ASSET" "$INSTALL_DIR/$ASSET"
log "Installed to $INSTALL_DIR/$ASSET"

if [ "${NO_DESKTOP:-0}" != "1" ]; then
    apps="$HOME/.local/share/applications"
    mkdir -p "$apps"
    cat > "$apps/konsole-appimage.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Konsole (AppImage)
Comment=Terminal emulator
Exec=$INSTALL_DIR/$ASSET
Icon=utilities-terminal
Categories=System;TerminalEmulator;
Terminal=false
DESKTOP
    command -v update-desktop-database >/dev/null 2>&1 && \
        update-desktop-database "$apps" 2>/dev/null || true
    log "Desktop entry: $apps/konsole-appimage.desktop"
fi

printf '\n\033[1;32mDone.\033[0m Run it with:\n  %s\n\n' "$INSTALL_DIR/$ASSET"
"$INSTALL_DIR/$ASSET" --version 2>/dev/null || true
