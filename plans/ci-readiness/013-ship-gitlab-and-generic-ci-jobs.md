# Ship jobs for GitLab and generic CI

Issue: [#45](https://github.com/carsonSgit/scour/issues/45).

| Priority | Effort | Change risk | Confidence | Audited commit |
|---|---|---|---|---|
| P0 | M | LOW | HIGH: code or repository evidence | afd5f4d |

## Current gap

README.md supplies only a GitHub Action fragment. scripts/run-action.sh depends on GitHub output variables. No GitLab template or provider-neutral job example exists.

## Work

Provide a version-pinned GitLab include/job and a generic shell job using the same CLI contract. Set install location/PATH, comparison revisions, threshold, config, and artifact retention explicitly. Keep provider detection in wrappers, not hidden CLI guesses.

## Acceptance

- [ ] Fresh GitLab and generic jobs need no Nim compiler or GitHub runtime variables.
- [ ] Full and comparison scans execute against dirty fixtures.
- [ ] Jobs retain reports and patches when Scour exits 1 or 2.
- [ ] Document shallow-history setup, required utilities, proxy use, offline/preinstalled execution, and read-only fork behavior.
- [ ] Record an actual GitLab pipeline run before declaring the integration supported.

## Scope and verification

CI template files, scripts/install.sh, README.md, integration fixtures.

Run `nimble test -y` for core changes and `bash tests/test_distribution.sh` for integration changes. Add the named regression cases. Record real pipeline/artifact evidence where required.

Readiness item 013.

## Dependencies

[#32](https://github.com/carsonSgit/scour/issues/32), [#41](https://github.com/carsonSgit/scour/issues/41), [#42](https://github.com/carsonSgit/scour/issues/42), [#44](https://github.com/carsonSgit/scour/issues/44).
