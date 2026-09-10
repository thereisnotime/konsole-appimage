# Design

## Context

Target hosts run Ubuntu 24.04 LTS: glibc 2.39, `GLIBCXX_3.4.33`, Plasma 5.27
(KF5/Qt5). The AppImage must run there while carrying KF6 6.29 and Qt6 6.11.

## Decision 1: source binaries from KDE neon's noble repo, do not compile

Konsole 26.08 depends on ~16 KF6 frameworks. Building those from source on a
KF5-only host means building all of KDE Frameworks first — days of work and a
permanent maintenance burden.

KDE neon publishes `konsole 4:26.08.0-0zneon+24.04+noble+release+build38` built
*against noble itself*. Same base, same glibc, no ABI risk by construction.

Rejected alternatives:

- **Arch / Fedora / Debian trixie containers.** All have glibc > 2.39. AppImages
  must be built on the *oldest* glibc they need to support; building on a newer
  one produces a binary that refuses to start on the target. This is the single
  most common way AppImage builds fail and it is silent until runtime.
- **`kdeneon/*` Docker Hub images.** Abandoned — last pushed 2023, still on the
  22.04 base with KDE Gear ~23.04.
- **Converting the Flathub build.** Flatpak hardcodes the `/app` prefix and the
  runtime assumes `/usr`; AppImages mount at a random `/tmp/.mount_XXXXXX`.
  That needs `patchelf` RPATH rewriting across every bundled library plus a
  `qt.conf` and an env shim. It is a port, not a conversion, and costs ~6 GB of
  SDK to even attempt.

## Decision 2: minimise environment variables, because this is a terminal

This is the constraint that makes a terminal AppImage different from every other
AppImage, and it is worth stating plainly.

A normal AppImage's `AppRun` exports `LD_LIBRARY_PATH`, `QT_PLUGIN_PATH` and
friends. **Konsole spawns a login shell, and that shell inherits the entire
environment.** Every command run from the terminal would then see the bundle's
`LD_LIBRARY_PATH` pointing at Qt6 6.11, which will break unrelated host binaries
launched from that window. A terminal that quietly poisons its own children is
worse than an old terminal.

So the bundle avoids env vars wherever a static mechanism exists:

| Concern | Mechanism | Leaks to shell? |
|---|---|---|
| Shared libraries | `RPATH` = `$ORIGIN/../lib` (linuxdeploy default) | no |
| Qt plugins, QML | `qt.conf` beside the binary | no |
| KF6 data (`konsoleui.rc`, profiles, icons) | `XDG_DATA_DIRS` | yes, benign |
| Host KF5 platform theme | `QT_QPA_PLATFORMTHEME=` (empty) | yes, benign |

Only two variables survive, and both are additive rather than overriding.
`XDG_DATA_DIRS` merely appends a lookup path; an empty `QT_QPA_PLATFORMTHEME`
only suppresses theme-plugin loading.

`QT_QPA_PLATFORMTHEME` must be neutralised: the session sets it for Plasma 5, and
letting a KF6/Qt6 process inherit it makes Qt attempt to load the host's Qt5
platform-theme plugin into a Qt6 process. That is a crash, not a cosmetic issue.

## Decision 3: `linuxdeploy` for ELF closure, manual copy for KF6 data

`linuxdeploy-plugin-qt` bundles Qt plugins, QML and translations, and rewrites
RPATHs. It knows nothing about KDE Frameworks, so these are copied explicitly:

- `/usr/share/konsole/` — built-in profiles and colour schemes
- `/usr/share/kxmlgui*/konsole/konsoleui.rc` — the menu definition. Without it
  the View menu (and therefore Split View) silently disappears. The directory is
  globbed because KF5 and KF6 disagree on `kxmlgui5` vs `kxmlgui6`.
- `/usr/share/icons/breeze*` — otherwise every toolbar button renders blank
- `qt6/plugins/kf6/` — KIO workers and other dlopened KF6 plugins that are not
  in the executable's `NEEDED` list, so `linuxdeploy` cannot discover them

`konsolepart` is dlopened rather than linked, so it is passed to `linuxdeploy`
explicitly with `-l`.

## Decision 4: build in a container, publish from the runner

The GitHub job runs on `ubuntu-24.04` (already noble) but does the build inside
`docker run ubuntu:24.04`. Two reasons: the runner has a large set of
preinstalled libraries that would otherwise leak into the AppDir and make the
bundle non-reproducible, and the neon repo must never be added to a system whose
Qt6 matters. Packaging and release upload then happen on the runner, where `gh`
and the `actions/*` toolchain are available.

`APPIMAGE_EXTRACT_AND_RUN=1` is set throughout: `linuxdeploy` and `appimagetool`
are themselves AppImages and there is no FUSE inside a container.

## Risks

- **Neon is a rolling target.** A future KF6 bump could change package names.
  The workflow pins the neon channel as an input and records resolved versions
  in the build output so a broken build is diagnosable.
- **KF6 app under a Plasma 5 session** is not a configuration upstream tests.
  Decision 2 covers the known failure; anything else surfaces at smoke-test time.
- Bundling Breeze icons wholesale is ~50 MB of the final size. Trimming is
  possible later but is deliberately not attempted in the first iteration.
