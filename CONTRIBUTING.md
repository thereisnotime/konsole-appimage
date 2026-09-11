# Contributing

## What belongs here

This repository packages Konsole. It does not patch it.

- **Packaging problems** belong here: it will not start, a library is missing on
  some distribution, the installer misbehaves, icons or fonts are wrong.
- **Konsole problems** belong at [KDE](https://bugs.kde.org/enter_bug.cgi?product=konsole).
  If the same thing happens with your distribution's Konsole, it is not a
  packaging bug.

## Setting up

You need Docker (or Podman) and [`just`](https://github.com/casey/just). Nothing
else — the build never touches your system.

```sh
just            # list every recipe
just build      # current target (noble base)
just test       # verify it
```

A full build pulls roughly 1.5 GB from KDE neon and takes a few minutes.

## Test locally, not in CI

This is the one rule worth stating outright, because ignoring it wasted four CI
runs early on.

Everything CI does can be run on your machine, in the same container:

```sh
just build-all      # both targets, exactly as CI builds them
just test           # current build
just test-legacy    # legacy build, and runs it on a real Ubuntu 22.04
just test-clean     # in a bare container, as a clean machine sees it
just lint           # shellcheck
```

`just test-clean` is the important one. Your desktop has Qt, KDE libraries and
fonts already installed, so a bundle with a missing dependency will still work
for you and fail for everyone else. Two real bugs — no Wayland platform plugin,
and plugins with no `RPATH` — passed on a developer machine and were only caught
in a bare container.

Open a PR once those pass.

## Things that are easy to get wrong

**The glibc floor is the whole design.** An AppImage must be built against a
glibc no newer than the oldest system it targets. That is why the noble build
uses `ubuntu:24.04` and the jammy build uses `ubuntu:22.04`, and why the build
refuses to run if `NEON_DIST` does not match the container. Building on a newer
base produces something that silently will not start elsewhere.

**Do not export environment variables from `AppRun`.** Konsole hands its
environment to the shell it spawns, so `LD_LIBRARY_PATH` or `QT_PLUGIN_PATH`
would follow every command the user runs and break unrelated host binaries.
Libraries resolve through `RPATH`, Qt paths through `qt.conf`. The smoke test
enforces this.

**Do not bundle GPU-driver-coupled libraries** (`libEGL`, `libGL`, `libGLX`).
They have to match the host's driver. `build/host-deps.txt` is the list of what
we expect the host to provide.

**Anything copied in by hand needs an `RPATH`** and its dependency closure
resolved — `linuxdeploy` only knows about what it deployed itself.

## Adding a distribution target

`NEON_DIST` selects which neon archive to build from. To add one, check the
archive actually has it:

```sh
curl -s http://archive.neon.kde.org/user/dists/ | grep -oE 'href="[a-z]+/"'
```

then add a matrix entry in `.github/workflows/build-appimage.yml` with the
matching container image and a distinct `zsync` asset name. The zsync names must
not overlap, or AppImageUpdate can hand a user a build their glibc cannot load.

## Commits and PRs

Write commit messages that explain *why*, in plain prose. Say what broke and
what it means, not just what changed. No AI-generated filler.

PRs should say what you tested on. "Passes `just test-clean`" is a useful
sentence; "fixed it" is not.

## Specs

Non-trivial changes are tracked with [OpenSpec](https://openspec.dev) under
`openspec/`. `just spec` lists active changes, `just spec-validate` checks them.
