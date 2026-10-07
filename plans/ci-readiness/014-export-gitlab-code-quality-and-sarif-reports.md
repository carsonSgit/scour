# Export reports for GitLab Code Quality and SARIF

Issue: [#46](https://github.com/carsonSgit/scour/issues/46).

| Priority | Effort | Change risk | Confidence | Audited commit |
|---|---|---|---|---|
| P1 | M | LOW | HIGH: code or repository evidence | afd5f4d |

## Current gap

OutputFormat in src/scourpkg/scan_plan.nim exposes text/json/github/doctor only. Scour JSON is not GitLab Code Quality or SARIF.

## Work

Add serializers over the shared finding model for GitLab Code Quality and SARIF 2.1.0. Publish relative paths, severity mapping, stable fingerprints, and rule metadata. Keep report-file failures distinct from findings.

## Acceptance

- [ ] Schema/contract tests cover clean arrays, dirty findings, path escaping, missing locations, and stable fingerprints.
- [ ] GitLab artifacts use artifacts:reports:codequality.
- [ ] GitHub SARIF instructions state availability and token requirements.
- [ ] Logs/artifacts remain usable where native code scanning is unavailable.
- [ ] No secret content is emitted.

## Scope and verification

src/scourpkg/{scan_plan,cli,config,output}.nim, focused serializers, tests/test_cli_setup.nim, CI examples.

Run `nimble test -y` for core changes and `bash tests/test_distribution.sh` for integration changes. Add the named regression cases. Record real pipeline/artifact evidence where required.

Readiness item 014.

## Dependencies

[#38](https://github.com/carsonSgit/scour/issues/38).
