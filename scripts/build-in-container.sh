#!/bin/sh
# Builds a static musl c2patool from unmodified upstream source. Runs inside the
# pinned rust alpine image. Writes the binary and build-info.json to /out.
#
# Usage: build-in-container.sh <version> <expected-target>
# Exit 75: the tag build failed and crates.io does not have this version yet.

set -eu

VERSION="${1:?usage: build-in-container.sh <version> <expected-target>}"
EXPECT_TARGET="${2:?usage: build-in-container.sh <version> <expected-target>}"
UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/contentauth/c2pa-rs}"
TAG_PREFIX="${TAG_PREFIX:-c2patool-v}"
TAG="${TAG_PREFIX}${VERSION}"

EXIT_NOT_ON_CRATES_IO=75

# Root writes /out and /build, so hand the ownership back to the host.
give_files_back() {
    if [ -n "${HOST_UID:-}" ]; then
        chown -R "${HOST_UID}:${HOST_GID}" /out /build 2>/dev/null || true
    fi
}
trap give_files_back EXIT

# perl and cmake are needed because the dependency tree compiles its own OpenSSL.
apk add --no-cache build-base musl-dev perl cmake pkgconf binutils git jq >/dev/null

RUSTC_VERSION="$(rustc --version)"
HOST_TARGET="$(rustc -vV | awk '/^host:/ {print $2}')"

# Must be musl hosted: a plain cargo install then produces a static binary.
case "$HOST_TARGET" in
    *-linux-musl) ;;
    *)
        echo "error: the rustc host target is ${HOST_TARGET}, which is not a musl target." >&2
        exit 1
        ;;
esac

# Catches a runner of the wrong architecture, which would otherwise produce an
# archive with a misleading name.
if [ "$HOST_TARGET" != "$EXPECT_TARGET" ]; then
    echo "error: this container is ${HOST_TARGET}, but ${EXPECT_TARGET} was expected." >&2
    echo "The job is running on a runner of the wrong architecture." >&2
    exit 1
fi

echo ">>> ${RUSTC_VERSION}, host target ${HOST_TARGET}"

# Returns the HTTP status of the crates.io record for this version.
crates_io_status() {
    curl -s -o /dev/null -w '%{http_code}' \
        -H 'User-Agent: reload/c2patool-musl' \
        "https://crates.io/api/v1/crates/c2patool/${VERSION}" || printf '000'
}

# The tag is the source of record. The crate is found by package name, because
# upstream moved it from c2patool/ to cli/ and can move it again.
echo ">>> building from ${UPSTREAM_URL} at tag ${TAG}"
if cargo install --locked --root /build/out --git "$UPSTREAM_URL" --tag "$TAG" c2patool; then
    BUILD_SOURCE="${UPSTREAM_URL} at tag ${TAG}"
    BUILD_SOURCE_KIND="git-tag"
else
    echo ">>> the tag build failed. Looking at crates.io." >&2
    rm -rf /build/out

    STATUS="$(crates_io_status)"
    case "$STATUS" in
        404)
            # A release can appear seconds before its crates.io publish.
            echo ">>> crates.io does not have c2patool ${VERSION} yet." >&2
            exit "$EXIT_NOT_ON_CRATES_IO"
            ;;
        200)
            echo ">>> crates.io has ${VERSION}. Building from there instead." >&2
            ;;
        *)
            # A network or server problem must never look like a missing version.
            echo "error: the crates.io request returned ${STATUS}." >&2
            echo "The tag build failed and crates.io could not be read. This is a real failure." >&2
            exit 1
            ;;
    esac

    cargo install --locked --root /build/out --version "$VERSION" c2patool
    BUILD_SOURCE="crates.io c2patool ${VERSION}"
    BUILD_SOURCE_KIND="crates-io"
fi

SIZE_UNSTRIPPED="$(wc -c < /build/out/bin/c2patool | tr -d ' ')"
strip -o /out/c2patool /build/out/bin/c2patool
SIZE_STRIPPED="$(wc -c < /out/c2patool | tr -d ' ')"

# JSON, not shell: the host must never execute what this container wrote.
jq -n \
    --arg version "$VERSION" \
    --arg target "$HOST_TARGET" \
    --arg rustc "$RUSTC_VERSION" \
    --arg source "$BUILD_SOURCE" \
    --arg source_kind "$BUILD_SOURCE_KIND" \
    --argjson size_stripped "$SIZE_STRIPPED" \
    --argjson size_unstripped "$SIZE_UNSTRIPPED" \
    '{version: $version, target: $target, rustc: $rustc,
      build_source: $source, build_source_kind: $source_kind,
      size_stripped: $size_stripped, size_unstripped: $size_unstripped}' \
    > /out/build-info.json

echo ">>> built ${SIZE_STRIPPED} bytes for ${HOST_TARGET}, from ${BUILD_SOURCE}"
