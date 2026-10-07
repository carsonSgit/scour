# Preserve filenames with NUL-delimited Git enumeration

Issue: [#33](https://github.com/carsonSgit/scour/issues/33).

| Priority | Effort | Change risk | Confidence | Audited commit |
|---|---|---|---|---|
| P0 | S | LOW | HIGH: code or repository evidence | afd5f4d |

## Current gap

src/scourpkg/files.nim:79 parses diff output by lines. Both repositoryFiles implementations call plain ls-files and splitLines.

## Work

Use Git -z output and preserve filenames without quote decoding or shell reinterpretation. Apply the same contract to changed/staged candidates and repository inventories.

## Acceptance

- [ ] Regression fixtures cover Unicode, spaces, tabs, quotes, backslashes, and newline filenames where supported.
- [ ] Each filename is scanned once in changed, staged, full, and repository-rule paths.
- [ ] JSON preserves paths and GitHub annotations escape them.
- [ ] Windows cases honor native filename restrictions.

## Scope and verification

src/scourpkg/files.nim, src/scourpkg/rules/repo_hygiene.nim, src/scourpkg/rules/cross_reference.nim, tests/test_cli_setup.nim.

Run `nimble test -y` for core changes and `bash tests/test_distribution.sh` for integration changes. Add the named regression cases. Record real pipeline/artifact evidence where required.

Readiness item 003.

## Dependencies

None.
