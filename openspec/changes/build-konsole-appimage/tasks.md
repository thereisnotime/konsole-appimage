# Tasks

## 1. Build script

- [x] 1.1 Add neon apt repo with keyring inside an `ubuntu:24.04` container
- [x] 1.2 Install `konsole` and `breeze-icon-theme` from the pinned channel
- [x] 1.3 Fetch `linuxdeploy`, `linuxdeploy-plugin-qt`, `appimagetool`
- [x] 1.4 Assemble the AppDir via `linuxdeploy --plugin qt`
- [x] 1.5 Copy KF6 data (`konsole/`, `kxmlgui*/konsole/`, breeze icons, kf6 plugins)
- [x] 1.6 Write `qt.conf` so Qt plugin paths need no environment variable
- [x] 1.7 Write a custom `AppRun` exporting only `XDG_DATA_DIRS` and an empty
      `QT_QPA_PLATFORMTHEME`
- [x] 1.8 Emit a manifest of resolved package versions
- [x] 1.9 Package with `appimagetool`

## 2. CI pipeline

- [x] 2.1 `workflow_dispatch` workflow with channel and release inputs
- [x] 2.2 Run the build in a container, package on the runner
- [x] 2.3 Upload the AppImage as a workflow artifact
- [x] 2.4 Optionally attach it to a GitHub release

## 3. Verification

- [x] 3.1 Smoke-test locally: AppImage starts under Plasma 5.27
      (`konsole 26.08.0`, GUI launch on X11, exit 0)
- [x] 3.2 Confirm no env leak: `LD_LIBRARY_PATH`, `QT_PLUGIN_PATH`,
      `QML2_IMPORT_PATH`, `LD_PRELOAD` all absent in the spawned shell
- [x] 3.3 Confirm `ldd` of a host binary run from the spawned shell resolves to
      system libraries, not the bundle (`ls` -> `/lib/x86_64-linux-gnu/...`)
- [x] 3.4 Confirm host toolchain reachable (`kubectl`, `docker`, `gh` on PATH)
- [x] 3.5 Confirm max required glibc is 2.38, below the 2.39 target
- [x] 3.6 Confirm it runs headless and on a clean machine (bare container with
      only build/host-deps.txt: all 12 checks pass)
- [x] 3.7 Confirm the published install path works end to end (install.sh from
      a clean HOME: download, checksum, desktop entry, runs)
- [x] 3.8 Confirm the View -> Split View menu is present (manual: confirmed
      working in the bundled Konsole 26.08)
- [x] 3.9 Confirm Wayland works on a real session (manual: confirmed)
- [x] 3.10 Confirm host Qt6 apps still start (trivially: nothing was ever
      installed on the host; system Qt6 remains 6.4.2)
- [x] 3.11 Confirm the published artifact matches the local build
      (sha256sum -c against releases/latest: OK)

## 4. Publish

- [x] 4.1 Create the public GitHub repo and push
      (github.com/thereisnotime/konsole-appimage)
- [x] 4.2 Run the pipeline once manually and attach the first release
      (run 34522024754 green; v26.08.0 with AppImage, stable copy, zsync,
      SHA256SUMS and manifest)
- [x] 4.3 `openspec archive build-konsole-appimage --skip-specs -y`
