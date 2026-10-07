# Gate releases on actual artifact validation

Issue: [#43](https://github.com/carsonSgit/scour/issues/43).

| Priority | Effort | Change risk | Confidence | Audited commit |
|---|---|---|---|---|
| P0 | M | LOW | HIGH: code or repository evidence | afd5f4d |

## Current gap

.github/workflows/release.yml builds and packages without tests or a dependency on CI. CI tests Ubuntu only; tests/test_distribution.sh uses fake binaries and ZIP extraction.

## Work

Require green validation of the release commit before publication. On each of the five supported runners, extract the actual archive and execute it. Keep mocked tests for controlled failure paths, but add real artifact/install verification.

## Acceptance

- [ ] A failing regression test blocks publication.
- [ ] All five extracted binaries pass help/version, clean and dirty JSON scans, and expected exit codes.
- [ ] Checksums match exact archives.
- [ ] Installer tests consume actual archives for supported install paths.
- [ ] Wrapper tests invoke the actual binary.
- [ ] A validation-only workflow run publishes nothing.

## Scope and verification

.github/workflows/ci.yml, .github/workflows/release.yml, tests/test_distribution.sh, tests/test_cli_setup.nim.

Run `nimble test -y` for core changes and `bash tests/test_distribution.sh` for integration changes. Add the named regression cases. Record real pipeline/artifact evidence where required.

Readiness item 017.

## Dependencies

None.
