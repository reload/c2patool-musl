#!/usr/bin/env bash
# Builds and packages a static musl c2patool for one upstream version.
# Produces the release assets in the output directory.
#
# Usage: scripts/build.sh <version> [outdir]
# Example: scripts/build.sh 0.27.22 dist

set -euo pipefail

VERSION="${1:?usage: build.sh <version> [outdir]}"
OUTDIR="${2:-dist}"
RUST_IMAGE="${RUST_IMAGE:-rust:1.98.1-alpine3.24}"

TARGET="x86_64-unknown-linux-musl"
TAG="c2patool-v${VERSION}"
UPSTREAM_REPO="contentauth/c2pa-rs"
ARCHIVE="c2patool-v${VERSION}-${TARGET}.tar.gz"
LATEST_ARCHIVE="c2patool-${TARGET}.tar.gz"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$OUTDIR"
OUTDIR="$(cd "$OUTDIR" && pwd)"

curl_gh() {
    # Uses GITHUB_TOKEN when it is set, to raise the API rate limit.
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        curl -fsSL -H "Authorization: Bearer ${GITHUB_TOKEN}" "$@"
    else
        curl -fsSL "$@"
    fi
}

echo "==> Building c2patool ${VERSION} for ${TARGET} in ${RUST_IMAGE}"
mkdir -p "${WORK}/out" "${WORK}/build"
docker run --rm \
    -v "${REPO_ROOT}/scripts:/scripts:ro" \
    -v "${WORK}/out:/out" \
    -v "${WORK}/build:/build" \
    -w /build \
    "$RUST_IMAGE" \
    /scripts/build-in-container.sh "$VERSION"

# shellcheck disable=SC1091
set -a; . "${WORK}/out/build-info.env"; set +a

echo "==> Fetching the upstream release archive for the sample files"
# The asset name is read from the API, because upstream changed the naming
# convention. Release 0.10.2 used a doubled c2patool- prefix.
ASSET_URL="$(curl_gh "https://api.github.com/repos/${UPSTREAM_REPO}/releases/tags/${TAG}" \
    | jq -r '.assets[] | select(.name | endswith("x86_64-unknown-linux-gnu.tar.gz")) | .browser_download_url' \
    | head -n 1)"

if [ -z "$ASSET_URL" ] || [ "$ASSET_URL" = "null" ]; then
    echo "error: the upstream release ${TAG} has no x86_64-unknown-linux-gnu archive." >&2
    echo "The sample files for the smoke test come from that archive." >&2
    exit 1
fi

curl -fsSL -o "${WORK}/upstream.tar.gz" "$ASSET_URL"
mkdir -p "${WORK}/stage"
tar xzf "${WORK}/upstream.tar.gz" -C "${WORK}/stage"

if [ ! -f "${WORK}/stage/c2patool/c2patool" ]; then
    echo "error: the upstream archive does not contain c2patool/c2patool." >&2
    exit 1
fi

echo "==> Packaging ${ARCHIVE}"
# The glibc binary is replaced by the musl binary. Every other file, the sample
# directory included, is the file that upstream shipped.
install -m 0755 "${WORK}/out/c2patool" "${WORK}/stage/c2patool/c2patool"

FILE_OUTPUT="$(file -b "${WORK}/stage/c2patool/c2patool")"

cat > "${WORK}/stage/c2patool/MUSL-BUILD.txt" <<INFO
This archive is not an official ContentAuth distribution.

It contains c2patool ${VERSION}, compiled from unmodified upstream source for
${TARGET}. Every other file in this archive is the file that
upstream shipped in ${TAG}.

Upstream project: https://github.com/${UPSTREAM_REPO}
Upstream tag:     ${TAG}
Built from:       ${BUILD_SOURCE}
Compiler:         ${RUSTC_VERSION}
Target:           ${TARGET}
Built by:         https://github.com/reload/c2patool-musl
INFO

# The archive is written with sorted names and no timestamps, so that two
# builds of the same version produce the same bytes.
tar --sort=name --mtime="@0" --owner=0 --group=0 --numeric-owner \
    -C "${WORK}/stage" -cf - c2patool | gzip -9n > "${OUTDIR}/${ARCHIVE}"

cp "${OUTDIR}/${ARCHIVE}" "${OUTDIR}/${LATEST_ARCHIVE}"

( cd "$OUTDIR" && sha256sum "$ARCHIVE" "$LATEST_ARCHIVE" > SHA256SUMS )
SHA256="$(awk -v f="$ARCHIVE" '$2 == f || $2 == "*"f {print $1}' "${OUTDIR}/SHA256SUMS")"

cp "${WORK}/out/build-info.env" "${OUTDIR}/build-info.env"
cat >> "${OUTDIR}/build-info.env" <<INFO
ARCHIVE=${ARCHIVE}
LATEST_ARCHIVE=${LATEST_ARCHIVE}
SHA256=${SHA256}
FILE_OUTPUT=${FILE_OUTPUT}
INFO

cat > "${OUTDIR}/release-notes.md" <<INFO
A static \`c2patool\` ${VERSION} for \`${TARGET}\`.

This is not an official ContentAuth distribution. It is unmodified upstream
source, compiled for a target that upstream does not publish. See the
[README](https://github.com/reload/c2patool-musl#readme).

| | |
|---|---|
| Upstream version | \`${VERSION}\` |
| Upstream tag | [\`${TAG}\`](https://github.com/${UPSTREAM_REPO}/releases/tag/${TAG}) |
| Built from | ${BUILD_SOURCE} |
| Compiler | \`${RUSTC_VERSION}\` |
| Build image | \`${RUST_IMAGE}\` |
| Target triple | \`${TARGET}\` |
| Binary type | \`${FILE_OUTPUT}\` |
| Size | ${SIZE_STRIPPED} bytes stripped, ${SIZE_UNSTRIPPED} bytes unstripped |
| sha256 | \`${SHA256}\` |

The binary was tested in \`alpine:3.24\` and in \`debian:bookworm-slim\` before
this release was published. It reads a manifest from \`sample/C.jpg\` and
reports no claim for \`sample/image.jpg\`.

## Download

\`\`\`sh
curl -fsSL -o c2patool.tar.gz \\
  https://github.com/reload/c2patool-musl/releases/download/${TAG}/${ARCHIVE}
echo "${SHA256}  c2patool.tar.gz" | sha256sum -c -
tar xzf c2patool.tar.gz --strip-components=1 c2patool/c2patool
\`\`\`

The same build is always available at a stable URL:
\`https://github.com/reload/c2patool-musl/releases/latest/download/${LATEST_ARCHIVE}\`
INFO

echo "==> Done"
ls -l "$OUTDIR"
