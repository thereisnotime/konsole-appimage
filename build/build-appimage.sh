#!/usr/bin/env bash
#
# Build a self-contained Konsole AppImage from KDE neon's noble packages.
# Runs as root inside an ubuntu:24.04 container. Do not run this on a host
# whose Qt6 you care about -- the neon repo replaces the entire Qt6 stack.
#
set -euo pipefail

NEON_CHANNEL="${NEON_CHANNEL:-user}"   # user | testing | unstable
# Which Ubuntu base to build against. The container image MUST match:
#   noble -> ubuntu:24.04, glibc 2.39, current Konsole
#   jammy -> ubuntu:22.04, glibc 2.35, older Konsole but runs on 22.04
NEON_DIST="${NEON_DIST:-noble}"
OUT_DIR="${OUT_DIR:-/work/dist}"
APPDIR="${APPDIR:-/tmp/AppDir}"
ARCH="${ARCH:-x86_64}"

# linuxdeploy and appimagetool are themselves AppImages and there is no FUSE
# in a container, so they have to unpack themselves instead of mounting.
export APPIMAGE_EXTRACT_AND_RUN=1
export DEBIAN_FRONTEND=noninteractive

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }

# A stalled apt is the most common way this build wedges: without a timeout it
# blocks forever rather than failing. Seen in practice against neon's archive
# over a broken IPv6 path, where apt-get update never returned at all.
# APT_FORCE_IPV4=1 works around that; it is opt-in because forcing IPv4 would
# break an IPv6-only host.
install -d /etc/apt/apt.conf.d
{
    echo 'Acquire::http::Timeout "30";'
    echo 'Acquire::https::Timeout "30";'
    echo 'Acquire::Retries "3";'
    [ "${APT_FORCE_IPV4:-0}" = "1" ] && echo 'Acquire::ForceIPv4 "true";'
} > /etc/apt/apt.conf.d/99-build-appimage
[ "${APT_FORCE_IPV4:-0}" = "1" ] && log "Forcing IPv4 for apt"

log "Base packages"
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
    ca-certificates curl gnupg file desktop-file-utils patchelf zsync

# Guard against building jammy packages inside a noble container or vice
# versa -- the result would silently require the wrong glibc.
BASE_CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"
if [ "$BASE_CODENAME" != "$NEON_DIST" ]; then
    echo "ERROR: NEON_DIST=$NEON_DIST but the container is $BASE_CODENAME." >&2
    echo "       Use ubuntu:24.04 for noble, ubuntu:22.04 for jammy." >&2
    exit 1
fi

log "Adding KDE neon repo (channel: $NEON_CHANNEL, dist: $NEON_DIST)"
install -d /etc/apt/keyrings
curl -fsSL https://archive.neon.kde.org/public.key \
    | gpg --dearmor -o /etc/apt/keyrings/neon.gpg
cat > /etc/apt/sources.list.d/neon.list <<EOF
deb [signed-by=/etc/apt/keyrings/neon.gpg] http://archive.neon.kde.org/${NEON_CHANNEL} ${NEON_DIST} main
EOF
apt-get update -qq

log "Installing Konsole"
# The two *-dev-tools packages are build-only and are not bundled into the
# AppDir. linuxdeploy-plugin-qt shells out to qmake to discover Qt's
# plugin/QML/translation directories, and to qmlimportscanner to work out which
# QML modules to deploy (KF6 pulls in qt6-declarative, so the QML module runs
# whether or not Konsole itself uses QML).
# qt6-wayland is a RUNTIME dependency: without its platform plugin the AppImage
# cannot start natively on a Wayland session, which is the default on Plasma 6.
apt-get install -y -qq --no-install-recommends \
    konsole breeze-icon-theme qt6-wayland \
    qt6-base-dev-tools qt6-declarative-dev-tools

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

