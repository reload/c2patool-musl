#!/usr/bin/env bash
# Fetches what upstream ships beside the binary, so our archive keeps upstream's
# layout. The sample files are also what the smoke test runs against.
# They are the same for every target, so this runs once per version.
#
# Usage: scripts/fetch-aux.sh <version> <outdir>

set -euo pipefail

VERSION="${1:?usage: fetch-aux.sh <version> <outdir>}"
OUTDIR="${2:?usage: fetch-aux.sh <version> <outdir>}"

# shellcheck source=scripts/config.sh
. "$(cd "$(dirname "$0")" && pwd)/config.sh"

TAG="$(tag_for "$VERSION")"
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

# A function called from `if` runs with errexit off, so every step below states
# its own failure. Each route stages its own directory and publishes it only
# once the route finishes.

# Route 1: upstream's release archive, which gives the exact layout. The asset
# name comes from the API, because upstream changed the convention once.
from_release_archive() {
    stage="${WORK}/release-archive"
    rm -rf "$stage" || return 1
    mkdir -p "$stage" || return 1

    url="$(curl_gh "https://api.github.com/repos/${UPSTREAM_REPO}/releases/tags/${TAG}" \
        | jq -r '.assets[] | select(.name | endswith("-x86_64-unknown-linux-gnu.tar.gz")) | .browser_download_url' \
        | head -n 1)" || return 1

    if [ -z "$url" ] || [ "$url" = "null" ]; then
        echo "The upstream release ${TAG} has no Linux archive." >&2
        return 1
    fi

    echo "==> Reading the layout from the upstream release archive"
    curl -fsSL "$url" | tar xz -C "$stage" || return 1
    [ -d "${stage}/c2patool" ] || return 1

    # The glibc binary is dropped. The musl binary replaces it later.
    rm -f "${stage}/c2patool/c2patool" || return 1
    printf 'upstream release archive %s\n' "$(basename "$url")" \
        > "${stage}/c2patool/.aux-source" || return 1

    RESULT="${stage}/c2patool"
}

# Route 2: the source tag, for when upstream stops shipping a Linux archive.
# The crate is found by package name, because upstream moved it once already.
from_source_tag() {
    stage="${WORK}/source-tag"
    rm -rf "$stage" || return 1
    mkdir -p "${stage}/src" "${stage}/out" || return 1

    echo "==> The upstream release archive is unavailable. Reading the source tag instead."
    curl -fsSL "${UPSTREAM_URL}/archive/refs/tags/${TAG}.tar.gz" \
        | tar xz -C "${stage}/src" --strip-components=1 || return 1

    manifest="$(grep -rl --include=Cargo.toml -E '^name[[:space:]]*=[[:space:]]*"c2patool"' "${stage}/src" | head -n 1)"
    if [ -z "$manifest" ]; then
        echo "error: no crate named c2patool was found in the source of ${TAG}." >&2
        return 1
    fi
    crate="$(dirname "$manifest")"
    echo "    the c2patool crate is at ${crate#"${stage}"/src/}"

    if [ ! -d "${crate}/sample" ]; then
        echo "error: the c2patool crate has no sample directory." >&2
        return 1
    fi

    cp -a "${crate}/sample" "${stage}/out/" || return 1
    for f in README.md CHANGELOG.md; do
        if [ -f "${crate}/${f}" ]; then
            cp -a "${crate}/${f}" "${stage}/out/" || return 1
        fi
    done
    printf 'source tag %s\n' "$TAG" > "${stage}/out/.aux-source" || return 1

    RESULT="${stage}/out"
}

RESULT=""
if ! from_release_archive; then
    from_source_tag
fi

cp -a "${RESULT}/." "$OUTDIR/"

# Fail here rather than after a ten minute compile.
for f in sample/C.jpg sample/image.jpg; do
    if [ ! -f "${OUTDIR}/${f}" ]; then
        echo "error: ${f} is missing. The smoke test needs it." >&2
        exit 1
    fi
done

echo "==> Collected from $(cat "${OUTDIR}/.aux-source")"
find "$OUTDIR" -type f | sed "s|^${OUTDIR}/|    |" | sort
