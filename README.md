# c2patool-musl

Static `c2patool` binaries for Linux with musl, compiled from unmodified upstream
source. Two targets: `x86_64-unknown-linux-musl` and `aarch64-unknown-linux-musl`.

This is not an official ContentAuth distribution. Adobe and ContentAuth do not
produce, review, endorse or support these binaries. [Reload](https://github.com/reload)
maintains this repository and has no connection to upstream beyond the source it
compiles.

## Why

`c2patool` reads C2PA manifests, also called Content Credentials, out of media
files. Upstream, [contentauth/c2pa-rs](https://github.com/contentauth/c2pa-rs),
publishes it for macOS, Windows and Linux with glibc, but not for musl, the C
library that Alpine Linux uses. The glibc build also needs `GLIBC_2.39`, so it
does not start on Debian 12 either, which has glibc 2.36.

A static binary needs no shared library at run time. The same file therefore
runs on Alpine, Debian, Ubuntu and a GitHub runner. The arm64 target is for
Linux containers on an Apple Silicon Mac. For the macOS host itself, use the
`universal-apple-darwin` archive that upstream publishes.

Two things to know before you depend on it. The binary links its own OpenSSL,
which no system update will patch, so a new c2patool release is the only route
to an OpenSSL fix. The artifacts are not signed. `SHA256SUMS` protects against a
damaged download, not against a compromised release.

## Install

Pick the target for the machine the binary runs on: `x86_64-unknown-linux-musl`
for Intel and AMD, `aarch64-unknown-linux-musl` for arm64. The archive keeps
upstream's layout, so a command that unpacks the upstream archive works
unchanged.

```sh
VERSION=0.27.22
TARGET=x86_64-unknown-linux-musl
BASE=https://github.com/reload/c2patool-musl/releases/download/c2patool-v${VERSION}
ARCHIVE="c2patool-v${VERSION}-${TARGET}.tar.gz"

curl -fsSL -O "${BASE}/${ARCHIVE}"
curl -fsSL -O "${BASE}/SHA256SUMS"
grep " ${ARCHIVE}\$" SHA256SUMS | sha256sum -c -
tar xzf "$ARCHIVE" -C /usr/local/bin --strip-components=1 c2patool/c2patool
```

The `grep` takes one line out of `SHA256SUMS`, because BusyBox on Alpine has no
`--ignore-missing`. On macOS, use `shasum -a 256 -c -`. The same checksums are
in the release notes, and the archive holds a `MUSL-BUILD.txt` that names the
upstream tag and the compiler.

`https://github.com/reload/c2patool-musl/releases/latest/download/c2patool-${TARGET}.tar.gz`
always points at the newest release.

The steps above work unchanged in a Dockerfile or a build hook. The binary is
about 29 MB on x86_64 and 25 MB on arm64.

### Taskfile

If the binary runs in a container, the architecture of that container is the one
that matters. It matches the host unless you force a platform.

```yaml
vars:
  C2PATOOL_VERSION: 0.27.22
  C2PATOOL_TARGET:
    sh: |
      case "$(uname -m)" in
        arm64|aarch64) echo aarch64-unknown-linux-musl ;;
        *) echo x86_64-unknown-linux-musl ;;
      esac

tasks:
  c2patool:install:
    desc: Install the static c2patool binary into bin/
    vars:
      ARCHIVE: c2patool-v{{.C2PATOOL_VERSION}}-{{.C2PATOOL_TARGET}}.tar.gz
      BASE: https://github.com/reload/c2patool-musl/releases/download/c2patool-v{{.C2PATOOL_VERSION}}
    status:
      - test -x bin/c2patool
      - '[ "$(bin/c2patool --version | cut -d" " -f2)" = "{{.C2PATOOL_VERSION}}" ]'
    cmds:
      - mkdir -p bin .c2patool-download
      - curl -fsSL -o .c2patool-download/{{.ARCHIVE}} {{.BASE}}/{{.ARCHIVE}}
      - curl -fsSL -o .c2patool-download/SHA256SUMS {{.BASE}}/SHA256SUMS
      # macOS has shasum and no sha256sum.
      - |
        cd .c2patool-download
        if command -v sha256sum >/dev/null 2>&1; then
          grep ' {{.ARCHIVE}}$' SHA256SUMS | sha256sum -c -
        else
          grep ' {{.ARCHIVE}}$' SHA256SUMS | shasum -a 256 -c -
        fi
      - tar xzf .c2patool-download/{{.ARCHIVE}} -C bin --strip-components=1 c2patool/c2patool
      - rm -rf .c2patool-download
```

## Build it by hand

This is the build the workflow runs, for the architecture of the machine you run
it on. It takes about ten minutes.

```sh
docker run --rm -v "$PWD:/work" -w /work rust:1.98.1-alpine3.24 sh -c '
  set -e
  apk add --no-cache build-base musl-dev perl cmake pkgconf binutils git
  cargo install --locked --root /work/out \
    --git https://github.com/contentauth/c2pa-rs --tag c2patool-v0.27.22 c2patool
  strip -o /work/c2patool /work/out/bin/c2patool
'
```

The image is musl hosted, so a plain `cargo install` gives a static binary.
`perl` and `cmake` are needed because the dependency tree compiles its own
OpenSSL. From a clone, `./scripts/build.sh 0.27.22 dist` followed by
`./scripts/smoke-test.sh dist/<archive> 0.27.22` runs the same steps.

Your binary is not byte for byte the published one, because rustc writes
absolute paths into it. Compare the behavior and the version, not the sha256.

## How it works

There is no upstream source here, so there is nothing to merge. Every release
compiles the upstream release tag. `scripts/config.sh` holds the upstream
repository, the tag prefix, the pinned image and the target list. That list
drives the build matrix, the asset checks and the release notes.

Each target builds on a runner of its own architecture, so the container is
native. Cross compilation fights the OpenSSL that the dependency tree builds,
and emulation is about six times slower. There is no build cache. Minutes are
free for a public repository, and a cache lets a release be built from something
other than a clean tree.

### Build and release

`build-release.yml` has three jobs.

Prepare checks that the upstream release exists and skips a version that is
already published with every asset. It then fetches the files upstream ships
beside the binary, including `sample/`. They come from the upstream release
archive, or from the source tag if that archive is missing.

Build runs once per target. It runs `cargo install --git
https://github.com/contentauth/c2pa-rs --tag c2patool-vX.Y.Z c2patool --locked`
in `rust:1.98.1-alpine3.24`, finding the crate by package name because upstream
moved it once. If that fails, it falls back to crates.io with a warning. It then
tests the binary in `alpine:3.24` and in `debian:bookworm-slim`:

1. `c2patool --version` prints the expected version.
2. `c2patool sample/C.jpg` exits 0 and prints `active_manifest`.
3. `c2patool sample/image.jpg` exits 1 and prints `No claim found`.

Publish waits for every target, writes one `SHA256SUMS`, creates the release,
and downloads it back to compare against that file. Each release holds the
versioned archive per target, a copy at a name without the version for the
`/latest/` URL, and `SHA256SUMS`.

Only publish can write. Build runs upstream build scripts, so it is read-only
with no checkout credential, and publish reads its metadata as JSON, never as
shell.

To build any version by hand, start the workflow from the Actions tab. A
complete release is skipped. A published release that is missing assets stops
the run, because rebuilding changes checksums that people have pinned. The
`force` input rebuilds it anyway. A leftover draft is replaced without asking.

### Check upstream

`check-upstream.yml` runs daily at 06:40 UTC. It compares the newest
`c2patool-v*` release in `contentauth/c2pa-rs` with the newest release here and
builds when upstream is ahead. Only the newest version is built. When the two
match, it also checks that the release here still holds every asset.

A GitHub release can appear seconds before its crates.io publish. If the tag
build fails and crates.io answers a plain "not found", the run stops with a
warning and the next day takes it. Any other answer, or a version still missing
after 24 hours, is a failure.

### Keepalive

GitHub disables scheduled workflows after 60 days without a commit, and a
release is a tag, not a commit. `keepalive.yml` runs weekly and commits a
timestamp to `.github/keepalive` when the last commit is over 45 days old.

### Failures and checks

A failure in the build, the daily check or the keepalive opens an issue labelled
`build-failure`, or comments on the open one. Close it when the cause is fixed.

`lint.yml` runs actionlint, shellcheck and zizmor on every push. Actions are
pinned to a commit digest, and Dependabot proposes updates weekly after a seven
day cooldown.

Permissions: `contents: read` to prepare, build, check and lint. `contents:
write` to publish and to push the keepalive commit. `issues: write` to report a
failure.

## License

Upstream is dual licensed under MIT or Apache-2.0, see [LICENSE-MIT](LICENSE-MIT)
and [LICENSE-APACHE](LICENSE-APACHE). The binaries and the files in this
repository are under the same terms. [NOTICE](NOTICE) holds the attribution.
