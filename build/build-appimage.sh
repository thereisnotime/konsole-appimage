#!/usr/bin/env bash
#
# Build a self-contained Konsole AppImage from KDE neon's noble packages.
# Runs as root inside an ubuntu:24.04 container. Do not run this on a host
# whose Qt6 you care about -- the neon repo replaces the entire Qt6 stack.
#
set -euo pipefail

NEON_CHANNEL="${NEON_CHANNEL:-user}"   # user | testing | unstable
OUT_DIR="${OUT_DIR:-/work/dist}"
APPDIR="${APPDIR:-/tmp/AppDir}"
ARCH="${ARCH:-x86_64}"

# linuxdeploy and appimagetool are themselves AppImages and there is no FUSE
# in a container, so they have to unpack themselves instead of mounting.
export APPIMAGE_EXTRACT_AND_RUN=1
export DEBIAN_FRONTEND=noninteractive

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }

log "Base packages"
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
    ca-certificates curl gnupg file desktop-file-utils patchelf zsync

log "Adding KDE neon repo (channel: $NEON_CHANNEL, dist: noble)"
install -d /etc/apt/keyrings
curl -fsSL https://archive.neon.kde.org/public.key \
    | gpg --dearmor -o /etc/apt/keyrings/neon.gpg
cat > /etc/apt/sources.list.d/neon.list <<EOF
deb [signed-by=/etc/apt/keyrings/neon.gpg] http://archive.neon.kde.org/${NEON_CHANNEL} noble main
EOF
apt-get update -qq

log "Installing Konsole"
apt-get install -y -qq --no-install-recommends konsole breeze-icon-theme

KONSOLE_VER="$(dpkg-query -W -f='${Version}' konsole)"
QT_VER="$(dpkg-query -W -f='${Version}' qt6-base 2>/dev/null || echo unknown)"
# Strip the epoch and neon build suffix -> 26.08.0
KONSOLE_SEMVER="$(printf '%s' "$KONSOLE_VER" | sed -E 's/^[0-9]+://; s/-.*$//')"
log "konsole $KONSOLE_VER  (semver $KONSOLE_SEMVER), qt6-base $QT_VER"

log "Fetching AppImage tooling"
cd /tmp
for tool in \
    "linuxdeploy|https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-${ARCH}.AppImage" \
    "linuxdeploy-plugin-qt|https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-${ARCH}.AppImage" \
    "appimagetool|https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-${ARCH}.AppImage" ; do
    name="${tool%%|*}"; url="${tool#*|}"
    curl -fsSL -o "/usr/local/bin/$name" "$url"
    chmod +x "/usr/local/bin/$name"
done

log "Assembling AppDir"
rm -rf "$APPDIR"
install -d "$APPDIR"

DESKTOP_FILE="$(find /usr/share/applications -name 'org.kde.konsole.desktop' -print -quit)"
ICON_FILE="$(find /usr/share/icons -name 'konsole.svg' -print -quit)"
: "${DESKTOP_FILE:?could not locate org.kde.konsole.desktop}"
: "${ICON_FILE:?could not locate a konsole icon}"

# konsolepart is dlopened by KParts, so it is not in konsole's NEEDED list and
# linuxdeploy cannot discover it on its own.
KPART_LIBS=()
while IFS= read -r so; do KPART_LIBS+=( -l "$so" ); done < <(
    find /usr/lib/"${ARCH}"-linux-gnu -name 'konsolepart.so' -o -name 'libkonsole*.so*' 2>/dev/null
)

linuxdeploy \
    --appdir "$APPDIR" \
    -e /usr/bin/konsole \
    -d "$DESKTOP_FILE" \
    -i "$ICON_FILE" \
    "${KPART_LIBS[@]}" \
    --plugin qt

log "Copying KF6 data linuxdeploy does not know about"
install -d "$APPDIR/usr/share"

