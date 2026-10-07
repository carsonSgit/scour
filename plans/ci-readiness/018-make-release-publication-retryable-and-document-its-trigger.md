# Make release publication retryable and document its trigger

Issue: [#48](https://github.com/carsonSgit/scour/issues/48).

| Priority | Effort | Change risk | Confidence | Audited commit |
|---|---|---|---|---|
| P0 | M | MED | HIGH: code or repository evidence | afd5f4d |

## Current gap

.github/workflows/release.yml:93 pushes a version bump before builds. It skips release commits at line 43 and equal versions at line 73. README.md describes tag triggers and manual validation, although dispatch can publish.

## Work

Separate preparation, validation, and publication state. Detect whether the intended release and complete assets exist rather than treating a source bump as publication. Support retrying the same version/commit. Provide an explicit validation-only dispatch and update release instructions.

## Acceptance

- [ ] Simulated build/upload failures recover to exactly one release without an extra version bump.
- [ ] Partial assets are detected and repaired or rejected clearly.
- [ ] Invalid versions fail before writes.
- [ ] Main advances during preparation without being overwritten.
- [ ] Validation-only runs create no commits/tags/releases.
- [ ] README accurately names publishing events and the retry procedure.

## Scope and verification

.github/workflows/release.yml, scripts/bump_version.sh, README.md, release workflow tests.

Run `nimble test -y` for core changes and `bash tests/test_distribution.sh` for integration changes. Add the named regression cases. Record real pipeline/artifact evidence where required.

Readiness item 018.

## Dependencies

[#43](https://github.com/carsonSgit/scour/issues/43).
