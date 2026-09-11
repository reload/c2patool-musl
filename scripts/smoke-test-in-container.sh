#!/bin/sh
# Tests one c2patool binary inside a container. Exits non-zero on any failure.
# Runs from a directory that holds the c2patool binary and the sample directory.
#
# Usage: smoke-test-in-container.sh <expected-version>

set -u

VERSION="${1:?usage: smoke-test-in-container.sh <expected-version>}"
FAILED=0

fail() {
    echo "FAIL: $1"
    FAILED=1
}

echo "--- test 1: the binary reports version ${VERSION}"
OUT="$(./c2patool --version 2>&1)" || fail "c2patool --version exited $?"
echo "    output: ${OUT}"
case "$OUT" in
    *"$VERSION"*) echo "    ok" ;;
    *) fail "c2patool --version did not print ${VERSION}" ;;
esac

echo "--- test 2: sample/C.jpg has a manifest"
OUT="$(./c2patool sample/C.jpg 2>&1)"
STATUS=$?
if [ "$STATUS" -ne 0 ]; then
    fail "c2patool sample/C.jpg exited ${STATUS}, expected 0"
    echo "    output: ${OUT}"
fi
case "$OUT" in
    *active_manifest*) echo "    ok, the output contains active_manifest" ;;
    *) fail "the output of c2patool sample/C.jpg has no active_manifest"
       echo "    output: ${OUT}" ;;
esac

echo "--- test 3: sample/image.jpg has no manifest"
OUT="$(./c2patool sample/image.jpg 2>&1)"
STATUS=$?
if [ "$STATUS" -ne 1 ]; then
    fail "c2patool sample/image.jpg exited ${STATUS}, expected 1"
    echo "    output: ${OUT}"
fi
case "$OUT" in
    *"No claim found"*) echo "    ok, the output contains No claim found" ;;
    *) fail "the output of c2patool sample/image.jpg has no No claim found"
       echo "    output: ${OUT}" ;;
esac

if [ "$FAILED" -ne 0 ]; then
    echo "smoke test failed"
    exit 1
fi

echo "smoke test passed"
