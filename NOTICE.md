# Notice

## Not affiliated with KDE

This is an **unofficial, community-built** AppImage. It is not produced,
endorsed, supported or reviewed by KDE e.V. or the Konsole maintainers.

"Konsole", "KDE" and "KDE neon" are trademarks of KDE e.V. They are used here
only to identify the software being packaged.

If you want an officially supported Konsole, use your distribution's package,
the [Flathub build](https://flathub.org/apps/org.kde.konsole), or the Snap.
Upstream does not ship an AppImage.

## What is bundled

The AppImage contains unmodified binaries from
[KDE neon's](https://neon.kde.org/) `noble` archive:

- Konsole
- KDE Frameworks 6
- Qt 6
- their transitive library dependencies

No patches are applied. The build only repackages what neon publishes.

Each release's `manifest.txt` records the exact package versions used, so any
build can be reproduced or audited.

## Licences

The bundled software is covered by its own licences — predominantly GPL-2+,
LGPL-2.1+, LGPL-3, MIT and BSD. The copyright file for every bundled package is
included inside the AppImage:

```sh
./Konsole-*.AppImage --appimage-extract
ls squashfs-root/usr/share/doc/*/copyright
```

The build scripts in this repository are MIT licensed. See `LICENSE`.

## Written offer of source

Konsole and the KDE Frameworks are licensed under the GPL and LGPL, which
require that corresponding source be made available.

The binaries in these AppImages are unmodified packages from KDE neon. Their
corresponding source is published by KDE neon and can be obtained with the exact
versions listed in the release's `manifest.txt`:

```sh
# add the neon archive (see build/build-appimage.sh), then:
apt-get source konsole=<version-from-manifest>
```

Sources are also available from:

- KDE neon archive — <https://archive.neon.kde.org/>
- Konsole upstream — <https://invent.kde.org/utilities/konsole>
- KDE Frameworks — <https://invent.kde.org/frameworks>
- Qt 6 — <https://code.qt.io/cgit/qt/qtbase.git/>

If you cannot obtain the corresponding source through the above, open an issue
on this repository and it will be provided.

## LGPL relinking

The AppImage is a squashfs image and can be unpacked with
`--appimage-extract`, its libraries replaced, and repacked with
[`appimagetool`](https://github.com/AppImage/appimagetool). This satisfies the
LGPL requirement that users be able to relink against modified library versions.

## No warranty

Provided as-is, with no warranty of any kind. You run it at your own risk.
