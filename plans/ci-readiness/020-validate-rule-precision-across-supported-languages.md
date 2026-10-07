# Validate rule precision across supported languages

Issue: [#50](https://github.com/carsonSgit/scour/issues/50).

| Priority | Effort | Change risk | Confidence | Audited commit |
|---|---|---|---|---|
| P1 | M | MED | HIGH: code or repository evidence | afd5f4d |

## Current gap

src/scourpkg/source_text.nim uses a shared lexical mask for multiple languages. branch_hygiene.nim uses substring checks; isTestPath at line 28 misses names such as test_api.py. Existing language fixtures cover only selected positive forms.

## Work

Build a table of supported rule/language forms and add regression fixtures for real syntax before broadening claims. Correct confirmed false positives/negatives within existing rules. Keep unsupported constructs explicit and avoid new rule families.

## Acceptance

- [ ] Fixtures cover Python test_ names, comments, regex literals, multiline strings, template interpolation, PHP comment forms, token boundaries, test skips, and intentional examples.
- [ ] Tests identify which syntax is supported.
- [ ] Manual-only findings remain manual.
- [ ] Secret-output redaction checks cover every renderer and future patch report.
- [ ] nimble test -y passes the added cases.

## Scope and verification

src/scourpkg/source_text.nim, src/scourpkg/rules/branch_hygiene.nim, src/scourpkg/rules/security.nim, tests/test_cli_setup.nim.

Run `nimble test -y` for core changes and `bash tests/test_distribution.sh` for integration changes. Add the named regression cases. Record real pipeline/artifact evidence where required.

Readiness item 020.

## Dependencies

None.
