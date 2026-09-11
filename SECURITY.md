# Security

## Reporting a vulnerability

**In the AppImage packaging** (this repository: the build scripts, `install.sh`,
the workflow): open a [private security advisory](../../security/advisories/new).
Please do not open a public issue first.

**In Konsole, Qt or KDE Frameworks themselves**: report to the people who can
fix it, not here.

- Konsole and KDE Frameworks: <https://kde.org/info/security/>
- Qt: <https://www.qt.io/product/security>

This repository does not patch any of that code. A fix has to land upstream,
reach KDE neon's archive, and then a rebuild here picks it up.

## What you are trusting

This is worth being explicit about, because you are running a 100 MB binary
downloaded from the internet.

| | |
|---|---|
| Where the binaries come from | [KDE neon's](https://archive.neon.kde.org/) apt archive, verified against neon's signing key during the build |
| Are they modified? | No. The build unpacks neon's packages and repacks them. No patching, no recompilation. |
| Where the build runs | A throwaway `ubuntu:24.04` / `ubuntu:22.04` container in GitHub Actions, from a public workflow you can read |
| What records it | Every release ships `manifest.txt` with the exact version of every package that went in |
| Integrity | Every release ships `SHA256SUMS`; `install.sh` verifies the download before installing |

So the trust chain is: KDE neon's archive, GitHub Actions, and whoever controls
this repository. If you do not want to extend that trust, build it yourself with
`just build` and compare the result, or use your distribution's Konsole.

## Verifying a download

```sh
curl -fLO https://github.com/thereisnotime/konsole-appimage/releases/latest/download/Konsole-x86_64.AppImage
curl -fLO https://github.com/thereisnotime/konsole-appimage/releases/latest/download/SHA256SUMS
sha256sum -c SHA256SUMS --ignore-missing
```

`install.sh` does this for you and refuses to install on a mismatch.

## Not currently done

Stated plainly so nobody assumes otherwise:

- **The AppImages are not GPG signed.** Integrity rests on `SHA256SUMS` served
  over HTTPS from GitHub Releases. If you need signed artifacts, say so in an
  issue.
- **Builds are not reproducible.** Two builds a week apart will differ, because
  neon's archive moves. `manifest.txt` records what went into a given build, but
  you cannot currently rebuild a past release byte for byte.

## The AppImage is not a sandbox

AppImages are not sandboxed, and this one deliberately is not:

- It runs with your full user privileges.
- The shell it spawns is a normal shell with your real `PATH` and your real
  environment.

That is the entire point of it — a sandboxed terminal cannot see `kubectl`,
`docker` or anything else on your `PATH`, which is why the Flatpak build is
unsuitable as a primary terminal. But it does mean this offers no isolation
whatsoever. Treat it exactly as you would your distribution's Konsole.
