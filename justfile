# Konsole AppImage -- build, test and release recipes
#
# `just` on its own lists everything below.

BLUE  := '\033[1;34m'
GREEN := '\033[1;32m'
RED   := '\033[1;31m'
DIM   := '\033[2m'
BOLD  := '\033[1m'
NC    := '\033[0m'

IMAGE       := 'ubuntu:24.04'
DIST        := 'dist'
NEON        := env('NEON_CHANNEL', 'user')
INSTALL_DIR := env('INSTALL_DIR', env('HOME') / 'AppImages')
REPO        := 'thereisnotime/konsole-appimage'

# Show all recipes, grouped
[private]
default:
    @printf '\n{{BOLD}}Konsole AppImage{{NC}}  {{DIM}}build / test / release{{NC}}\n\n'
    @just --list --list-heading '' --list-prefix '  '
    @printf '\n{{DIM}}Everything builds in a %s container. Your system Qt is never touched.{{NC}}\n' '{{IMAGE}}'
    @printf '{{DIM}}Start with:{{NC}} just build {{DIM}}then{{NC}} just test\n\n'

# ---------------------------------------------------------------- build ------

# Build the AppImage (container; ~5 min, ~1.5 GB of downloads)
[group('build')]
build:
    @printf '{{BLUE}}==>{{NC}} Building from KDE neon channel {{BOLD}}{{NEON}}{{NC}}\n'
    docker run --rm -v "$PWD:/work" -w /work \
        -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
        -e NEON_CHANNEL='{{NEON}}' \
        {{IMAGE}} bash /work/build/build-appimage.sh
    @just _built

# Build exactly as CI does (stable-named copy + zsync update info)
[group('build')]
build-release:
    @printf '{{BLUE}}==>{{NC}} Release build (stable copy + zsync)\n'
    docker run --rm -v "$PWD:/work" -w /work \
        -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
        -e NEON_CHANNEL='{{NEON}}' \
        -e STABLE_COPY=1 \
        -e UPDATE_INFO='gh-releases-zsync|thereisnotime|konsole-appimage|latest|Konsole-*-x86_64.AppImage.zsync' \
        {{IMAGE}} bash /work/build/build-appimage.sh
    @just _built

# Remove build output
[group('build')]
clean:
    rm -rf {{DIST}} squashfs-root
    @printf '{{GREEN}}cleaned{{NC}}\n'

[private]
_built:
    @printf '\n{{GREEN}}built:{{NC}}\n'
    @ls -lh {{DIST}}/ | tail -n +2 | awk '{printf "  %-42s %s\n", $9, $5}'

# ----------------------------------------------------------------- test ------

# Verify the built AppImage (runs, no env leaks, deps complete)
[group('test')]
test:
    @bash build/smoke-test.sh {{DIST}}

# Verify in a bare container, the way a clean machine would see it
[group('test')]
test-clean:
    @printf '{{BLUE}}==>{{NC}} Testing in a bare {{IMAGE}} (no desktop libraries preinstalled)\n'
    docker run --rm -v "$PWD:/work" -w /work {{IMAGE}} bash -c '\
        export DEBIAN_FRONTEND=noninteractive; \
        apt-get update -qq >/dev/null 2>&1; \
        apt-get install -y -qq $(cat build/host-deps.txt | tr "\n" " ") >/dev/null 2>&1; \
        bash build/smoke-test.sh {{DIST}}'

# List libraries the AppImage expects from the host
[group('test')]
host-deps:
    #!/usr/bin/env bash
    set -euo pipefail
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    ( cd "$tmp" && APPIMAGE_EXTRACT_AND_RUN=1 "$OLDPWD"/{{DIST}}/Konsole-*-x86_64.AppImage --appimage-extract >/dev/null )
    printf '{{BOLD}}%s{{NC}}\n' "libraries that must come from the host:"
    find "$tmp/squashfs-root/usr" -type f \( -name '*.so*' -o -name konsole \) \
        -exec objdump -p {} \; 2>/dev/null | awk '/NEEDED/{print $2}' | sort -u \
    | while read -r l; do [ -e "$tmp/squashfs-root/usr/lib/$l" ] || echo "  $l"; done

# --------------------------------------------------------------- install -----

# Install the locally built AppImage to INSTALL_DIR
[group('install')]
install:
    #!/usr/bin/env bash
    set -euo pipefail
    f=$(ls {{DIST}}/Konsole-*-x86_64.AppImage 2>/dev/null | head -1) \
        || { printf '{{RED}}no build found -- run `just build`{{NC}}\n'; exit 1; }
    mkdir -p '{{INSTALL_DIR}}'
    install -m 0755 "$f" '{{INSTALL_DIR}}/'
    printf '{{GREEN}}installed{{NC}} %s\n' "{{INSTALL_DIR}}/$(basename "$f")"

# Install the latest published release (what users run)
[group('install')]
install-release:
    curl -fsSL https://raw.githubusercontent.com/{{REPO}}/master/install.sh | bash

# Run the locally built AppImage
[group('install')]
run:
    @{{DIST}}/Konsole-*-x86_64.AppImage

# --------------------------------------------------------------- release -----

# Trigger the GitHub build (channel=user|testing|unstable)
[group('release')]
ci-build channel=NEON:
    gh workflow run build-appimage.yml -f neon_channel={{channel}} -f publish_release=false
    @printf '{{DIM}}watch with: just ci-watch{{NC}}\n'

# Trigger a GitHub build and publish a release
[group('release')]
ci-release channel=NEON:
    gh workflow run build-appimage.yml -f neon_channel={{channel}} -f publish_release=true
    @printf '{{DIM}}watch with: just ci-watch{{NC}}\n'

# Watch the most recent CI run
[group('release')]
ci-watch:
    @gh run watch $(gh run list --limit 1 --json databaseId -q '.[0].databaseId')

# Show why the last CI run failed
[group('release')]
ci-log:
    @gh run view $(gh run list --limit 1 --json databaseId -q '.[0].databaseId') --log-failed

# List published releases
[group('release')]
releases:
    @gh release list

# ------------------------------------------------------------------ spec -----

# Show OpenSpec change status
[group('spec')]
spec:
    @openspec list

# Validate the OpenSpec change
[group('spec')]
spec-validate:
    @openspec validate build-konsole-appimage

# Lint the shell scripts (needs shellcheck)
[group('spec')]
lint:
    @shellcheck build/*.sh install.sh && printf '{{GREEN}}shellcheck clean{{NC}}\n'
