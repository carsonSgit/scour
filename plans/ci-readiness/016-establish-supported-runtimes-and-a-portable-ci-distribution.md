# Establish supported runtimes and a portable CI distribution

Issue: [#44](https://github.com/carsonSgit/scour/issues/44).

| Priority | Effort | Change risk | Confidence | Audited commit |
|---|---|---|---|---|
| P1 | M | MED | MED: runtime compatibility needs measurement | afd5f4d |

## Current gap

Release binaries compile on Ubuntu/macOS/Windows runners; scripts/install.sh selects OS/architecture without libc policy. There is no container image or native PowerShell installation path.

## Work

Measure Linux binary dependencies and define minimum supported runtimes, including an explicit Alpine/musl policy. Publish a versioned multi-architecture CI image with Git and required utilities. Improve installer prerequisite errors and document native Windows installation.

## Acceptance

- [ ] Real Linux binaries run on the documented minimum glibc environments and a supported musl path or tested image alternative.
- [ ] The image scans a mounted repo read-only and can write requested artifacts as a non-root user.
- [ ] Versions/digests are pin-able.
- [ ] Missing curl, extraction, checksum, or install tools yield actionable errors.
- [ ] Offline binary usage works.
- [ ] macOS/Windows support matches tested paths.

## Scope and verification

scripts/install.sh, release/container packaging, tests/test_distribution.sh, README.md.

Run `nimble test -y` for core changes and `bash tests/test_distribution.sh` for integration changes. Add the named regression cases. Record real pipeline/artifact evidence where required.

Readiness item 016.

## Dependencies

[#43](https://github.com/carsonSgit/scour/issues/43).
