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
- [ ] 3.6 Confirm the View -> Split View menu is present (manual, needs a human
      at the GUI)
- [ ] 3.7 Confirm host Qt6 apps (VirtualBox, Wireshark) still start
      (expected trivially: nothing was installed on the host)

## 4. Publish

- [ ] 4.1 Create the public GitHub repo and push
- [ ] 4.2 Run the pipeline once manually and attach the first release
- [ ] 4.3 `openspec archive build-konsole-appimage --skip-specs -y`
