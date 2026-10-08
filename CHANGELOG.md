# Changelog

All notable changes to this project are documented here.
This project adheres to [Semantic Versioning](https://semver.org).

## [0.4.10] - 2026-10-08

### Other
- Fix version match string and Windows packaging steps

## [0.4.9] - 2026-10-08

### Other
- Fix release-artifact version comparison and Windows verification packaging

## [0.4.8] - 2026-10-08

### Bug Fixes
- YAML syntax in release and action workflows

### Other
- Align version assertions with the v0.4.7 release

## [0.4.7] - 2026-10-08

### Other
- Sync scour.nimble with published 0.4.6 release state

## [0.4.6] - 2026-10-08

### Other
- Reference issue numbers without repo-prefix assumptions in loop prompts
- Rename loop branch scheme to feature/scour-N and update guide

## [0.4.5] - 2026-10-07

### Other
- Let review sessions rerun tests under workspace-write with redirected caches

## [0.4.4] - 2026-10-07

### Other
- Permit plugin state under .omo in loop cleanliness gate

## [0.4.3] - 2026-10-07

### Other
- Fix loop session checks to count retried commands by final exit

## [0.4.2] - 2026-10-07

### Other
- Add CI-readiness roadmap and implementation loop controller

## [0.4.1] - 2026-10-07

### Other
- Add multi-language rule coverage, secret scanning, and frequency-capped

- Extend debugger/skipped/focused-test and env-var detection to Python,
  Ruby, PHP, Go, Rust, JVM, and .NET conventions, masking strings and
  comments so matches only fire on real code
- Add hardcoded-secret, tracked-env-file, dependency-lock-drift, and
  unpinned-github-action rules, bringing the catalog to 17 rules
- Replace the weighted-v1 score model with a frequency-capped model so
  one noisy rule can no longer erase the score's visibility into other
  issues
- Default-ignore node_modules/vendor/.venv/etc. during full scans and
  update docs, site copy, and snapshots to match

## [0.4.0] - 2026-06-15

### Features
- Hero visuals and crt

## [0.3.1] - 2026-06-12

### Bug Fixes
- Support Git Bash Windows installer

## [0.3.0] - 2026-06-10

### Bug Fixes
- Drop bottom border on both final rules-grid cells

### Build & CI
- Deploy landing page to GitHub Pages

### Features
- Scaffold Vite + React + Tailwind landing page
- Theme hook with system default and localStorage persistence
- Sticky nav with scroll-aware background and theme toggle
- Hero with install command and copy feedback
- Terminal demo timeline data with accurate severities
- Animated terminal demo with replay
- Rules grid with catalog-accurate severities
- GitHub Action section with hand-highlighted YAML
- Assemble landing page with footer
- Breathing dither shimmer in hero with masked bottom fade
- Waking severity-dot dither and floating nav
- Severity dots wake along a sweeping scan wave
- Full-page diagonal scan wave with organic band width
- Sleeker dot animation

### Miscellaneous
- Migrate to pnpm

## [0.2.0] - 2026-06-02

### Build & CI
- Auto-release on merge to main via git-cliff

### Features
- Add Scour Doctor score and doctor output format

## [0.1.0] - 2026-06-02

### Bug Fixes
- Honor end-of-options marker for explicit paths
- Drop bottom border on both final rules-grid cells
- Support Git Bash Windows installer
- Honor end-of-options marker for explicit paths

### Build & CI
- Add build and test workflow
- Add release workflow
- Package five platform releases
- Auto-release on merge to main via git-cliff
- Deploy landing page to GitHub Pages
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
- Add Scour Doctor score and doctor output format
- Scaffold Vite + React + Tailwind landing page
- Theme hook with system default and localStorage persistence
- Sticky nav with scroll-aware background and theme toggle
- Hero with install command and copy feedback
- Terminal demo timeline data with accurate severities
- Animated terminal demo with replay
- Rules grid with catalog-accurate severities
- GitHub Action section with hand-highlighted YAML
- Assemble landing page with footer
- Breathing dither shimmer in hero with masked bottom fade
- Waking severity-dot dither and floating nav
- Severity dots wake along a sweeping scan wave
- Full-page diagonal scan wave with organic band width
- Sleeker dot animation
- Hero visuals and crt
- Add CI output and failure behavior
- Add rule catalog and discovery commands
- Add grouped triage scan command
- Add action and verified installer

### Miscellaneous
- Update .gitignore
- Migrate to pnpm
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
- Add multi-language rule coverage, secret scanning, and frequency-capped

- Extend debugger/skipped/focused-test and env-var detection to Python,
  Ruby, PHP, Go, Rust, JVM, and .NET conventions, masking strings and
  comments so matches only fire on real code
- Add hardcoded-secret, tracked-env-file, dependency-lock-drift, and
  unpinned-github-action rules, bringing the catalog to 17 rules
- Replace the weighted-v1 score model with a frequency-capped model so
  one noisy rule can no longer erase the score's visibility into other
  issues
- Default-ignore node_modules/vendor/.venv/etc. during full scans and
  update docs, site copy, and snapshots to match
- Add CI-readiness roadmap and implementation loop controller
- Fix loop session checks to count retried commands by final exit
- Permit plugin state under .omo in loop cleanliness gate
- Let review sessions rerun tests under workspace-write with redirected caches
- Apply scan filters consistently for Scour #31
- Preserve filtered lockfile context for Scour #31
- Use valid workflow fixture for Scour #31
- Preserve git filenames with NUL-delimited enumeration (#33)
- Deterministic revision selection for CI (#32)
- Validate TOML values and implement accepted scan settings (#34)
- Bound filesystem reads and expose incomplete scans (#35)
- Read staged scans from the git index snapshot (#36)
- Version machine reports and include scan coverage (#38)
- Scope drift checks to workspaces and parse CI command context (#37)
- Add opt-in fix planning and patch application (#39)
- Implement the first bounded cleanup rules (#40)
- Deliver cleanup patches through CI without write credentials (#41)
- Make the GitHub Action reproducible and preserve failures (#42)
- Gate releases on actual artifact validation (#43)
- Make release publication retryable and document its trigger (#48)
- Export GitLab Code Quality and SARIF reports (#46)
- Include the declared MIT license in packages (#49)
- Validate rule precision across supported languages (#50)
- Add baseline adoption and scoped finding suppressions (#47)
- Ship GitLab and generic CI jobs with install prerequisite guards (#45 partial)
- Publish and test the user onboarding contract (#51 partial)
- Establish supported runtimes and portable CI distribution (#44 partial)
- Add non-root container image for portable CI (#44 follow-up)
- Update roadmap status: 21 issues implemented and PR'd
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
- Cover hygiene scan behavior
- Cover rule discovery CLI behavior
- Add fixture repository regression harness
- Lock scan modes and rule families with snapshots
- Rebuild fixture binary once per test process

