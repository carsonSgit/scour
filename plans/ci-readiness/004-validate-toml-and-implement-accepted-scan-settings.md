# Validate TOML and implement accepted scan settings

Issue: [#34](https://github.com/carsonSgit/scour/issues/34).

| Priority | Effort | Change risk | Confidence | Audited commit |
|---|---|---|---|---|
| P0 | M | MED | HIGH: code or repository evidence | afd5f4d |

## Current gap

src/scourpkg/config.nim:86 splits quoted arrays on commas; line 191 treats quoted # as a comment. Lines 299-300 silently discard mode, respect_gitignore, and follow_symlinks.

## Work

Use a TOML parser that preserves quoted values, then validate the supported schema. Implement scan.mode and respect_gitignore with explicit tracked/untracked semantics. Coordinate follow_symlinks with file-boundary work. Reject unsupported values and duplicate keys. Preserve CLI-over-config precedence.

## Acceptance

- [ ] Quoted #, comma-containing paths, escapes, literal strings, multiline arrays, duplicate keys, wrong types, and size overflow have fixtures.
- [ ] Each accepted scan setting changes behavior.
- [ ] Invalid values exit 2.
- [ ] Ignored untracked files are excluded while tracked generated files remain available to repository hygiene rules.
- [ ] Document the supported path-pattern syntax.

## Scope and verification

src/scourpkg/config.nim, src/scourpkg/scan_plan.nim, src/scourpkg/files.nim, tests/test_cli_setup.nim.

Run `nimble test -y` for core changes and `bash tests/test_distribution.sh` for integration changes. Add the named regression cases. Record real pipeline/artifact evidence where required.

Readiness item 004.

## Dependencies

[#31](https://github.com/carsonSgit/scour/issues/31).
