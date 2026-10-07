# Implement the first bounded cleanup rules

Issue: [#40](https://github.com/carsonSgit/scour/issues/40).

| Priority | Effort | Change risk | Confidence | Audited commit |
|---|---|---|---|---|
| P0 | L | HIGH | HIGH: code or repository evidence | afd5f4d |

## Current gap

RuleDefinition.fix in src/scourpkg/rule_catalog.nim is prose. dockerignore-missing and unpinned-github-action already produce actionable findings, but neither has an executable fix.

## Work

Implement two initial fixes: create a missing .dockerignore from explicit configured entries, and replace an Action ref using an explicitly supplied repository/ref-to-SHA mapping. Reuse fix planning and validation. Advertise the exact supported set.

## Acceptance

- [ ] A configured missing .dockerignore is created once; existing files are preserved.
- [ ] Action replacement accepts only validated 40-character SHAs and preserves YAML meaning.
- [ ] Mapping resolution needs no network or repository command execution.
- [ ] Reruns remove the corresponding findings.
- [ ] Secrets, conflicts, duplicate-lockfile choices, skipped tests, and other judgment-dependent findings remain manual.
- [ ] Clean fixtures produce no patch.

## Scope and verification

src/scourpkg/rule_catalog.nim, fix handlers, src/scourpkg/config.nim, tests/test_cli_setup.nim, tests/fixtures/.

Run `nimble test -y` for core changes and `bash tests/test_distribution.sh` for integration changes. Add the named regression cases. Record real pipeline/artifact evidence where required.

Readiness item 010.

## Dependencies

[#39](https://github.com/carsonSgit/scour/issues/39).
