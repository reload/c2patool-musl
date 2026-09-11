# c2patool-musl

Static `c2patool` binaries for `x86_64-unknown-linux-musl`, built from
unmodified upstream source.

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

The binary in each release is tested in `alpine:3.24` and in
`debian:bookworm-slim` before the release is published.

## Why it is needed

The glibc binary that upstream publishes needs symbols up to `GLIBC_2.39`:

1. On `debian:bookworm-slim` it stops with `version 'GLIBC_2.38' not found` and
   `version 'GLIBC_2.39' not found`. Debian 12 Bookworm has glibc 2.36.
2. On Alpine it stops with `sh: not found`, because the file
   `/lib64/ld-linux-x86-64.so.2` does not exist there.
3. The Alpine `gcompat` package does not repair it. The binary then stops with
   `Error relocating: __isoc23_strtol: symbol not found`.

A static musl binary runs in all of these places, from one file.

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

### Pin a version

Pin a version in production. The sha256 makes the download verifiable.

```sh
VERSION=0.27.22
SHA256=a91386dfaf8c00a9f211af5732b0c1ae6709e3b863a4fadc8538388dd332ae6f
URL=https://github.com/reload/c2patool-musl/releases/download/c2patool-v${VERSION}/c2patool-v${VERSION}-x86_64-unknown-linux-musl.tar.gz

curl -fsSL -o /tmp/c2patool.tar.gz "$URL"
echo "${SHA256}  /tmp/c2patool.tar.gz" | sha256sum -c -
tar xzf /tmp/c2patool.tar.gz -C /usr/local/bin --strip-components=1 c2patool/c2patool
rm -f /tmp/c2patool.tar.gz
```

### Always take the newest version

This URL always points at the newest release:

```sh
curl -fsSL -o /tmp/c2patool.tar.gz \
  https://github.com/reload/c2patool-musl/releases/latest/download/c2patool-x86_64-unknown-linux-musl.tar.gz
tar xzf /tmp/c2patool.tar.gz -C /usr/local/bin --strip-components=1 c2patool/c2patool
rm -f /tmp/c2patool.tar.gz
```

### Taskfile

```yaml
vars:
  C2PATOOL_VERSION: 0.27.22
  C2PATOOL_SHA256: a91386dfaf8c00a9f211af5732b0c1ae6709e3b863a4fadc8538388dd332ae6f

tasks:
  c2patool:install:
    desc: Install the static c2patool binary into bin/
    status:
      - test -x bin/c2patool
      - '[ "$(bin/c2patool --version | cut -d" " -f2)" = "{{.C2PATOOL_VERSION}}" ]'
    cmds:
      - mkdir -p bin
      - curl -fsSL -o /tmp/c2patool.tar.gz https://github.com/reload/c2patool-musl/releases/download/c2patool-v{{.C2PATOOL_VERSION}}/c2patool-v{{.C2PATOOL_VERSION}}-x86_64-unknown-linux-musl.tar.gz
      - echo "{{.C2PATOOL_SHA256}}  /tmp/c2patool.tar.gz" | sha256sum -c -
      - tar xzf /tmp/c2patool.tar.gz -C bin --strip-components=1 c2patool/c2patool
      - rm -f /tmp/c2patool.tar.gz
```

### Upsun

```yaml
hooks:
    build: |
        set -e
        C2PATOOL_VERSION=0.27.22
        C2PATOOL_SHA256=a91386dfaf8c00a9f211af5732b0c1ae6709e3b863a4fadc8538388dd332ae6f
        mkdir -p "$PLATFORM_APP_DIR/bin"
        curl -fsSL -o /tmp/c2patool.tar.gz \
            "https://github.com/reload/c2patool-musl/releases/download/c2patool-v${C2PATOOL_VERSION}/c2patool-v${C2PATOOL_VERSION}-x86_64-unknown-linux-musl.tar.gz"
        echo "${C2PATOOL_SHA256}  /tmp/c2patool.tar.gz" | sha256sum -c -
        tar xzf /tmp/c2patool.tar.gz -C "$PLATFORM_APP_DIR/bin" --strip-components=1 c2patool/c2patool
        rm -f /tmp/c2patool.tar.gz
```

The binary is about 29 MB. Upsun counts it against the build output size.

## Make sure that a download is correct

Every release has a `SHA256SUMS` file. Compare the file you downloaded against
it:

