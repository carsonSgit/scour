# Add baseline adoption and scoped finding suppressions

Issue: [#47](https://github.com/carsonSgit/scour/issues/47).

| Priority | Effort | Change risk | Confidence | Audited commit |
|---|---|---|---|---|
| P1 | M | MED | HIGH: code or repository evidence | afd5f4d |

## Current gap

Current controls are global rule overrides and path exclusions. There is no finding baseline; triage ignored is presentation metadata and hasFailingIssues still uses severity.

## Work

Add an explicit baseline generated from a completed scan, then gate only new findings when that baseline is selected. Add narrowly scoped suppressions with a reason and expiry. Show suppressed counts separately and validate stale/malformed records.

## Acceptance

- [ ] An existing dirty repository can adopt Scour while a new matching-severity finding still fails.
- [ ] Line shifts preserve baseline identity; distinct findings remain distinct.
- [ ] Expired suppressions become visible.
- [ ] Baseline generation refuses incomplete scans.
- [ ] Explicit refresh is the only way to accept new findings.
- [ ] Normal scans preserve existing threshold semantics.

## Scope and verification

src/scourpkg/{issues,config,cli,app,json_output}.nim, baseline support, tests/test_cli_setup.nim.

Run `nimble test -y` for core changes and `bash tests/test_distribution.sh` for integration changes. Add the named regression cases. Record real pipeline/artifact evidence where required.

Readiness item 015.

## Dependencies

[#38](https://github.com/carsonSgit/scour/issues/38).
