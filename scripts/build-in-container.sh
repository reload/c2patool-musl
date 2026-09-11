#!/bin/sh
# Builds a static musl c2patool from unmodified upstream source.
# Runs inside the pinned rust alpine image. Writes the stripped binary and
# build-info.env to /out.
#
# Usage: build-in-container.sh <version>

set -eu

VERSION="${1:?usage: build-in-container.sh <version>}"

# Everything under /out and /build is written by root inside this container.
# The ownership is handed back, so that the host can read and delete the files.
give_files_back() {
    if [ -n "${HOST_UID:-}" ]; then
        chown -R "${HOST_UID}:${HOST_GID}" /out /build 2>/dev/null || true
    fi
}
trap give_files_back EXIT
TAG="c2patool-v${VERSION}"
GIT_URL="https://github.com/contentauth/c2pa-rs"
WANT_TARGET="x86_64-unknown-linux-musl"

# perl and cmake are needed because the dependency tree compiles its own OpenSSL.
apk add --no-cache build-base musl-dev perl cmake pkgconf binutils git >/dev/null

RUSTC_VERSION="$(rustc --version)"
HOST_TARGET="$(rustc -vV | awk '/^host:/ {print $2}')"

# The image must be musl-hosted. A plain cargo install then produces a static
# binary with no cross-compilation setup.
if [ "$HOST_TARGET" != "$WANT_TARGET" ]; then
    echo "error: rustc host target is ${HOST_TARGET}, expected ${WANT_TARGET}" >&2
    exit 1
fi

echo ">>> ${RUSTC_VERSION}, host target ${HOST_TARGET}"

# Primary source is the upstream release tag. The crate is found by package
# name, because upstream moved it from c2patool/ to cli/ and can move it again.
# Never build from a hard-coded path.
BUILD_SOURCE=""
BUILD_SOURCE_KIND=""
echo ">>> building from ${GIT_URL} at tag ${TAG}"
if cargo install --locked --root /build/out --git "$GIT_URL" --tag "$TAG" c2patool; then
    BUILD_SOURCE="${GIT_URL} at tag ${TAG}"
    BUILD_SOURCE_KIND="git-tag"
else
    echo ">>> the tag build failed. Falling back to crates.io." >&2
    rm -rf /build/out
    cargo install --locked --root /build/out --version "$VERSION" c2patool
    BUILD_SOURCE="crates.io c2patool ${VERSION}"
    BUILD_SOURCE_KIND="crates-io"
fi

SIZE_UNSTRIPPED="$(wc -c < /build/out/bin/c2patool | tr -d ' ')"
strip -o /out/c2patool /build/out/bin/c2patool
SIZE_STRIPPED="$(wc -c < /out/c2patool | tr -d ' ')"

# The values are single quoted, because the build script reads this file with
# the shell. A rustc version string contains spaces and brackets.
quote() { printf "%s" "$1" | tr -d "'"; }

cat > /out/build-info.env <<INFO
RUSTC_VERSION='$(quote "$RUSTC_VERSION")'
BUILD_SOURCE='$(quote "$BUILD_SOURCE")'
BUILD_SOURCE_KIND='${BUILD_SOURCE_KIND}'
SIZE_UNSTRIPPED='${SIZE_UNSTRIPPED}'
SIZE_STRIPPED='${SIZE_STRIPPED}'
INFO

echo ">>> built ${SIZE_STRIPPED} bytes stripped, from ${BUILD_SOURCE}"
