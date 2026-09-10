# appimage-build

## ADDED Requirements

### Requirement: Reproducible build base

The build SHALL run inside an `ubuntu:24.04` container so the produced AppImage
links against glibc 2.39 or older.

#### Scenario: Build runs on a newer host

- **WHEN** the build is invoked from a machine running a distribution newer than
  Ubuntu 24.04
- **THEN** the build still executes inside the `ubuntu:24.04` container
- **AND** the resulting AppImage starts on an Ubuntu 24.04 host

#### Scenario: Resolved versions are recorded

- **WHEN** a build completes
- **THEN** the resolved `konsole`, `qt6-base` and KF6 versions are written to a
  manifest alongside the AppImage

### Requirement: Self-contained Qt6 and KF6

The AppImage SHALL bundle its own Qt6 and KF6 libraries and SHALL NOT require
any Qt6 or KF6 package to be installed on the host.

#### Scenario: Host has an older Qt6

- **WHEN** the AppImage runs on a host with Qt6 6.4.2 installed
- **THEN** Konsole loads its bundled Qt6 6.11
- **AND** the host's Qt6 applications continue to use the system Qt6

#### Scenario: Host has no Qt6 at all

- **WHEN** the AppImage runs on a host with no Qt6 packages installed
- **THEN** Konsole starts normally

### Requirement: Environment isolation for spawned shells

The AppImage SHALL NOT export `LD_LIBRARY_PATH` or `QT_PLUGIN_PATH` into the
environment of the shell it spawns.

#### Scenario: Running a host binary from the terminal

- **WHEN** a user launches the AppImage and runs a dynamically linked host
  binary from the resulting shell
- **THEN** that binary resolves its libraries from the system, not the bundle
- **AND** it runs exactly as it would from a system terminal

#### Scenario: Host toolchain is reachable

- **WHEN** a user runs `kubectl`, `docker` or an `xx*` toolbelt command from the
  spawned shell
- **THEN** the command is found on the host `PATH`

### Requirement: Complete KDE resources

The AppImage SHALL bundle the KF6 data files Konsole needs at runtime.

#### Scenario: Split View is reachable

- **WHEN** a user opens the menubar in the bundled Konsole
- **THEN** the View menu is present and contains the Split View submenu

#### Scenario: Icons render

- **WHEN** the bundled Konsole displays its toolbar and menus
- **THEN** icons render rather than appearing blank

### Requirement: Plasma 5 session compatibility

The AppImage SHALL start correctly under a Plasma 5 session.

#### Scenario: Session sets a Qt5 platform theme

- **WHEN** the AppImage is launched from a Plasma 5.27 session that exports
  `QT_QPA_PLATFORMTHEME`
- **THEN** the bundled Konsole neutralises it and starts without attempting to
  load the host's Qt5 platform-theme plugin

### Requirement: Manual pipeline trigger

The repository SHALL provide a GitHub Actions workflow triggered manually via
`workflow_dispatch`.

#### Scenario: Operator triggers a build

- **WHEN** an operator dispatches the workflow
- **THEN** the AppImage is built and uploaded as a downloadable artifact

#### Scenario: Operator requests a release

- **WHEN** an operator dispatches the workflow with the release input enabled
- **THEN** the AppImage is additionally attached to a GitHub release tagged with
  the built Konsole version