# Konsole's own profiles and colour schemes.
cp -r /usr/share/konsole "$APPDIR/usr/share/"

# The menu definition. Without this the View menu -- and therefore Split View --
# silently vanishes. KF5 and KF6 disagree on the directory name, so glob it.
for d in /usr/share/kxmlgui*/konsole; do
    [ -d "$d" ] || continue
    parent="$(basename "$(dirname "$d")")"
    install -d "$APPDIR/usr/share/$parent"
    cp -r "$d" "$APPDIR/usr/share/$parent/"
done

# Breeze icons, else every toolbar button is blank.
for d in /usr/share/icons/breeze /usr/share/icons/breeze-dark; do
    [ -d "$d" ] && cp -r "$d" "$APPDIR/usr/share/icons/"
done

# KF6 plugins are dlopened (KIO workers, KAuth backends, ...).
if [ -d "/usr/lib/${ARCH}-linux-gnu/qt6/plugins/kf6" ]; then
    install -d "$APPDIR/usr/plugins"
    cp -r "/usr/lib/${ARCH}-linux-gnu/qt6/plugins/kf6" "$APPDIR/usr/plugins/"
fi

# Locale data for KF6's ki18n.
[ -d /usr/share/locale ] && cp -r /usr/share/locale "$APPDIR/usr/share/" || true

log "Writing qt.conf (keeps Qt paths out of the environment)"
cat > "$APPDIR/usr/bin/qt.conf" <<'EOF'
[Paths]
Prefix = ..
Plugins = plugins
Imports = qml
Qml2Imports = qml
EOF

log "Writing AppRun"
# Deliberately minimal. Konsole spawns a login shell that inherits this
# environment, so LD_LIBRARY_PATH and QT_PLUGIN_PATH must NOT be exported --
# they would follow every command the user runs and break host binaries.
# Libraries resolve through RPATH ($ORIGIN/../lib, set by linuxdeploy) and Qt
# paths through qt.conf above.
cat > "$APPDIR/AppRun" <<'EOF'
#!/usr/bin/env bash
HERE="$(dirname "$(readlink -f "${0}")")"

# KF6 finds konsoleui.rc, profiles, colour schemes and icons through this.
# Additive, so it is harmless for child processes.
export XDG_DATA_DIRS="${HERE}/usr/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"

# A Plasma 5 session exports a Qt5 platform theme. Letting a Qt6 process
# inherit it makes Qt load Qt5 theme plugins into a Qt6 process, which crashes.
export QT_QPA_PLATFORMTHEME=""

exec "${HERE}/usr/bin/konsole" "$@"
EOF
chmod +x "$APPDIR/AppRun"

log "Writing manifest"
install -d "$OUT_DIR"
{
    echo "built:            $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "neon_channel:     $NEON_CHANNEL"
    echo "base:             ubuntu:24.04 (noble)"
    echo "konsole:          $KONSOLE_VER"
    echo "qt6-base:         $QT_VER"
    echo "glibc:            $(ldd --version | head -1 | grep -oE '[0-9]+\.[0-9]+$')"
    echo
    echo "kf6 packages:"
    dpkg-query -W -f='  ${Package} ${Version}\n' 'kf6-*' 2>/dev/null | sort
} > "$OUT_DIR/manifest.txt"

log "Packaging"
OUTPUT="$OUT_DIR/Konsole-${KONSOLE_SEMVER}-${ARCH}.AppImage"
appimagetool "$APPDIR" "$OUTPUT"
chmod +x "$OUTPUT"

# So the caller (CI) can pick these up without re-parsing.
if [ -n "${GITHUB_ENV:-}" ]; then
    echo "KONSOLE_SEMVER=$KONSOLE_SEMVER" >> "$GITHUB_ENV"
fi
echo "$KONSOLE_SEMVER" > "$OUT_DIR/version.txt"

log "Done: $OUTPUT"
ls -lh "$OUTPUT"
