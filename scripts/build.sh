#!/usr/bin/env bash
# Builds and packages a static musl c2patool for one version. The target is the
# architecture of this machine, because the build container is never emulated.
#
# Usage: scripts/build.sh <version> [outdir]
#
# Exit code 75 means crates.io does not have this version yet. Try again later.
# Every other non-zero exit is a real failure.

set -euo pipefail

VERSION_INPUT="${1:?usage: build.sh <version> [outdir]}"
OUTDIR="${2:-dist}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/config.sh
. "${REPO_ROOT}/scripts/config.sh"

VERSION="$(normalize_version "$VERSION_INPUT")"
TAG="$(tag_for "$VERSION")"
TARGET="${TARGET:-$(target_for_host_arch)}"
ARCHIVE="$(archive_for "$VERSION" "$TARGET")"
REPO_URL="${REPO_URL:-https://github.com/reload/c2patool-musl}"

EXIT_NOT_ON_CRATES_IO=75

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$OUTDIR"
OUTDIR="$(cd "$OUTDIR" && pwd)"

# Same for every target, so a multi-target caller fetches them once and passes
# the directory in.
if [ -n "${AUX_DIR:-}" ]; then
    AUX_DIR="$(cd "$AUX_DIR" && pwd)"
else
    AUX_DIR="${WORK}/aux"
    "${REPO_ROOT}/scripts/fetch-aux.sh" "$VERSION" "$AUX_DIR"
fi

echo "==> Building c2patool ${VERSION} for ${TARGET} in ${RUST_IMAGE}"
mkdir -p "${WORK}/out" "${WORK}/build"
STATUS=0
docker run --rm \
    -e HOST_UID="$(id -u)" \
    -e HOST_GID="$(id -g)" \
    -e UPSTREAM_URL="$UPSTREAM_URL" \
    -e TAG_PREFIX="$TAG_PREFIX" \
    -v "${REPO_ROOT}/scripts/build-in-container.sh:/build-in-container.sh:ro" \
    -v "${WORK}/out:/out" \
    -v "${WORK}/build:/build" \
    -w /build \
    "$RUST_IMAGE" \
    /build-in-container.sh "$VERSION" "$TARGET" || STATUS=$?

if [ "$STATUS" -eq "$EXIT_NOT_ON_CRATES_IO" ]; then
    echo "==> ${TAG} is tagged upstream but is not on crates.io yet. Nothing was built."
    exit "$EXIT_NOT_ON_CRATES_IO"
fi
if [ "$STATUS" -ne 0 ]; then
    exit "$STATUS"
fi

# Read as data, never sourced: that container ran upstream build scripts as root.
INFO="${WORK}/out/build-info.json"
read_info() { jq -er --arg k "$1" '.[$k] | tostring' "$INFO"; }

BUILT_TARGET="$(read_info target)"
RUSTC_VERSION="$(read_info rustc)"
BUILD_SOURCE="$(read_info build_source)"
BUILD_SOURCE_KIND="$(read_info build_source_kind)"

if [ "$BUILT_TARGET" != "$TARGET" ]; then
    echo "error: the container built ${BUILT_TARGET}, but ${TARGET} was expected." >&2
    exit 1
fi

# The fallback keeps producing releases, so a rotting tag build must be loud.
if [ "$BUILD_SOURCE_KIND" = "crates-io" ]; then
    echo "::warning::The tag build failed and ${TAG} was built from crates.io instead. Check whether the tag build is broken."
fi

echo "==> Packaging ${ARCHIVE}"
mkdir -p "${WORK}/stage/c2patool"
cp -a "${AUX_DIR}/." "${WORK}/stage/c2patool/"
rm -f "${WORK}/stage/c2patool/.aux-source"
install -m 0755 "${WORK}/out/c2patool" "${WORK}/stage/c2patool/c2patool"

FILE_OUTPUT="$(file -b "${WORK}/stage/c2patool/c2patool")"

cat > "${WORK}/stage/c2patool/MUSL-BUILD.txt" <<INFO
This archive is not an official ContentAuth distribution.

It contains c2patool ${VERSION}, compiled from unmodified upstream source for
${TARGET}. Every other file in this archive is the file that
upstream shipped in ${TAG}.

Upstream project: ${UPSTREAM_URL}
Upstream tag:     ${TAG}
Built from:       ${BUILD_SOURCE}
Compiler:         ${RUSTC_VERSION}
Target:           ${TARGET}
Built by:         ${REPO_URL}
INFO

# Sorted names and no timestamps, so two builds give the same bytes.
tar --sort=name --mtime="@0" --owner=0 --group=0 --numeric-owner \
    -C "${WORK}/stage" -cf - c2patool | gzip -9n > "${OUTDIR}/${ARCHIVE}"

# The host adds what only the host knows.
jq --arg archive "$ARCHIVE" \
   --arg file_output "$FILE_OUTPUT" \
   --arg rust_image "$RUST_IMAGE" \
   --arg tag "$TAG" \
   '. + {archive: $archive, file_output: $file_output, rust_image: $rust_image, upstream_tag: $tag}' \
   "$INFO" > "${OUTDIR}/build-info-${TARGET}.json"

echo "==> Done"
ls -l "${OUTDIR}/${ARCHIVE}"
