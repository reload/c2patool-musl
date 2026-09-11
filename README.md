# c2patool-musl

Static `c2patool` binaries for Linux with musl, built from unmodified upstream
source. Two targets are published: `x86_64-unknown-linux-musl` and
`aarch64-unknown-linux-musl`.

This is not an official ContentAuth distribution. Read
[What this is not](#what-this-is-not) before you use it.

## What this is

`c2patool` reads C2PA manifests out of media files. C2PA, also called Content
Credentials, is a standard that records how a file was made. The upstream
project is [contentauth/c2pa-rs](https://github.com/contentauth/c2pa-rs).

Upstream publishes prebuilt binaries for three targets: macOS, Windows, and
Linux with glibc. glibc is the C library that Debian and Ubuntu use. Upstream
publishes no binary for musl, the C library that Alpine Linux uses.

This repository fills that gap. A workflow compiles the upstream source in a
musl container once a day and publishes the result as a release here. The
binary is static, which means that it needs no shared library at run time. One
binary therefore runs on Alpine, on Debian, on Ubuntu, and on a GitHub runner.

Every binary is tested in `alpine:3.24` and in `debian:bookworm-slim` on its own
architecture before the release is published.

## Why it is needed

The glibc binary that upstream publishes needs symbols up to `GLIBC_2.39`:

1. On `debian:bookworm-slim` it stops with `version 'GLIBC_2.38' not found` and
   `version 'GLIBC_2.39' not found`. Debian 12 Bookworm has glibc 2.36.
2. On Alpine it stops with `sh: not found`, because the file
   `/lib64/ld-linux-x86-64.so.2` does not exist there.
3. The Alpine `gcompat` package does not repair it. The binary then stops with
   `Error relocating: __isoc23_strtol: symbol not found`.

A static musl binary runs in all of these places, from one file.

The arm64 target exists for local development on an Apple Silicon Mac. The tool
runs inside a php-fpm container, and on that machine the container is
`linux/arm64`. For a binary that runs on the macOS host itself, use the
`universal-apple-darwin` archive that upstream publishes.

## What this is not

Adobe and ContentAuth do not produce, review, endorse, or support these
binaries. This repository is maintained by [Reload](https://github.com/reload)
and has no connection to the upstream project beyond the source code it
compiles.

The binary links its own copy of OpenSSL. A system update will never patch that
copy. A new version of c2patool is the only route to an OpenSSL fix, so track
the releases here.

The release artifacts are not signed. The `SHA256SUMS` file protects against a
damaged download, not against a compromised release.

## Install

The archive has the same layout as the upstream release archive, so a command
that unpacks the upstream archive works here without a change.

Pick the target that matches the machine the binary runs on:

- `x86_64-unknown-linux-musl` for Intel and AMD.
- `aarch64-unknown-linux-musl` for arm64, which includes an Apple Silicon Mac
  running a Linux container.

### Pin a version

Pin a version in production. The `SHA256SUMS` file of that release makes the
download verifiable.

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

The single line is taken out of `SHA256SUMS` first, because BusyBox, which is
what Alpine uses, has no `--ignore-missing` option. On macOS, write
`shasum -a 256 -c -` in place of `sha256sum -c -`.

### Always take the newest version

Each target has a URL that always points at the newest release:

```sh
TARGET=x86_64-unknown-linux-musl
curl -fsSL -o /tmp/c2patool.tar.gz \
  "https://github.com/reload/c2patool-musl/releases/latest/download/c2patool-${TARGET}.tar.gz"
tar xzf /tmp/c2patool.tar.gz -C /usr/local/bin --strip-components=1 c2patool/c2patool
rm -f /tmp/c2patool.tar.gz
```

### Taskfile

The binary runs inside the php-fpm container, so the architecture that matters
is the architecture of that container. It is the same as the host unless you
force a platform. To read it, run
`docker compose exec php uname -m`.

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
      # macOS has shasum and no sha256sum. Linux usually has both.
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

### In a container image or a server build step

When you know the architecture of the machine the build runs on, fix the target
rather than detecting it.

```sh
set -e
C2PATOOL_VERSION=0.27.22
C2PATOOL_TARGET=x86_64-unknown-linux-musl
INSTALL_DIR=/usr/local/bin

ARCHIVE="c2patool-v${C2PATOOL_VERSION}-${C2PATOOL_TARGET}.tar.gz"
BASE="https://github.com/reload/c2patool-musl/releases/download/c2patool-v${C2PATOOL_VERSION}"

mkdir -p "$INSTALL_DIR" /tmp/c2patool
cd /tmp/c2patool
curl -fsSL -O "${BASE}/${ARCHIVE}"
curl -fsSL -O "${BASE}/SHA256SUMS"
grep " ${ARCHIVE}\$" SHA256SUMS | sha256sum -c -
tar xzf "$ARCHIVE" -C "$INSTALL_DIR" --strip-components=1 c2patool/c2patool
cd - >/dev/null && rm -rf /tmp/c2patool
```

The binary is about 29 MB on x86_64 and about 25 MB on arm64. It counts against
any limit on the size of a build output.

## Make sure that a download is correct

Every release has a `SHA256SUMS` file that covers every archive in that release.
Compare the file you downloaded against it:

```sh
VERSION=0.27.22
TARGET=x86_64-unknown-linux-musl
BASE=https://github.com/reload/c2patool-musl/releases/download/c2patool-v${VERSION}

ARCHIVE="c2patool-v${VERSION}-${TARGET}.tar.gz"

curl -fsSL -O "${BASE}/${ARCHIVE}"
curl -fsSL -O "${BASE}/SHA256SUMS"
grep " ${ARCHIVE}\$" SHA256SUMS | sha256sum -c -
```

On macOS, write `shasum -a 256 -c -` in place of `sha256sum -c -`.

The same checksums are printed in the release notes. The archive contains a
`MUSL-BUILD.txt` file that names the upstream tag and the compiler version.

## Build it again by hand

This one command produces the same binary that the workflow produces. It takes
about ten minutes:

```sh
docker run --rm -v "$PWD:/work" -w /work rust:1.98.1-alpine3.24 sh -c '
  set -e
  apk add --no-cache build-base musl-dev perl cmake pkgconf binutils git
  cargo install --locked --root /work/out \
    --git https://github.com/contentauth/c2pa-rs --tag c2patool-v0.27.22 c2patool
  strip -o /work/c2patool /work/out/bin/c2patool
'
```

The image is musl hosted, so a plain `cargo install` produces the static
binary. No cross compilation setup is needed. `perl` and `cmake` are needed
because the dependency tree compiles its own OpenSSL. The command builds for the
architecture of the machine you run it on, so run it on arm64 hardware to get
the arm64 binary.

After you clone this repository, the same build runs through the scripts that
the workflow uses:

```sh
./scripts/build.sh 0.27.22 dist
./scripts/smoke-test.sh dist/c2patool-v0.27.22-x86_64-unknown-linux-musl.tar.gz 0.27.22
```

Your binary and a published binary are not byte for byte identical. The Rust
compiler writes absolute paths into the binary. Compare the behavior and the
version, not the sha256.

## How this repository works

There is no upstream source code here. There is nothing to merge and nothing to
rebase. Every release is compiled from the upstream release tag, so the source
cannot drift away from upstream.

`scripts/config.sh` holds the upstream repository, the tag prefix, the pinned
build image, and the list of targets. Add a target there and the build matrix
follows.

### Build and release

`.github/workflows/build-release.yml` builds one version and publishes it. It
has three jobs.

The first job decides what to build. It checks that the upstream release exists,
and it skips a version that is already published with every expected asset. It
then downloads the files that upstream ships beside the binary, which includes
the `sample/` directory the smoke test needs. If upstream ever stops publishing
a Linux archive, the job reads those files from the source tag instead.

The second job builds, once per target, on a runner of that architecture. It
runs `cargo install --git https://github.com/contentauth/c2pa-rs --tag
c2patool-vX.Y.Z c2patool --locked` inside a pinned `rust:1.98.1-alpine3.24`
image. The crate is found by package name, because upstream moved it from
`c2patool/` to `cli/` and can move it again. If the tag build fails, the job
falls back to `cargo install c2patool --version X.Y.Z --locked` from crates.io
and prints a warning, so a tag build that rots does not stay hidden.

The job then runs three tests in `alpine:3.24` and in `debian:bookworm-slim`:

1. `c2patool --version` prints the expected version.
2. `c2patool sample/C.jpg` exits 0 and prints `active_manifest`.
3. `c2patool sample/image.jpg` exits 1 and prints `No claim found`.

A failed test stops the release.

The third job publishes. It waits for every target, writes one `SHA256SUMS` file
across all of them, and creates the release. Each release carries the versioned
archive for each target, a copy of each at a name without the version, and
`SHA256SUMS`. The copies without the version are what make the
`/releases/latest/download/` URL work.

Only the third job holds a write permission. The build job runs upstream build
scripts, so it holds `contents: read` and its checkout carries no credential.
The publish job never runs anything the build produced. It reads the build
metadata as JSON data and never as shell.

Permissions: `contents: read` to prepare and to build, `contents: write` to
publish, and `issues: write` to report a failure.

### Running it by hand

Start the workflow from the Actions tab and give it a version number. Running it
again for a version that is already complete does nothing.

If a release exists but is missing assets, the workflow stops and tells you.
Rebuilding replaces assets, and somebody can already have pinned a checksum for
them, so a person decides that and not the schedule. The `force` input rebuilds and
replaces such a release. A leftover draft release is different: a draft has no
consumers, so the workflow replaces it without asking.

### Check upstream

`.github/workflows/check-upstream.yml` runs once a day at 06:40 UTC.

It reads the newest `c2patool-v*` release from `contentauth/c2pa-rs`, compares
it against the newest release here, and starts the build workflow when upstream
is ahead. Only the newest upstream version is built. The log of every run states
both version numbers and the decision.

An upstream GitHub release can appear a few seconds before the crates.io
publish. If the tag build fails and crates.io returns a plain "not found" for
that version, the workflow writes a warning and stops without an error. The next
daily run takes that version. Two limits keep this from hiding a real fault. Any
other answer from crates.io, which includes a network error or a server error,
is a real failure. A version that is still missing 24 hours after its upstream
release is also a real failure.

Permissions: `contents: write` and `issues: write`, because a called workflow
runs with the permissions of the job that calls it.

### Keepalive

`.github/workflows/keepalive.yml` runs once a week.

GitHub disables the scheduled workflows in a repository after 60 days without
repository activity, and that timer counts commits. Publishing a release creates
a tag, not a commit, so releases do not reset it. Upstream can also go quiet for
longer than 60 days. Either way the daily check stops without anybody noticing.

This workflow reads the date of the last commit. If that commit is more than 45
days old, the workflow writes a timestamp to `.github/keepalive` and commits it.
The commit resets the 60 day timer. A weekly run means the commit always lands
well before day 60.

Permissions: `contents: write` to push the commit.

### When something breaks

A failure in any of the three workflows opens an issue with the `build-failure`
label. If an open issue with that label already exists, the workflow adds a
comment to it instead. A daily failure therefore produces one issue and one
comment per day, not one issue per day.

Close the issue after you fix the cause. The next failure opens a new one.

## Other targets

Add a target to `TARGET_RUNNERS` in `scripts/config.sh` together with a runner
of that architecture. The build matrix and the asset checks follow from that one
list.

Every target is built on a runner of its own architecture, so the container is
always native. Cross compilation is avoided because the dependency tree compiles
its own OpenSSL, which is the part that fights a cross toolchain. Emulation is
avoided because it makes the build roughly six times slower.

There is no build cache between runs. A build takes about ten minutes, GitHub
charges nothing for a public repository, and a cache adds a way for one release
to be built from something other than a clean tree.

## License and attribution

The upstream project is dual licensed under MIT or Apache-2.0. Both license
texts are in this repository as [LICENSE-MIT](LICENSE-MIT) and
[LICENSE-APACHE](LICENSE-APACHE). You can use the binaries under either
license.

The files in this repository, which means the workflows, the scripts, and this
README, are published under the same dual license.

Read [NOTICE](NOTICE) for the full attribution.
