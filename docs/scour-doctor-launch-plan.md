# Scour Doctor Launch Plan

## Goal

Build a Scour experience that mirrors the useful parts of React Doctor for
agents and humans:

- deterministic scans against a repo or diff
- a single score that trends up as issues are fixed
- clear suggested fixes with rule-level explanations
- linked guidance for each finding
- setup paths for local use, agent use, and demo use

This document separates what exists in Scour today from the additional work
needed for launch.

## React Doctor Concept Distilled

React Doctor's current public model is useful in five ways:

1. It gives a deterministic scan result with file, line, rule, severity, and
   recommendation details.
2. It provides a 0-100 score as a trend signal, not as a replacement for
   high-severity findings.
3. It supports normal, diff, and staged workflows so agents can run it after
   edits or before commits.
4. It exposes rule explainability and multiple output surfaces, including JSON,
   annotations, and PR comments.
5. It installs agent-facing skills and optional hooks so the feedback loop can
   happen automatically.

Reference links:

- https://www.react.doctor/docs
- https://www.react.doctor/docs/overview/what-is-a-score
- https://www.react.doctor/docs/reference/cli-reference
- https://www.react.doctor/docs/getting-started/install-for-coding-agents
- https://www.react.doctor/docs/getting-started/how-to-fix-issues
- https://www.react.doctor/docs/ci-and-prs/github-actions-setup

## Current Scour Baseline

Scour already has the core pieces needed for a first "Scour Doctor" demo:

- deterministic scan modes: changed, `--since`, `--staged`, `--all`, and paths
- text, JSON, GitHub, triage, rules, `--score`, `--format doctor`, and `explain <rule>` surfaces
- stable issue summaries with severity and triage counts
- weighted score metadata in JSON output
- rule metadata with purpose, example, and fix text
- release install script and GitHub Action support
- a disposable demo workspace under `demo/`

Scour does not yet have these React Doctor-style capabilities in core:

- issue-linked docs pages per rule
- first-party autofix or patch generation
- agent skill installer or native agent hooks
- sticky PR comment workflow

## Scope and Requirements

### Phase 1: Demoable Scour Doctor Loop — delivered

Deliver a launch-quality demo that shows:

- scan
- score
- doctor-style presentation
- triage
- explain
- fix guidance
- optional side-by-side React Doctor comparison

Required artifacts:

- `demo/install.sh`
- `demo/run.sh`
- `demo/setup.sh`
- `demo/README.md`
- `tests/snapshots/dirty-doctor.txt`
- this plan document

### Phase 2: Product Capability Build-Out

Add first-class Scour Doctor features to the CLI:

- `scour --score` — shipped
- structured score metadata in JSON output — shipped
- `scour --format doctor` mascot/gauge presentation — shipped
- rule docs pages or generated markdown references
- machine-readable fix plans for agents
- optional autofix for safe repo-metadata drift cases

### Phase 3: Launch Surface

Ship:

- local install path
- GitHub Action story
- agent workflow story
- interactive demo workspace
- screencast or terminal walkthrough

## Architectural Approach

### Current-State Architecture

Use existing Scour internals rather than forking a second scanner:

- source of truth for findings: scan pipeline in `src/scourpkg/app.nim`
- source of truth for rule metadata: `src/scourpkg/rule_catalog.nim`
- source of truth for summaries: `src/scourpkg/issues.nim`
- source of truth for JSON output: `src/scourpkg/json_output.nim`

### Proposed Core Extensions

1. Extend score support with config or alternative weighting models when needed.
2. JSON output already carries the score block (shipped):
   - `score.current`
   - `score.max`
   - `score.model`
   - `score.deductions`
3. Add `--explain <rule>` links to generated docs or markdown paths.
4. Add a machine-readable fix-plan surface:
   - ordered issues
   - safe-fix eligibility
   - recommended command or file action

### Autofix Strategy

Keep autofix narrow and explicit:

- safe first targets:
  - `dockerignore-missing`
  - `generated-files` fix suggestions
  - `duplicate-lockfiles` remediation guidance
  - `package-lock-drift` command hints
- defer unsafe code edits until a patch-review flow exists:
  - `env-drift`
  - `ci-command-drift`
  - `readme-command-drift`
  - source-code hygiene rules

Suggested future CLI shape:

```text
scour doctor --all
scour doctor --score
scour doctor --json
scour doctor --plan
scour doctor --fix-safe
scour explain env-drift
```

