# Deliver cleanup patches through CI without write credentials

Issue: [#41](https://github.com/carsonSgit/scour/issues/41).

| Priority | Effort | Change risk | Confidence | Audited commit |
|---|---|---|---|---|
| P0 | M | MED | HIGH: code or repository evidence | afd5f4d |

## Current gap

action.yml has no fix inputs or patch outputs. scripts/run-action.sh only emits annotations, counters, and an optional triage summary.

## Work

Expose preview/apply inputs, changed-file counts, patch paths, and before/after reports. Use retained artifacts as the default delivery path for GitHub, GitLab, and generic jobs. Document how maintainers apply the patch locally.

## Acceptance

- [ ] Read-only fork pipelines can generate downloadable patches without repository-write tokens.
- [ ] Reports and patches survive both finding failures and fatal execution failures when available.
- [ ] Exit status reflects the documented post-fix contract.
- [ ] Fixtures prove no push, commit, or unrequested repository command occurs.
- [ ] Automatic remote commits remain a separately authorized integration, not a prerequisite.

## Scope and verification

action.yml, scripts/run-action.sh, CI templates, tests/test_distribution.sh, README.md.

Run `nimble test -y` for core changes and `bash tests/test_distribution.sh` for integration changes. Add the named regression cases. Record real pipeline/artifact evidence where required.

Readiness item 011.
## Dependencies

[#39](https://github.com/carsonSgit/scour/issues/39), [#40](https://github.com/carsonSgit/scour/issues/40), [#38](https://github.com/carsonSgit/scour/issues/38).
