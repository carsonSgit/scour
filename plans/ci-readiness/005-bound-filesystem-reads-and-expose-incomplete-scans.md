# Bound filesystem reads and expose incomplete scans

Issue: [#35](https://github.com/carsonSgit/scour/issues/35).

| Priority | Effort | Change risk | Confidence | Audited commit |
|---|---|---|---|---|
| P0 | M | MED | HIGH: code or repository evidence | afd5f4d |

## Current gap

src/scourpkg/files.nim:101 accepts file links; normalization lacks canonical-root containment. Failed opens become binary skips at line 37. Missing explicit paths are discarded at line 110. Rules read whole files repeatedly; maxFileSize defaults to zero.

## Work

Enforce repository containment for candidate and auxiliary reads, with links disabled by default. Distinguish binary/size exclusions from I/O failures. Add finite configurable resource limits and one controlled error contract. Reuse this policy for future fixes.

## Acceptance

- [ ] External links, dangling links, cycles, outside-root paths, missing paths, unreadable files, and files removed during scanning have defined results.
- [ ] Default scans never read outside the root.
- [ ] I/O failures cannot yield a clean result; fatal execution failures exit 2.
- [ ] Reports count skipped/incomplete files.
- [ ] Large-tree fixtures measure runtime and peak memory against recorded limits.

## Scope and verification

src/scourpkg/{files,app,errors,config}.nim, src/scourpkg/rules/*.nim, tests/test_cli_setup.nim.

Run `nimble test -y` for core changes and `bash tests/test_distribution.sh` for integration changes. Add the named regression cases. Record real pipeline/artifact evidence where required.

Readiness item 005.

## Dependencies

[#31](https://github.com/carsonSgit/scour/issues/31), [#34](https://github.com/carsonSgit/scour/issues/34).
