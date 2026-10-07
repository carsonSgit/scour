# Read staged scans from the Git index

Issue: [#36](https://github.com/carsonSgit/scour/issues/36).

| Priority | Effort | Change risk | Confidence | Audited commit |
|---|---|---|---|---|
| P1 | M | MED | HIGH: code or repository evidence | afd5f4d |

## Current gap

src/scourpkg/files.nim:124 selects staged names, but branch_hygiene.nim:96 and security.nim:77 read working-tree bytes.

## Work

Make scan content and auxiliary metadata come from the selected snapshot. Staged scans must read index blobs, including manifests and env examples. Keep full/working-tree scan behavior explicit.

## Acceptance

- [ ] Staged dirty/worktree clean still reports the finding.
- [ ] Staged clean/worktree dirty stays clean for that finding.
- [ ] Partially staged manifests, index-only files, renames, and deletions preserve the selected snapshot.
- [ ] Existing output and severity tests pass.

## Scope and verification

src/scourpkg/scan_plan.nim, src/scourpkg/files.nim, src/scourpkg/rules/*.nim, tests/test_cli_setup.nim.

Run `nimble test -y` for core changes and `bash tests/test_distribution.sh` for integration changes. Add the named regression cases. Record real pipeline/artifact evidence where required.

Readiness item 006.

## Dependencies

[#33](https://github.com/carsonSgit/scour/issues/33), [#35](https://github.com/carsonSgit/scour/issues/35).