```sh
VERSION=0.27.22
BASE=https://github.com/reload/c2patool-musl/releases/download/c2patool-v${VERSION}

curl -fsSL -O "${BASE}/c2patool-v${VERSION}-x86_64-unknown-linux-musl.tar.gz"
curl -fsSL -O "${BASE}/SHA256SUMS"
sha256sum -c --ignore-missing SHA256SUMS
```

The same sha256 is also printed in the release notes. The archive contains a
`MUSL-BUILD.txt` file that names the upstream tag and the compiler version.

## Build it again by hand

This one command produces the same binary that the workflow produces. It takes
about eight to ten minutes:

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
because the dependency tree compiles its own OpenSSL.

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

Three workflows do the work.

### Build and release

`.github/workflows/build-release.yml` builds one version and publishes it.

It runs `cargo install --git https://github.com/contentauth/c2pa-rs --tag
c2patool-vX.Y.Z c2patool --locked` inside a pinned `rust:1.98.1-alpine3.24`
image. The crate is found by package name, because upstream moved it from
`c2patool/` to `cli/` and can move it again. If the tag build fails, the
workflow falls back to `cargo install c2patool --version X.Y.Z --locked` from
crates.io.

The workflow then downloads the upstream release archive, replaces the glibc
binary in it with the musl binary, and adds a `MUSL-BUILD.txt` file. Every
other file, the `sample/` directory included, is the file that upstream
shipped.

Before it publishes anything, the workflow runs three tests in `alpine:3.24`
and in `debian:bookworm-slim`:

1. `c2patool --version` prints the expected version.
2. `c2patool sample/C.jpg` exits 0 and prints `active_manifest`.
3. `c2patool sample/image.jpg` exits 1 and prints `No claim found`.

A failed test stops the release.

Each release carries three assets: the versioned archive, a copy at a name
without the version, and `SHA256SUMS`. The copy without the version is what
makes the `/releases/latest/download/` URL work.

Running the workflow again for a version that is already published does
nothing. To build any version by hand, start the workflow from the Actions tab
and give it a version number. The `force` input replaces a release that already
exists.

Permissions: `contents: write` to create the release, and `issues: write` to
report a failure.

### Check upstream

`.github/workflows/check-upstream.yml` runs once a day at 06:40 UTC.

It reads the newest `c2patool-v*` release from `contentauth/c2pa-rs`, compares
it against the newest release here, and starts the build workflow when upstream
is ahead. Only the newest upstream version is built. The log of every run
states both version numbers and the decision.

An upstream GitHub release can appear a few seconds before the crates.io
publish. If the build fails and crates.io does not have the version yet, the
workflow writes a warning and stops without an error. The next daily run takes
that version.

Permissions: `contents: write` and `issues: write`, because this workflow
passes its permissions down to the build workflow.

### Keepalive

`.github/workflows/keepalive.yml` runs once a week.

GitHub disables the scheduled workflows in a repository after 60 days without
repository activity, and a published release does not reset that timer
reliably. Upstream can go quiet for longer than 60 days. If that happens, the
daily check stops silently and this repository falls behind without anybody
noticing.

This workflow reads the date of the last commit. If that commit is more than 45
days old, the workflow writes a timestamp to `.github/keepalive` and commits
it. The commit resets the 60 day timer. While upstream stays active, the
workflow does nothing, because each release run leaves no commit but the
keepalive check is cheap.

Permissions: `contents: write` to push the commit.

### When something breaks

A failed build or a failed upstream check opens an issue with the
`build-failure` label. If an open issue with that label already exists, the
workflow adds a comment to it instead. A daily failure therefore produces one
issue and one comment per day, not one issue per day.

Close the issue after you fix the cause. The next failure opens a new one.

## Other targets

Only `x86_64-unknown-linux-musl` is built. `aarch64-unknown-linux-musl` is a
small addition: it needs a matrix entry in the build workflow and a runner or a
cross compiler for that architecture. Open an issue if you need it.

## License and attribution

The upstream project is dual licensed under MIT or Apache-2.0. Both license
texts are in this repository as [LICENSE-MIT](LICENSE-MIT) and
[LICENSE-APACHE](LICENSE-APACHE). You can use the binaries under either
license.

The files in this repository, which means the workflows, the scripts, and this
README, are published under the same dual license.

Read [NOTICE](NOTICE) for the full attribution.