# KF6 plugins are dlopened (KIO workers, KAuth backends, ...), so linuxdeploy
# never sees them and they have to be copied by hand.
if [ -d "/usr/lib/${ARCH}-linux-gnu/qt6/plugins/kf6" ]; then
    install -d "$APPDIR/usr/plugins"
    cp -r "/usr/lib/${ARCH}-linux-gnu/qt6/plugins/kf6" "$APPDIR/usr/plugins/"
fi

# Konsole performs no privileged operations and has no spell checking, but the
# KF6 plugin set drags in a KAuth polkit backend and three Sonnet spell-check
# backends. Their dependencies (libpolkit-qt6-core-1, libhunspell, libaspell,
# libvoikko) are not present on a non-KDE host, so keeping the plugins would
# mean either four phantom host requirements or bundling libraries nothing uses.
# Drop them.
if [ -d "$APPDIR/usr/plugins/kf6" ]; then
    for junk in kauth sonnet; do
        if [ -e "$APPDIR/usr/plugins/kf6/$junk" ]; then
            rm -rf "$APPDIR/usr/plugins/kf6/$junk"
            log "  pruned unused plugin set: $junk"
        fi
    done
    # Sonnet backends are sometimes installed loose rather than in a subdir.
    find "$APPDIR/usr/plugins" -name 'sonnet_*.so' -delete 2>/dev/null || true
fi

# linuxdeploy-plugin-qt bundles only the xcb platform plugin. Without wayland
# the AppImage cannot start natively on a Wayland session; without offscreen it
# cannot run headless at all, which also makes it untestable in CI.
QT_PLUGIN_SRC="/usr/lib/${ARCH}-linux-gnu/qt6/plugins"
if [ -d "$QT_PLUGIN_SRC/platforms" ]; then
    install -d "$APPDIR/usr/plugins/platforms"
    # Qt6 names it libqwayland.so; libqwayland-generic.so was the Qt5 name.
    for plat in libqoffscreen.so libqminimal.so libqwayland.so \
                libqwayland-generic.so libqwayland-egl.so libqeglfs.so; do
        [ -e "$QT_PLUGIN_SRC/platforms/$plat" ] || continue
        cp "$QT_PLUGIN_SRC/platforms/$plat" "$APPDIR/usr/plugins/platforms/"
        log "  extra platform plugin: $plat"
    done
    # Wayland needs its shell-integration and decoration plugins too.
    for extra in wayland-shell-integration wayland-decoration-client wayland-graphics-integration-client; do
        [ -d "$QT_PLUGIN_SRC/$extra" ] || continue
        cp -r "$QT_PLUGIN_SRC/$extra" "$APPDIR/usr/plugins/"
        log "  extra plugin dir: $extra"
    done
fi

# Everything copied above bypassed linuxdeploy, so it has neither an RPATH nor
# a resolved dependency closure. Both have to be fixed by hand.
if [ -d "$APPDIR/usr/plugins" ]; then
    # A hand-copied plugin has no RPATH, so it cannot find the bundled
    # libraries -- and since AppRun deliberately does not export
    # LD_LIBRARY_PATH, nothing else will find them either.
    log "Setting RPATH on hand-copied plugins"
    while IFS= read -r so; do
        rel="$(realpath --relative-to="$(dirname "$so")" "$APPDIR/usr/lib")"
        patchelf --set-rpath "\$ORIGIN/$rel" "$so" 2>/dev/null || true
    done < <(find "$APPDIR/usr/plugins" -name '*.so' -type f)

    # Those plugins pull in KDE/Qt libraries that nothing else in the bundle
    # references. They are absent on a non-KDE host, so resolve the closure and
    # bundle them. Only KDE/Qt libraries are copied -- system and
    # GPU-driver-coupled libraries must keep coming from the host.
    log "Resolving KDE/Qt dependency closure for plugins"
    for _pass in 1 2 3 4 5; do
        added=0
        while IFS= read -r elf; do
            while IFS= read -r need; do
                case "$need" in
                    libKF6*|libkuri*|libkonsole*|libQt6*) ;;
                    *) continue ;;
                esac
                [ -e "$APPDIR/usr/lib/$need" ] && continue
                src="$(find /usr/lib/"${ARCH}"-linux-gnu -name "$need" -print -quit 2>/dev/null)"
                [ -n "$src" ] || continue
                cp -L "$src" "$APPDIR/usr/lib/$need"
                patchelf --set-rpath '$ORIGIN' "$APPDIR/usr/lib/$need" 2>/dev/null || true
                log "  bundled missing dependency: $need"
                added=$((added + 1))
            done < <(objdump -p "$elf" 2>/dev/null | awk '/NEEDED/{print $2}')
        done < <(find "$APPDIR/usr/lib" "$APPDIR/usr/plugins" -name '*.so*' -type f)
        [ "$added" -eq 0 ] && break
    done
