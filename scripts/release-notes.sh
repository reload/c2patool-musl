#!/usr/bin/env bash
# Writes the release notes for one version from the build info of every target.
#
# Usage: scripts/release-notes.sh <version> <dist-dir>
# Reads <dist-dir>/build-info-<target>.json and <dist-dir>/SHA256SUMS.

set -euo pipefail

VERSION="${1:?usage: release-notes.sh <version> <dist-dir>}"
DIST="${2:?usage: release-notes.sh <version> <dist-dir>}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/config.sh
. "${REPO_ROOT}/scripts/config.sh"

TAG="$(tag_for "$VERSION")"
REPO_URL="${REPO_URL:-https://github.com/reload/c2patool-musl}"
DIST="$(cd "$DIST" && pwd)"

INFOS=("${DIST}"/build-info-*.json)
if [ ! -f "${INFOS[0]}" ]; then
    echo "error: no build-info-*.json file was found in ${DIST}." >&2
    exit 1
fi

sha_of() { awk -v f="$1" '$2 == f {print $1}' "${DIST}/SHA256SUMS"; }

# A field is printed once when every target agrees, and once per target when
# they do not. They normally agree, because every target uses the same image.
common_field() {
    jq -r --arg k "$1" '.[$k]' "${INFOS[@]}" | sort -u
}

format_field() {
    local key="$1" label="$2" values
    values="$(common_field "$key")"
    if [ "$(printf '%s\n' "$values" | wc -l)" -eq 1 ]; then
        printf '| %s | `%s` |\n' "$label" "$values"
    else
        local info
        for info in "${INFOS[@]}"; do
            printf '| %s, %s | `%s` |\n' "$label" \
                "$(jq -r .target "$info")" "$(jq -r --arg k "$key" '.[$k]' "$info")"
        done
    fi
}

cat <<MD
Static \`c2patool\` ${VERSION} binaries for Linux with musl.

This is not an official ContentAuth distribution. It is unmodified upstream
source, compiled for targets that upstream does not publish. See the
[README](${REPO_URL}#readme).

## Targets

| Target | Archive | Size | sha256 |
|---|---|---|---|
MD

for info in "${INFOS[@]}"; do
    target="$(jq -r .target "$info")"
    archive="$(jq -r .archive "$info")"
    size="$(jq -r .size_stripped "$info")"
    printf '| `%s` | `%s` | %s bytes | `%s` |\n' \
        "$target" "$archive" "$size" "$(sha_of "$archive")"
done

cat <<MD

Each target also has a copy at a name without the version, so that
\`${REPO_URL}/releases/latest/download/c2patool-<target>.tar.gz\` always points
at the newest release.

## Build

| | |
|---|---|
| Upstream version | \`${VERSION}\` |
| Upstream tag | [\`${TAG}\`](${UPSTREAM_URL}/releases/tag/${TAG}) |
MD

format_field build_source "Built from"
format_field rustc "Compiler"
format_field rust_image "Build image"
format_field file_output "Binary type"

# Built before the heredoc, because backticks inside a heredoc expansion are
# command substitution.
IMAGES_TEXT=""
for image in $SMOKE_IMAGES; do
    if [ -z "$IMAGES_TEXT" ]; then
        IMAGES_TEXT="\`${image}\`"
    else
        IMAGES_TEXT="${IMAGES_TEXT} and \`${image}\`"
    fi
done

cat <<MD

Every binary was tested in ${IMAGES_TEXT} before this release was
published. It reads a manifest from \`sample/C.jpg\` and reports no claim for
\`sample/image.jpg\`.

## Download

Replace \`<target>\` with \`x86_64-unknown-linux-musl\` or
\`aarch64-unknown-linux-musl\`.

\`\`\`sh
curl -fsSL -O ${REPO_URL}/releases/download/${TAG}/${TAG}-<target>.tar.gz
curl -fsSL -O ${REPO_URL}/releases/download/${TAG}/SHA256SUMS
sha256sum -c --ignore-missing SHA256SUMS
tar xzf ${TAG}-<target>.tar.gz --strip-components=1 c2patool/c2patool
\`\`\`
MD
