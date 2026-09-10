#!/usr/bin/env bash
#
# Validate a built AppImage. Runs identically in CI and locally:
#
#   bash build/smoke-test.sh dist
#
set -euo pipefail

DIST="${1:-dist}"
[ -d "$DIST" ] || { echo "no such directory: $DIST" >&2; exit 1; }

VERSION="$(cat "$DIST/version.txt")"
APPIMAGE="$DIST/Konsole-${VERSION}-x86_64.AppImage"
STABLE="$DIST/Konsole-x86_64.AppImage"

fail() { printf '\033[1;31mFAIL\033[0m %s\n' "$*"; exit 1; }
ok()   { printf '\033[1;32mok\033[0m   %s\n' "$*"; }

echo "testing $APPIMAGE (version $VERSION)"

[ -f "$APPIMAGE" ] || fail "versioned AppImage missing: $APPIMAGE"
ok "versioned AppImage present"

chmod +x "$DIST"/*.AppImage

if [ -f "$STABLE" ]; then
    cmp "$APPIMAGE" "$STABLE" || fail "stable copy differs from versioned build"
    ok "stable copy is byte-identical"
fi

"./$APPIMAGE" --version >/dev/null || fail "AppImage does not run"
ok "runs: $("./$APPIMAGE" --version)"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
( cd "$tmp" && "$OLDPWD/$APPIMAGE" --appimage-extract >/dev/null )
root="$tmp/squashfs-root"

file "$root/AppRun" | grep -q "shell script" \
    || fail "AppRun is not our script (linuxdeploy's symlink survived?)"
ok "AppRun is the wrapper script"

file "$root/usr/bin/konsole" | grep -q ELF \
    || fail "konsole binary is not an ELF (AppRun clobbered it?)"
ok "konsole binary intact"

# The whole design rests on these not reaching the shell Konsole spawns.
for leak in LD_LIBRARY_PATH QT_PLUGIN_PATH QML2_IMPORT_PATH LD_PRELOAD; do
    if grep -q "$leak" "$root/AppRun"; then
        fail "AppRun exports $leak -- it would leak into the spawned shell"
    fi
done
ok "AppRun leaks no loader/Qt paths"

[ -f "$root/usr/bin/qt.conf" ] || fail "qt.conf missing -- Qt paths would need env vars"
ok "qt.conf present"

max="$(find "$root/usr" -type f \( -name '*.so*' -o -name konsole \) \
       -exec objdump -T {} \; 2>/dev/null \
       | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -uV | tail -1)"
[ -n "$max" ] || fail "could not determine glibc requirement"
[ "$(printf '%s\nGLIBC_2.39\n' "$max" | sort -V | tail -1)" = "GLIBC_2.39" ] \
    || fail "requires $max, above the noble target GLIBC_2.39"
ok "max glibc requirement $max (<= GLIBC_2.39)"

if [ -n "$(ls "$DIST"/*.zsync 2>/dev/null)" ]; then
    ok "zsync present"
else
    fail "no .zsync -- AppImageUpdate cannot update this build"
fi

printf '\n\033[1;32mall checks passed\033[0m\n'
