# Changelog

All notable changes to this project are documented here.
This project adheres to [Semantic Versioning](https://semver.org).

## [0.2.0] - 2026-06-02

### Build & CI
- Auto-release on merge to main via git-cliff

### Features
- Add Scour Doctor score and doctor output format

## [0.1.0] - 2026-06-02

### Bug Fixes
- Honor end-of-options marker for explicit paths

### Build & CI
- Add build and test workflow
- Add release workflow
- Package five platform releases

### Documentation
- Add initial commands and scan flow
- Add issue and pull request templates
- Document repository automation
- Document CI output behavior
- Document rule discovery commands
- Document triage and fixture regression coverage
- Document distribution workflows
- Add interactive rule demo

### Features
- Add CI output and failure behavior
- Add rule catalog and discovery commands
- Add grouped triage scan command
- Add action and verified installer

### Miscellaneous
- Update .gitignore

### Other
- Nimble setup
- Add real CLI scan orchestration
- Add issue model and text output
- Load rule settings
- Add branch hygiene checks
- Run hygiene rules in scans
- Add duplicate lockfile detection
- Add dockerignore missing detection
- Add generated tracked file detection
- Run repository hygiene checks
- Update CLI diagram to reflect new scan flow
- Add cross-reference drift detection
- Avoid pcre dependency for env drift
- Implement config rule overrides
- Delete PRD.md

### Testing
- Cover CLI scaffold
- Cover hygiene scan behavior
- Cover rule discovery CLI behavior
- Add fixture repository regression harness
- Lock scan modes and rule families with snapshots
- Rebuild fixture binary once per test process

