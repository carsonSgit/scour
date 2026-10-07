# Publish and test the user onboarding contract

Issue: [#51](https://github.com/carsonSgit/scour/issues/51).

| Priority | Effort | Change risk | Confidence | Audited commit |
|---|---|---|---|---|
| P0 | M | LOW | HIGH: code or repository evidence | afd5f4d |

## Current gap

README.md's Action example omits checkout/history and references nonexistent v1. There is no complete GitLab/generic cleanup quickstart or supported-fix matrix.

## Work

Publish complete pinned scan and cleanup examples, configuration reference, supported platforms/languages/fixes, exit codes, artifact application steps, and troubleshooting. Generate rule/config references from existing catalogs where feasible. Align the site snippets with executable examples.

## Acceptance

- [ ] A new checkout follows each documented supported-provider example without a compiler.
- [ ] Automated tests execute copied example commands and validate workflow references.
- [ ] Documentation distinguishes scan findings, cleanup capability, and manual remediation.
- [ ] Record one clean, one failing, and one patch-producing GitHub/GitLab run with retained artifacts before calling the product user-ready.

## Scope and verification

README.md, docs/, site/src/components/GithubAction.tsx, integration/example checks.

Run `nimble test -y` for core changes and `bash tests/test_distribution.sh` for integration changes. Add the named regression cases. Record real pipeline/artifact evidence where required.

Readiness item 021.

## Dependencies

[#32](https://github.com/carsonSgit/scour/issues/32), [#40](https://github.com/carsonSgit/scour/issues/40), [#41](https://github.com/carsonSgit/scour/issues/41), [#42](https://github.com/carsonSgit/scour/issues/42), [#45](https://github.com/carsonSgit/scour/issues/45), [#44](https://github.com/carsonSgit/scour/issues/44), [#48](https://github.com/carsonSgit/scour/issues/48), [#49](https://github.com/carsonSgit/scour/issues/49), [#50](https://github.com/carsonSgit/scour/issues/50).
