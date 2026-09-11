# shellcheck shell=sh
# shellcheck disable=SC2034  # these constants are read by the scripts that source this file
# Shared constants and helpers for the build scripts.
# Sourced, never executed. Every value can be overridden from the environment.

UPSTREAM_REPO="${UPSTREAM_REPO:-contentauth/c2pa-rs}"
UPSTREAM_URL="https://github.com/${UPSTREAM_REPO}"

# Upstream tags a c2patool release as c2patool-vX.Y.Z in the c2pa-rs repository.
TAG_PREFIX="c2patool-v"

# The build image is pinned to an exact compiler and an exact Alpine version.
# The image must be musl hosted, so that a plain cargo install produces a static
# binary with no cross compilation setup.
RUST_IMAGE="${RUST_IMAGE:-rust:1.98.1-alpine3.24}"

# The targets this repository publishes, and the runner that builds each one.
# The runner must be of the target's architecture, so the build image is always
# native. Cross compilation is avoided because the dependency tree compiles its
# own OpenSSL, and emulation is avoided because it makes the build far slower.
TARGET_RUNNERS="${TARGET_RUNNERS:-x86_64-unknown-linux-musl=ubuntu-latest aarch64-unknown-linux-musl=ubuntu-24.04-arm}"

# Prints one target per line.
supported_targets() {
    for _pair in $TARGET_RUNNERS; do
        printf '%s\n' "${_pair%%=*}"
    done
}

# Prints the build matrix for the workflow, so the list of targets lives here
# and not in the workflow file as well.
matrix_json() {
    _first=1
    printf '{"include":['
    for _pair in $TARGET_RUNNERS; do
        [ "$_first" -eq 1 ] || printf ','
        printf '{"target":"%s","runner":"%s"}' "${_pair%%=*}" "${_pair#*=}"
        _first=0
    done
    printf ']}'
}

# The binary is tested in these images before any release is published.
SMOKE_IMAGES="${SMOKE_IMAGES:-alpine:3.24 debian:bookworm-slim}"

# Accepts 0.27.22, v0.27.22 and c2patool-v0.27.22. Prints 0.27.22.
normalize_version() {
    _v="${1#c2patool-}"
    _v="${_v#v}"
    printf '%s' "$_v"
}

# Prints the upstream tag for a version number.
tag_for() {
    printf '%s%s' "$TAG_PREFIX" "$1"
}

# Prints the release asset name for a version and a target.
archive_for() {
    printf '%s%s-%s.tar.gz' "$TAG_PREFIX" "$1" "$2"
}

# Prints the version independent asset name for a target. This name is what
# makes the /releases/latest/download/ URL work.
latest_archive_for() {
    printf 'c2patool-%s.tar.gz' "$1"
}

# Prints every asset name a complete release of this version must hold.
expected_assets() {
    printf '%s\n' "SHA256SUMS"
    for _t in $(supported_targets); do
        archive_for "$1" "$_t"; printf '\n'
        latest_archive_for "$_t"; printf '\n'
    done
}

# Prints the asset names that the given release is missing. Reads the output of
# `gh release view --json assets` on standard input.
missing_assets() {
    _release="$(cat)"
    for _a in $(expected_assets "$1"); do
        if ! printf '%s' "$_release" | jq -e --arg a "$_a" 'any(.assets[]; .name == $a)' >/dev/null; then
            printf '%s\n' "$_a"
        fi
    done
}

# Prints the target triple for the architecture of the machine that runs this.
target_for_host_arch() {
    case "$(uname -m)" in
        x86_64|amd64) printf 'x86_64-unknown-linux-musl' ;;
        aarch64|arm64) printf 'aarch64-unknown-linux-musl' ;;
        *) return 1 ;;
    esac
}
