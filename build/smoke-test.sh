#!/usr/bin/env bash
#
# Validate a built AppImage. Runs identically in CI and locally:
#
#   bash build/smoke-test.sh dist
#
set -euo pipefail

# Self-extract instead of FUSE-mounting, so this runs identically on a desktop,
# on a CI runner, and inside an unprivileged container (which has no /dev/fuse).
export APPIMAGE_EXTRACT_AND_RUN=1

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

# Konsole builds a QApplication before it parses --version, so it needs a
# platform plugin even for that. CI and containers are headless, so ask for the
# offscreen platform rather than requiring a display.
if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    ver="$("./$APPIMAGE" --version 2>&1)" || fail "AppImage does not run: $ver"
else
    ver="$(QT_QPA_PLATFORM=offscreen "./$APPIMAGE" --version 2>&1)" \
        || fail "AppImage does not run headless: $ver"
fi
ok "runs: $ver"

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

# xcb alone means the bundle cannot start natively on Wayland, and without
# offscreen it cannot run headless at all.
for plat in libqxcb.so libqoffscreen.so libqwayland.so; do
    [ -e "$root/usr/plugins/platforms/$plat" ] \
        || fail "platform plugin missing: $plat"
done
ok "platform plugins present (xcb, offscreen, wayland)"

# No bundled binary may reference a KDE/Qt library that is not in the bundle.
# Those do not exist on a non-KDE host, so a miss here means "works on my
# machine, broken everywhere else".
missing="$(mktemp)"
while IFS= read -r elf; do
    objdump -p "$elf" 2>/dev/null | awk '/NEEDED/{print $2}' | while IFS= read -r need; do
        case "$need" in
            libKF6*|libkuri*|libkonsole*|libQt6*) ;;
            *) continue ;;
        esac
        [ -e "$root/usr/lib/$need" ] || echo "$need" >> "$missing"
    done
done < <(find "$root/usr" -type f \( -name '*.so*' -o -name konsole \))
if [ -s "$missing" ]; then
    echo "unbundled KDE/Qt libraries referenced by the bundle:"
    sort -u "$missing" | sed 's/^/    /'
    rm -f "$missing"
    fail "bundle is incomplete"
fi
rm -f "$missing"
ok "no unbundled KDE/Qt dependencies"

# Every hand-copied plugin needs an RPATH, or it cannot find usr/lib at
# runtime (AppRun deliberately does not export LD_LIBRARY_PATH).
if [ -d "$root/usr/plugins/kf6" ]; then
    while IFS= read -r so; do
        objdump -x "$so" 2>/dev/null | grep -qE 'RPATH|RUNPATH' \
            || fail "plugin has no RPATH: ${so#$root/}"
    done < <(find "$root/usr/plugins/kf6" -name '*.so' -type f)
    ok "all KF6 plugins carry an RPATH"
fi

# Software centres and AppImage catalogues read this to describe the app.
if [ -n "$(ls "$root/usr/share/metainfo/"*.xml 2>/dev/null)" ]; then
    ok "AppStream metainfo present ($(basename "$(ls "$root/usr/share/metainfo/"*.xml | head -1)"))"
else
    fail "AppStream metainfo missing"
fi

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
