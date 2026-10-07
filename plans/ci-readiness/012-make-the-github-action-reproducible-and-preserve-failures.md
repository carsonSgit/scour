# Make the GitHub Action reproducible and preserve failures

Issue: [#42](https://github.com/carsonSgit/scour/issues/42).

| Priority | Effort | Change risk | Confidence | Audited commit |
|---|---|---|---|---|
| P0 | M | MED | HIGH: code or repository evidence | afd5f4d |

## Current gap

README.md advertises scour@v1, but git ls-remote reports only v0.x tags. action.yml:29 downloads latest independently of the Action revision. scripts/run-action.sh:31 suppresses first-scan errors and performs additional scans.

## Work

Publish an existing, supported Action reference and bind its default binary to that release. Keep explicit version overrides. Render reports from one scan result where feasible; distinguish findings from fatal errors before parsing outputs. Validate runner prerequisites.

## Acceptance

- [ ] The copied quickstart resolves and reports its expected executable version.
- [ ] Repeated pinned runs use identical versions.
- [ ] Real-binary fixtures cover statuses 0/1/2, malformed/empty JSON, missing prerequisites, triage, thresholds, and invalid inputs.
- [ ] Fatal diagnostics survive and counters never become null success outputs.
- [ ] Document Linux-only Action support until other runners are tested.

## Scope and verification

action.yml, scripts/run-action.sh, tests/test_distribution.sh, README.md, site/src/components/GithubAction.tsx.

Run `nimble test -y` for core changes and `bash tests/test_distribution.sh` for integration changes. Add the named regression cases. Record real pipeline/artifact evidence where required.

Readiness item 012.

## Dependencies

[#32](https://github.com/carsonSgit/scour/issues/32), [#38](https://github.com/carsonSgit/scour/issues/38).
