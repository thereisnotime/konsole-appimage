# Konsole AppImage

Current [Konsole](https://apps.kde.org/konsole/) as a single self-contained
file, for distributions whose packaged Konsole is years behind.

Built from [KDE neon](https://neon.kde.org/) packages on an Ubuntu 24.04 base,
so it runs on any glibc 2.38+ system without touching the host's Qt or KDE
libraries.

> **Unofficial build.** Not affiliated with or endorsed by KDE. See
> [NOTICE.md](NOTICE.md).

## Quickstart

```sh
curl -fsSL https://raw.githubusercontent.com/thereisnotime/konsole-appimage/master/install.sh | bash
```

Downloads the latest release, verifies its SHA256, installs to `~/AppImages/`
and adds a desktop entry. No root, no package manager, no repository to add.

```sh
INSTALL_DIR=~/bin ./install.sh      # somewhere else
VERSION=v26.08.0  ./install.sh      # a specific release
NO_DESKTOP=1      ./install.sh      # skip the .desktop entry
```

Prefer to pipe nothing into a shell? Reasonable. Grab it directly:

```sh
curl -fLO https://github.com/thereisnotime/konsole-appimage/releases/latest/download/Konsole-x86_64.AppImage
curl -fLO https://github.com/thereisnotime/konsole-appimage/releases/latest/download/SHA256SUMS
sha256sum -c SHA256SUMS --ignore-missing
chmod +x Konsole-x86_64.AppImage
./Konsole-x86_64.AppImage
```

or with wget:

```sh
wget https://github.com/thereisnotime/konsole-appimage/releases/latest/download/Konsole-x86_64.AppImage
chmod +x Konsole-x86_64.AppImage && ./Konsole-x86_64.AppImage
```

Versioned filenames (`Konsole-26.08.0-x86_64.AppImage`) are published alongside
the stable one on every [release](../../releases), if you want to keep several
around.

To uninstall, delete the file.

## Updating

Each AppImage embeds zsync update information, so
[AppImageUpdate](https://github.com/AppImage/AppImageUpdate) fetches only the
changed blocks instead of the full ~100 MB:

```sh
AppImageUpdate Konsole-x86_64.AppImage
```

Or just re-run the install command.

## Why this exists

Ubuntu 24.04 LTS ships Konsole 23.08 — roughly three years and nine feature
releases behind current. None of the usual escape hatches work:

| Approach | Outcome |
|---|---|
| `kubuntu-ppa/backports` | publishes Konsole for questing and jammy only. Nothing for noble. |
| Add KDE neon's repo to the host | its `qt6-base` replaces Ubuntu's Qt6 and removes 26 reverse-dependencies — on a typical desktop that means VirtualBox, Wireshark and qBittorrent |
| [Flathub](https://flathub.org/apps/org.kde.konsole) | works, but the shell runs inside the sandbox, so `kubectl`, `docker`, `gh` and anything else on your host `PATH` is invisible |
| Official AppImage | does not exist — upstream ships Flatpak, Snap and distro packages |
| Upgrade the distro | fair, but not always on the table |

An AppImage loads its own Qt6/KF6 into one process while the system stack keeps
serving everything else, and it is not sandboxed, so the shell you get is a
normal shell.

## What makes this different from a generic AppImage

**The bundle does not leak into your shell.**

A terminal emulator spawns a login shell that inherits its environment. The
usual AppImage recipe exports `LD_LIBRARY_PATH` and `QT_PLUGIN_PATH`, which
would then follow every command you type and break unrelated host binaries
launched from that window.

This build avoids that. Libraries resolve through `RPATH` (`$ORIGIN/../lib`) and
Qt paths through a `qt.conf` beside the binary. Only two variables are exported,
both additive and harmless:

| Variable | Why |
|---|---|
| `XDG_DATA_DIRS` | KF6 icon and resource lookup; prepends, keeps your existing entries |
| `QT_QPA_PLATFORMTHEME` (empty) | stops a Plasma 5 session pushing its Qt5 platform-theme plugin into this Qt6 process, which crashes it |

Verified on a Plasma 5.27 host:

```
LD_LIBRARY_PATH   absent
QT_PLUGIN_PATH    absent
QML2_IMPORT_PATH  absent
LD_PRELOAD        absent

$ ldd $(command -v ls)      # from inside the bundled Konsole
libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6        # system, not the bundle
```

## Compatibility

| | |
|---|---|
| Requires | glibc **2.38+** (current build) or **2.35+** (legacy build), x86_64 |
| Session | X11 and Wayland (both verified) |
| Tested on | Ubuntu 24.04 LTS, Plasma 5.27, X11 and Wayland |
| Host Qt6 | untouched — runs fine alongside Qt6 6.4.2 |
| Size | ~103 MB |

Runs on a Plasma 5 desktop, a Plasma 6 desktop, GNOME, or headless.

### Two builds

Konsole 26.08 needs Qt 6.11, which KDE neon only builds for noble (glibc 2.39).
Ubuntu 22.04 has glibc 2.35 and cannot load those binaries at all:

```
libc.so.6: version `GLIBC_2.38' not found (required by libQt6Gui.so.6)
```

So there are two builds, from neon's two archives:

| Build | Konsole | Requires | Typical systems |
|---|---|---|---|
| `Konsole-x86_64.AppImage` | 26.08.0 | glibc **2.38+** | Ubuntu 24.04+, Debian 13+, Fedora 39+, rolling |
| `Konsole-jammy-x86_64.AppImage` | 24.08.1 | glibc **2.35+** | Ubuntu 22.04 |

`install.sh` detects your glibc and downloads the right one — you do not need to
choose. Force it with `BUILD=current` or `BUILD=legacy` if you want to.

Even the legacy build is a year newer than the 23.08 Ubuntu 24.04 ships, and
several years newer than what 22.04 has.

Anything older than glibc 2.35 is out of scope.

## Configuration

The AppImage reads the same configuration as a system Konsole:
`~/.config/konsolerc` and `~/.local/share/konsole/`. Existing profiles and
colour schemes are picked up automatically.

If the menubar is missing, press `Ctrl+Shift+M` — recent Konsole hides it by
default in favour of the hamburger menu. Split View then lives under
**View → Split View**.

## Building it yourself

Trigger **Build Konsole AppImage** from the Actions tab. Inputs:

| Input | Meaning |
|---|---|
| `neon_channel` | `user` (stable), `testing`, or `unstable` |
| `targets` | `both`, `current` (noble only), or `legacy` (jammy only) |
| `publish_release` | also attach the results to a GitHub release |

Or locally. There is a `justfile`; run `just` to see everything:

```sh
just build          # current build (noble base)
just build-legacy   # legacy build (jammy base, runs on 22.04)
just build-all      # both, exactly as CI does
just test           # verify the current build
just test-legacy    # verify the legacy build and run it on a real 22.04
just test-clean     # verify in a bare container, as a clean machine sees it
just install        # install to ~/AppImages
just host-deps      # list what the bundle expects from the host
just ci-release     # trigger a GitHub build and publish
```

Without `just`:

```sh
docker run --rm -v "$PWD:/work" -w /work \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
  ubuntu:24.04 bash /work/build/build-appimage.sh
```

Output lands in `dist/` with a `manifest.txt` recording every resolved package
version.

> Run the build in a container. The script adds KDE neon's apt repository, which
> will replace the entire Qt6 stack of whatever system it runs on.

## How it works

1. Start from `ubuntu:24.04`. AppImages must be built against a glibc no newer
   than the oldest host they target — building on Arch or Fedora produces a
   binary that silently refuses to start on Ubuntu 24.04.
2. Add KDE neon's `noble` archive, which publishes current Konsole built against
   that same base. Nothing is compiled.
3. `linuxdeploy` resolves the ELF closure and rewrites RPATHs;
   `linuxdeploy-plugin-qt` bundles Qt plugins, QML and translations.
4. Copy the KDE data files `linuxdeploy` knows nothing about, write `qt.conf`
   and a deliberately minimal `AppRun`, then pack with `appimagetool`.

Full rationale, including the alternatives that were rejected and why, is in
[`openspec/changes/build-konsole-appimage/design.md`](openspec/changes/build-konsole-appimage/design.md).

## Licence

Build scripts: MIT ([LICENSE](LICENSE)).
Bundled software: its own licences, all included in the image. See
[NOTICE.md](NOTICE.md) for redistribution details and the offer of source.
