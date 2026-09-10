# konsole-appimage

Builds a self-contained [Konsole](https://apps.kde.org/konsole/) AppImage from
KDE neon's noble packages, so you can run current Konsole on Ubuntu 24.04 LTS
without touching the system Qt6 stack.

## Why

Ubuntu 24.04 ships Konsole 23.08.5 — about three years behind current stable.
There is no clean native upgrade:

| Option | Result |
|---|---|
| `kubuntu-ppa/backports` | publishes `konsole` for questing and jammy only, nothing for noble |
| KDE neon repo on the host | its `qt6-base` replaces Ubuntu's Qt6 6.4.2 and removes 26 reverse-deps, including VirtualBox, Wireshark and qBittorrent |
| Flathub | works, but sandboxes the shell — no `kubectl`, `docker`, `gh` on `PATH` |
| Official AppImage | does not exist; upstream ships Flatpak, Snap and distro packages |

An AppImage loads its own Qt6/KF6 into one process while the system Qt6 keeps
serving everything else, and it is not sandboxed, so the shell sees the real
`PATH`.

## Usage

Download the AppImage from
[Releases](../../releases), then:

```sh
chmod +x Konsole-*.AppImage
./Konsole-*.AppImage
```

## Building

Trigger **Build Konsole AppImage** from the Actions tab (`workflow_dispatch`).
Inputs:

- `neon_channel` — `user` (stable), `testing`, or `unstable`
- `publish_release` — also attach the result to a GitHub release

Locally, with Docker:

```sh
docker run --rm -v "$PWD:/work" -w /work ubuntu:24.04 \
  bash /work/build/build-appimage.sh
```

Output lands in `dist/`, along with a `manifest.txt` recording the resolved
Konsole, Qt6 and KF6 versions.

> Run the build in a container. The script adds KDE neon's apt repo, which will
> replace the entire Qt6 stack of whatever system it runs on.

## Design notes

The build base is pinned to `ubuntu:24.04` on purpose. AppImages must be built
against a glibc no newer than the oldest host they target; building on Arch or
Fedora produces a binary that silently refuses to start on Ubuntu 24.04.

The `AppRun` is deliberately minimal. Konsole spawns a login shell that inherits
its environment, so exporting `LD_LIBRARY_PATH` or `QT_PLUGIN_PATH` — what a
typical AppImage does — would follow every command you run and break host
binaries launched from that window. Libraries resolve via `RPATH` and Qt paths
via `qt.conf` instead. Only `XDG_DATA_DIRS` (additive) and an empty
`QT_QPA_PLATFORMTHEME` are exported; the latter stops a Plasma 5 session from
pushing its Qt5 platform-theme plugin into this Qt6 process.

See `openspec/changes/build-konsole-appimage/design.md` for the full rationale.
