# Security

## This repository

Report a vulnerability in the build and release pipeline through
[private vulnerability reporting](https://github.com/reload/c2patool-musl/security/advisories/new).
That covers the workflows, the scripts and the published release assets. Do not
open a public issue.

## c2patool

Report a vulnerability in c2patool or its dependencies, including the OpenSSL
that the binary links, to upstream. The
[contentauth/c2patool security policy](https://github.com/contentauth/c2patool/blob/main/SECURITY.md)
describes how. This repository compiles upstream source without changes and
cannot patch it.

## Fixes

A fix reaches these binaries only through a new upstream release. The daily
check builds that release automatically. Published releases are not rebuilt, so
update to the newest one.
