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
# The two *-dev-tools packages are build-only and are not bundled into the
# AppDir. linuxdeploy-plugin-qt shells out to qmake to discover Qt's
# plugin/QML/translation directories, and to qmlimportscanner to work out which
# QML modules to deploy (KF6 pulls in qt6-declarative, so the QML module runs
# whether or not Konsole itself uses QML).
apt-get install -y -qq --no-install-recommends \
    konsole breeze-icon-theme qt6-base-dev-tools qt6-declarative-dev-tools

# Neon's layout does not match Ubuntu's, so find qmake rather than assume.
QMAKE="$(command -v qmake6 || true)"
if [ -z "$QMAKE" ]; then
    QMAKE="$(find /usr/lib/qt6 /usr/lib/"${ARCH}"-linux-gnu/qt6 -name 'qmake6' -o -name 'qmake' 2>/dev/null | head -1)"
fi
: "${QMAKE:?could not locate qmake6 -- linuxdeploy-plugin-qt cannot run without it}"
export QMAKE
log "Using qmake: $QMAKE"

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
: "${DESKTOP_FILE:?could not locate org.kde.konsole.desktop}"

# linuxdeploy insists the AppDir root icon matches the desktop file's Icon= key,
# which for Konsole is "utilities-terminal", not "konsole". Search Breeze first
# so we do not pick up whatever unrelated theme apt happened to pull in.
ICON_NAME="$(sed -n 's/^Icon=//p' "$DESKTOP_FILE" | head -1)"
: "${ICON_NAME:?desktop file has no Icon= entry}"

ICON_FILE=""
for dir in /usr/share/icons/breeze /usr/share/icons/hicolor /usr/share/icons; do
    [ -d "$dir" ] || continue
    ICON_FILE="$(find "$dir" \( -name "${ICON_NAME}.svg" -o -name "${ICON_NAME}.png" \) -print -quit 2>/dev/null)"
    [ -n "$ICON_FILE" ] && break
done
# Fall back to Konsole's own icon, renamed to match the desktop entry.
if [ -z "$ICON_FILE" ]; then
    ICON_FILE="$(find /usr/share/icons/breeze /usr/share/icons -name 'konsole.svg' -print -quit 2>/dev/null)"
fi
: "${ICON_FILE:?could not locate an icon for '$ICON_NAME'}"
log "Icon: $ICON_FILE -> $ICON_NAME"

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
    --icon-filename "$ICON_NAME" \
    "${KPART_LIBS[@]}" \
    --plugin qt

log "Copying KF6 data linuxdeploy does not know about"
install -d "$APPDIR/usr/share"

# NOTE: Konsole 26.08 ships neither /usr/share/konsole nor a kxmlgui*/konsole
# directory. Since KF6 the ui.rc, built-in profiles and colour schemes are
# compiled into the binary as Qt resources, so there is nothing to copy for
# those. Everything below is copied only if it actually exists -- the layout
# differs between KDE releases and a missing optional path must not fail a
# build.
for d in \
    /usr/share/konsole \
    /usr/share/knotifications6 \
    /usr/share/qlogging-categories6 \
    /usr/share/kglobalaccel \
    /usr/share/kio \
    /usr/share/kf6 ; do
    [ -e "$d" ] || continue
    cp -r "$d" "$APPDIR/usr/share/"
done

# Kept for older/newer layouts that do ship an on-disk ui.rc.
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

# Translations for ki18n. Copying all of /usr/share/locale would add hundreds
# of megabytes of unrelated catalogues, so take only Konsole's and those of the
# frameworks that supply its menu and dialog strings.
if [ -d /usr/share/locale ]; then
    ( cd / && find usr/share/locale -type f \( \
          -name 'konsole*.mo' \
       -o -name 'kxmlgui*.mo' \
       -o -name 'kconfigwidgets*.mo' \
       -o -name 'kwidgetsaddons*.mo' \
       -o -name 'kcoreaddons*.mo' \
       -o -name 'kio*.mo' \
        \) -print0 2>/dev/null \
        | xargs -0 -r cp --parents -t "$APPDIR/" ) || true
fi

log "Writing qt.conf (keeps Qt paths out of the environment)"
cat > "$APPDIR/usr/bin/qt.conf" <<'EOF'
[Paths]
Prefix = ..
Plugins = plugins
Imports = qml
Qml2Imports = qml
EOF

log "Writing AppRun"
# linuxdeploy leaves AppDir/AppRun as a symlink to usr/bin/konsole. Redirecting
# into it would follow the link and overwrite the Konsole binary with this
# script, so drop it first.
rm -f "$APPDIR/AppRun"
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

# Embedding update information lets AppImageUpdate fetch a binary delta instead
# of re-downloading ~100 MB. Requires the matching .zsync to be published as a
# release asset alongside the AppImage.
APPIMAGETOOL_ARGS=()
if [ -n "${UPDATE_INFO:-}" ]; then
    APPIMAGETOOL_ARGS+=( -u "$UPDATE_INFO" )
    log "Update info: $UPDATE_INFO"
fi

# appimagetool writes the .zsync into the CURRENT WORKING DIRECTORY, not
# alongside the output path, so run it from OUT_DIR or the zsync goes missing.
( cd "$OUT_DIR" && appimagetool "${APPIMAGETOOL_ARGS[@]}" "$APPDIR" "$(basename "$OUTPUT")" )
chmod +x "$OUTPUT"

# A stable filename makes the /releases/latest/download/ URL usable, which is
# what install.sh and any curl one-liner depend on.
if [ "${STABLE_COPY:-0}" = "1" ]; then
    cp "$OUTPUT" "$OUT_DIR/Konsole-${ARCH}.AppImage"
    log "Stable-named copy: Konsole-${ARCH}.AppImage"
fi

log "Checksums"
( cd "$OUT_DIR" && shopt -s nullglob && sha256sum ./*.AppImage ./*.zsync > SHA256SUMS )
cat "$OUT_DIR/SHA256SUMS"

# So the caller (CI) can pick these up without re-parsing.
if [ -n "${GITHUB_ENV:-}" ]; then
    echo "KONSOLE_SEMVER=$KONSOLE_SEMVER" >> "$GITHUB_ENV"
fi
echo "$KONSOLE_SEMVER" > "$OUT_DIR/version.txt"

# The container runs as root, so without this a bind-mounted dist/ ends up
# root-owned on the host and needs sudo to clean up.
if [ -n "${HOST_UID:-}" ]; then
    chown -R "${HOST_UID}:${HOST_GID:-$HOST_UID}" "$OUT_DIR"
fi

log "Done: $OUTPUT"
ls -lh "$OUTPUT"
