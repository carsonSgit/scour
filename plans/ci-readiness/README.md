# Scour CI readiness

Audited afd5f4d on 2026-10-06. Goal: install into GitHub, GitLab, or generic CI; scan predictably; apply supported cleanup; retain reviewable patches.

21 issues published to carsonSgit/scour. The pre-publication duplicate check found 0 open issues. Closed initial implementation issues are historical context, not unfinished work.

## Execution order

Fix scan correctness and file boundaries first. Add report contracts and the fix engine next. Wire provider integrations and validate releases before publishing the onboarding contract.

P0 marks launch blockers. P1 marks adoption and supported-runtime work; finish any P1 required by the advertised support matrix before launch. S means hours, M roughly a day, L multiple days, including tests. Estimates are provisional.

| Draft | Work | Priority | Effort | Dependencies | Status |
|---|---|---|---|---|---|
| [001](001-apply-scan-exclusions-and-size-filters-consistently.md) | [Apply scan exclusions and size filters consistently](https://github.com/carsonSgit/scour/issues/31) | P0 | S | None | TODO |
| [002](002-define-deterministic-revision-selection-for-ci.md) | [Define deterministic revision selection for CI](https://github.com/carsonSgit/scour/issues/32) | P0 | M | 001 | TODO |
| [003](003-preserve-git-filenames-with-nul-delimited-enumeration.md) | [Preserve filenames with NUL-delimited Git enumeration](https://github.com/carsonSgit/scour/issues/33) | P0 | S | None | TODO |
| [004](004-validate-toml-and-implement-accepted-scan-settings.md) | [Validate TOML and implement accepted scan settings](https://github.com/carsonSgit/scour/issues/34) | P0 | M | 001 | TODO |
| [005](005-bound-filesystem-reads-and-expose-incomplete-scans.md) | [Bound filesystem reads and expose incomplete scans](https://github.com/carsonSgit/scour/issues/35) | P0 | M | 001, 004 | TODO |
| [006](006-read-staged-scans-from-the-git-index.md) | [Read staged scans from the Git index](https://github.com/carsonSgit/scour/issues/36) | P1 | M | 003, 005 | TODO |
| [007](007-scope-drift-checks-to-workspaces-and-parse-ci-command-context.md) | [Scope drift checks to workspaces and parse CI command context](https://github.com/carsonSgit/scour/issues/37) | P1 | L | 001, 004 | TODO |
| [008](008-version-machine-reports-and-include-scan-coverage.md) | [Version machine reports and include scan coverage](https://github.com/carsonSgit/scour/issues/38) | P1 | M | 002, 005 | TODO |
| [009](009-add-opt-in-fix-planning-and-patch-application.md) | [Add opt-in fix planning and patch application](https://github.com/carsonSgit/scour/issues/39) | P0 | L | 005, 008 | TODO |
| [010](010-implement-the-first-bounded-cleanup-rules.md) | [Implement the first bounded cleanup rules](https://github.com/carsonSgit/scour/issues/40) | P0 | L | 009 | TODO |
| [011](011-deliver-cleanup-patches-through-ci-without-write-credentials.md) | [Deliver cleanup patches through CI without write credentials](https://github.com/carsonSgit/scour/issues/41) | P0 | M | 009, 010, 008 | TODO |
| [012](012-make-the-github-action-reproducible-and-preserve-failures.md) | [Make the GitHub Action reproducible and preserve failures](https://github.com/carsonSgit/scour/issues/42) | P0 | M | 002, 008 | TODO |
| [013](013-ship-gitlab-and-generic-ci-jobs.md) | [Ship jobs for GitLab and generic CI](https://github.com/carsonSgit/scour/issues/45) | P0 | M | 002, 011, 012, 016 | TODO |
| [014](014-export-gitlab-code-quality-and-sarif-reports.md) | [Export reports for GitLab Code Quality and SARIF](https://github.com/carsonSgit/scour/issues/46) | P1 | M | 008 | TODO |
| [015](015-add-baseline-adoption-and-scoped-finding-suppressions.md) | [Add baseline adoption and scoped finding suppressions](https://github.com/carsonSgit/scour/issues/47) | P1 | M | 008 | TODO |
| [016](016-establish-supported-runtimes-and-a-portable-ci-distribution.md) | [Establish supported runtimes and a portable CI distribution](https://github.com/carsonSgit/scour/issues/44) | P1 | M | 017 | TODO |
| [017](017-gate-releases-on-actual-artifact-validation.md) | [Gate releases on actual artifact validation](https://github.com/carsonSgit/scour/issues/43) | P0 | M | None | TODO |
| [018](018-make-release-publication-retryable-and-document-its-trigger.md) | [Make release publication retryable and document its trigger](https://github.com/carsonSgit/scour/issues/48) | P0 | M | 017 | TODO |
| [019](019-include-the-declared-mit-license-in-packages.md) | [Include the declared MIT license in packages](https://github.com/carsonSgit/scour/issues/49) | P1 | S | None | TODO |
| [020](020-validate-rule-precision-across-supported-languages.md) | [Validate rule precision across supported languages](https://github.com/carsonSgit/scour/issues/50) | P1 | M | None | TODO |
| [021](021-publish-and-test-the-user-onboarding-contract.md) | [Publish and test the user onboarding contract](https://github.com/carsonSgit/scour/issues/51) | P0 | M | 002, 010, 011, 012, 013, 016, 018, 019, 020 | TODO |

## Observed verification

- `bash tests/test_distribution.sh` exited 0; its installer/action checks use mocked binaries.
- `git ls-remote --tags origin` returned five v0.x tags and no v1 tag.
- Nim and Nimble are absent locally; the core regression suite was not executed.
- Inspection covered CLI, configuration, selection, rule families, reports, Action, installer, release workflow, tests, and launch docs.
- Website visuals, live hosted pipelines, real release binaries, and dependency vulnerability scanning were not audited.

## Provider report contracts

Native reporting work follows [GitLab Code Quality](https://docs.gitlab.com/ci/testing/code_quality/) and [GitHub SARIF](https://docs.github.com/en/code-security/reference/code-scanning/sarif-files/sarif-support). Plain logs and artifacts remain the generic CI contract.

## Considered and excluded

- An AI repair agent, automatic remote commits, native hooks, and new rule families are not prerequisites for the requested CI product.
- Scoring polish and website redesign do not close scan or cleanup gaps.
- A full filesystem scan need not obey gitignore blindly: tracked generated artifacts must remain visible to repository hygiene checks.

## Published issues

Published with user approval to `carsonSgit/scour`, which is public. Draft 005 describes a filesystem boundary gap; draft 021 and other drafts describe product capabilities, not exposed credentials. No secret values or misuse instructions appear in these drafts.