## Interactive Demo Design

### Audience

This works for three audiences without changing the workspace:

- product walkthroughs
- developer onboarding
- agent workflow demos

### User Flow

1. `bash demo/install.sh`
2. `bash demo/run.sh`
3. Review the generated score and triage report
4. Open the `explain-*.txt` files for linked guidance
5. Optionally run `bash demo/run.sh --with-react-doctor` inside the demo
   environment for a side-by-side comparison
6. Fix one problem and rerun the script to demonstrate score improvement

### Demo Script Behavior

`demo/run.sh` should:

- run Scour against the broken workspace
- save text, JSON, triage, rules, and explain outputs outside the scanned repo
- save the doctor-style presentation output alongside the other reports
- read the score from `scour --score`
- print references to the plan and rule catalog
- optionally run React Doctor through `npx`
- keep the React Doctor sample isolated from the main Scour fixture repo

## Install and Setup Scripts

### Repo-Local Demo Install

```sh
bash demo/install.sh
```

Responsibilities:

- build `./scour` if missing
- recreate `demo/workspace`
- create a reports directory
- print the next command

### Interactive Run

```sh
bash demo/run.sh
```

Responsibilities:

- generate Scour reports
- compute and print the current score
- point users to the highest-value explain outputs

### Optional React Doctor Comparison

```sh
bash demo/run.sh --with-react-doctor
```

This intentionally stays optional because it depends on `npx` and networked
package resolution.

## Example Deliverables for Core Implementation

### Example JSON Shape

```json
{
  "summary": {
    "errors": 6,
    "warnings": 6,
    "info": 0,
    "total": 12,
    "files": 6,
    "triage": {
      "blockers": 2,
      "fix_now": 8,
      "review": 2,
      "cleanup": 0,
      "ignored": 0
    }
  },
  "score": {
    "current": 10,
    "max": 100,
    "model": "weighted-v2-frequency-capped",
    "deductions": {
      "errors": 60,
      "warnings": 24,
      "info": 0,
      "blockers": 6,
      "total": 90
    }
  },
  "issues": []
}
```

### Proposed Future Config Direction

```toml
fail_on = "warning"

[output]
format = "text"

[doctor.score]
model = "weighted-v2-frequency-capped"
error_penalty = 10
warning_penalty = 4
info_penalty = 1
blocker_penalty = 3

[doctor.fix]
safe_autofix = false
write_patch_files = true
```

## Testing Strategy

### Demo Validation

- `nimble build -y`
- `bash demo/install.sh`
- `bash demo/run.sh`

Success means:

- the workspace resets cleanly
- the reports are regenerated
- the score prints consistently
- the explain files exist and match current CLI behavior

### Core Feature Validation

Core score verification:

- add unit coverage for score math
- snapshot JSON with score metadata
- snapshot text output if a summary score is shown there
- preserve exit-code behavior

### Autofix Validation

- keep fixes opt-in
- write changed files to committed fixtures or temp repos
- verify no unrelated files change
- verify rerun reduces findings or improves score

## Documentation and Onboarding

Required docs for launch:

- README section for Scour Doctor
- demo README with one-command setup
- per-rule docs or generated explain references
- short screencast script

Suggested screencast flow:

1. Build and install the demo
2. Show the broken score
3. Open triage output
4. Open one explain file
5. Fix a blocker
6. Rerun and show the score improvement

## Milestones

Because no target launch date was provided, use relative milestones.

### Milestone 1: Demo Completion

- finish demo scripts
- document the React Doctor mapping
- confirm the walkthrough works from a clean clone

### Milestone 2: Core Score

- add configurable score models
- keep `--score` stable for agents
- preserve score metadata in JSON

### Milestone 3: Agent Readiness

- publish a Scour skill template
- add optional git hook setup
- define machine-readable fix-plan output

### Milestone 4: Safe Autofix

- implement safe metadata fixes
- add patch preview mode
- add regression coverage

### Milestone 5: Launch Package

- refresh README and docs
- capture screencast
- tighten GitHub Action messaging
- publish the interactive demo path

## Remaining Gaps to Full Product Launch

- React Doctor comparison is optional and not vendored into this repo.
- There is no current Scour autofix engine.
- There are no first-party per-rule docs pages yet.
- There is no agent installer or native hook integration yet.