fi

# AppStream metainfo: what software centres and AppImage catalogues read to
# describe the app. Copy only Konsole's, not every package's.
for mi in /usr/share/metainfo/org.kde.konsole*.xml; do
    [ -e "$mi" ] || continue
    install -d "$APPDIR/usr/share/metainfo"
    cp "$mi" "$APPDIR/usr/share/metainfo/"
    log "  metainfo: $(basename "$mi")"
done

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
    echo "base:             $BASE_CODENAME ($NEON_DIST)"
    echo "konsole:          $KONSOLE_VER"
    echo "qt6-base:         $QT_VER"
    echo "glibc:            $(ldd --version | head -1 | grep -oE '[0-9]+\.[0-9]+$')"
    echo
    echo "kf6 packages:"
    dpkg-query -W -f='  ${Package} ${Version}\n' 'kf6-*' 2>/dev/null | sort
} > "$OUT_DIR/manifest.txt"

log "Packaging"
# The jammy build is a second artifact in the same release, so it needs a
# distinguishing name. The noble build keeps the plain one.
if [ "$NEON_DIST" = "noble" ]; then
    SUFFIX=""
else
    SUFFIX="-${NEON_DIST}"
fi
OUTPUT="$OUT_DIR/Konsole-${KONSOLE_SEMVER}${SUFFIX}-${ARCH}.AppImage"

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
    cp "$OUTPUT" "$OUT_DIR/Konsole${SUFFIX}-${ARCH}.AppImage"
    log "Stable-named copy: Konsole${SUFFIX}-${ARCH}.AppImage"
    # Also give the zsync a stable name. UPDATE_INFO globs have to be exact:
    # "Konsole-*-x86_64.AppImage.zsync" would match the jammy zsync as well and
    # could hand a 22.04 user the build their glibc cannot load.
    if [ -e "${OUTPUT}.zsync" ]; then
        cp "${OUTPUT}.zsync" "$OUT_DIR/Konsole${SUFFIX}-${ARCH}.AppImage.zsync"
        log "Stable-named zsync: Konsole${SUFFIX}-${ARCH}.AppImage.zsync"
    fi
fi

log "Checksums"
( cd "$OUT_DIR" && shopt -s nullglob && sha256sum ./*.AppImage ./*.zsync > SHA256SUMS )
cat "$OUT_DIR/SHA256SUMS"

# So the caller (CI) can pick these up without re-parsing.
if [ -n "${GITHUB_ENV:-}" ]; then
    echo "KONSOLE_SEMVER=$KONSOLE_SEMVER" >> "$GITHUB_ENV"
fi
echo "$KONSOLE_SEMVER" > "$OUT_DIR/version.txt"
echo "$NEON_DIST" > "$OUT_DIR/dist.txt"
# The build base's own glibc is the ceiling this artifact may require.
getconf GNU_LIBC_VERSION | awk '{print $NF}' > "$OUT_DIR/glibc-max.txt"

# The container runs as root, so without this a bind-mounted dist/ ends up
# root-owned on the host and needs sudo to clean up.
if [ -n "${HOST_UID:-}" ]; then
    chown -R "${HOST_UID}:${HOST_GID:-$HOST_UID}" "$OUT_DIR"
fi

log "Done: $OUTPUT"
ls -lh "$OUTPUT"
