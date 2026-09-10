# Build a self-contained Konsole AppImage

## Why

Ubuntu 24.04 LTS (noble) ships Konsole 23.08.5, which is three years and roughly
nine feature releases behind current stable (26.08.x). There is no supported way
to get a newer Konsole natively on this OS:

- `ppa:kubuntu-ppa/backports` publishes `konsole` only for questing (25.10) and
  jammy. Nothing for noble.
- KDE neon's noble repo *does* carry `konsole 26.08.0`, but its `qt6-base`
  metapackage declares `Breaks`/`Replaces` on every Ubuntu Qt6 package
  `<< 6.8.1`, and does not `Provides:` their names. Noble ships Qt6 6.4.2.
  Installing it removes 26 reverse-dependencies, including **VirtualBox 7.1,
  Wireshark and qBittorrent**. Unacceptable collateral for a terminal.
- The Flathub build works but sandboxes the shell, so the host toolchain
  (`kubectl`, `docker`, `gh`, the `xx*` toolbelt) is off `PATH`. Useless as a
  primary terminal.
- No official Konsole AppImage exists. Upstream ships Flatpak, Snap and distro
  packages only.

An AppImage carries its own Qt6/KF6 inside a single process while the system Qt6
keeps serving everything else. It is also not sandboxed, so the shell it spawns
sees the real `PATH`. That is the only option that satisfies both constraints.

## What Changes

- Add a build script that assembles a Konsole AppImage from KDE neon's noble
  packages inside a disposable `ubuntu:24.04` container.
- Add a manually-triggered GitHub Actions workflow (`workflow_dispatch`) that
  runs the same script and publishes the artifact, optionally as a release.
- Pin the build base to noble so the produced binary matches Ubuntu 24.04's
  glibc 2.39 and does not require a newer loader than the target hosts have.

## Impact

- Affected specs: `appimage-build` (new)
- Affected code: `build/`, `.github/workflows/`
- No change to any host system. The AppImage is a single file, removed with `rm`.
