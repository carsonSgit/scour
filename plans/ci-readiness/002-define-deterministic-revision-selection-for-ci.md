# Define deterministic revision selection for CI

Issue: [#32](https://github.com/carsonSgit/scour/issues/32).

| Priority | Effort | Change risk | Confidence | Audited commit |
|---|---|---|---|---|
| P0 | M | MED | HIGH: code or repository evidence | afd5f4d |

## Current gap

src/scourpkg/scan_plan.nim:72 defaults Git repositories to changed mode. src/scourpkg/files.nim:130 guesses main/master and silently changes to staged/full scope when comparison fails.

## Work

Define provider-neutral full and explicit base/head scan contracts. CI defaults should scan the full tracked checkout unless a comparison is explicitly supplied. Missing comparison history must produce an actionable error, not a different scope. Keep any history fetching in provider wrappers.

## Acceptance

- [ ] Tests cover default-branch pushes, alternate target branches, detached HEAD, forks, shallow clones, first commits, deleted/renamed files, missing refs, and empty diffs.
- [ ] Explicit comparisons use documented merge-base semantics.
- [ ] Reports identify effective mode, base/head, and scanned count.
- [ ] A dirty main checkout cannot pass because HEAD was compared with itself.

## Scope and verification

src/scourpkg/{cli,scan_plan,files,app}.nim, tests/test_cli_setup.nim.

Run `nimble test -y` for core changes and `bash tests/test_distribution.sh` for integration changes. Add the named regression cases. Record real pipeline/artifact evidence where required.

Readiness item 002.

## Dependencies

[#31](https://github.com/carsonSgit/scour/issues/31).
