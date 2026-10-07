# Apply scan exclusions and size filters consistently

Issue: [#31](https://github.com/carsonSgit/scour/issues/31).

| Priority | Effort | Change risk | Confidence | Audited commit |
|---|---|---|---|---|
| P0 | S | LOW | HIGH: code or repository evidence | afd5f4d |

## Current gap

src/scourpkg/files.nim:135 returns before filters at line 148. Repository rules use unfiltered inventory in src/scourpkg/rules/repo_hygiene.nim:141 and src/scourpkg/rules/cross_reference.nim:531.

## Work

Route every candidate-selection branch through configured filters. Keep context inventory separate from reportable scope so ignored files can provide context without generating findings.

## Acceptance

- [ ] Automatic origin/main, main, and master scans honor ignore.paths and max_file_size.
- [ ] Explicit, staged, changed, and full scans apply the same policy.
- [ ] Every repository-wide rule suppresses findings anchored in ignored paths.
- [ ] Nonignored files still validate against required context.

## Scope and verification

src/scourpkg/files.nim, src/scourpkg/rules/repo_hygiene.nim, src/scourpkg/rules/cross_reference.nim, tests/test_cli_setup.nim.

Run `nimble test -y` for core changes and `bash tests/test_distribution.sh` for integration changes. Add the named regression cases. Record real pipeline/artifact evidence where required.

Readiness item 001.

## Dependencies

None.
