# Add opt-in fix planning and patch application

Issue: [#39](https://github.com/carsonSgit/scour/issues/39).

| Priority | Effort | Change risk | Confidence | Audited commit |
|---|---|---|---|---|
| P0 | L | HIGH | HIGH: code or repository evidence | afd5f4d |

## Current gap

src/scourpkg/app.nim:51 only scans and renders. CliOptions and RuleDefinition contain no executable fix contract. docs/scour-doctor-launch-plan.md explicitly lists the missing autofix engine.

## Work

Add explicit fix-plan, patch-preview, and apply modes over the existing findings. Default scans remain read-only. Record original content hashes and file boundaries; refuse stale or overlapping edits. Write atomically and rerun the scan to determine the final finding status.

## Acceptance

- [ ] Preview writes a patch artifact without modifying checkout files.
- [ ] Apply changes only approved in-root paths and preserves unrelated bytes and modes.
- [ ] Stale content, conflicts, unsafe links, and write failures stop with a controlled error.
- [ ] A second apply changes nothing.
- [ ] Post-fix reports separate fixed, remaining, and unfixable findings; exit 1 follows remaining findings and exit 2 follows execution errors.

## Scope and verification

src/scourpkg/{cli,scan_plan,app,rule_catalog,issues}.nim, a focused fix module, tests/test_cli_setup.nim.

Run `nimble test -y` for core changes and `bash tests/test_distribution.sh` for integration changes. Add the named regression cases. Record real pipeline/artifact evidence where required.

Readiness item 009.

## Dependencies

[#35](https://github.com/carsonSgit/scour/issues/35), [#38](https://github.com/carsonSgit/scour/issues/38).
