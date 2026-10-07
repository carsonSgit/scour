# Version machine reports and include scan coverage

Issue: [#38](https://github.com/carsonSgit/scour/issues/38).

| Priority | Effort | Change risk | Confidence | Audited commit |
|---|---|---|---|---|
| P1 | M | LOW | HIGH: code or repository evidence | afd5f4d |

## Current gap

src/scourpkg/json_output.nim:21 emits summary, score, and issues without schema/tool version, revision selection, coverage, or stable finding IDs.

## Work

Add an additive, versioned report contract with tool version, effective scope/revisions, scanned/skipped counts, completion state, stable finding fingerprints, and fixability metadata. Publish a schema. Preserve existing summary keys used by the Action.

## Acceptance

- [ ] Snapshots and schema validation cover clean, dirty, empty, skipped, and incomplete scans.
- [ ] Fingerprints survive unrelated line shifts but distinguish separate findings.
- [ ] No credential bytes appear in any renderer or fingerprint input serialized to output.
- [ ] The Action consumes existing keys unchanged.
- [ ] Breaking report changes require a new schema version.

## Scope and verification

src/scourpkg/{json_output,issues,scan_plan,app}.nim, tests/test_cli_setup.nim, tests/snapshots/.

Run `nimble test -y` for core changes and `bash tests/test_distribution.sh` for integration changes. Add the named regression cases. Record real pipeline/artifact evidence where required.

Readiness item 008.

## Dependencies

[#32](https://github.com/carsonSgit/scour/issues/32), [#35](https://github.com/carsonSgit/scour/issues/35).
