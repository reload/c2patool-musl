#!/usr/bin/env bash
# Tests a packaged c2patool archive in every target container.
# The binary is tested in the containers it must run in, not on the host.
#
# Usage: scripts/smoke-test.sh <archive.tar.gz> <expected-version>

set -euo pipefail

ARCHIVE="${1:?usage: smoke-test.sh <archive.tar.gz> <expected-version>}"
VERSION="${2:?usage: smoke-test.sh <archive.tar.gz> <expected-version>}"
IMAGES="${IMAGES:-alpine:3.24 debian:bookworm-slim}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE="$(cd "$(dirname "$ARCHIVE")" && pwd)/$(basename "$ARCHIVE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

tar xzf "$ARCHIVE" -C "$WORK"
test -x "${WORK}/c2patool/c2patool"

FAILED=""
for IMAGE in $IMAGES; do
    echo "=============================================================="
    echo "==> Testing c2patool ${VERSION} in ${IMAGE}"
    echo "=============================================================="
    if docker run --rm \
        -v "${WORK}/c2patool:/t:ro" \
        -v "${REPO_ROOT}/scripts/smoke-test-in-container.sh:/smoke-test.sh:ro" \
        -w /t \
        "$IMAGE" \
        /bin/sh /smoke-test.sh "$VERSION"
    then
        echo "==> ${IMAGE}: passed"
    else
        echo "==> ${IMAGE}: FAILED"
        FAILED="${FAILED} ${IMAGE}"
    fi
done

if [ -n "$FAILED" ]; then
    echo "The smoke test failed in:${FAILED}"
    exit 1
fi

echo "The smoke test passed in every image."
