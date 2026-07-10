# scour

[![CI](https://github.com/carsonSgit/scour/actions/workflows/ci.yml/badge.svg)](https://github.com/carsonSgit/scour/actions/workflows/ci.yml)

Fast pre-merge checks for repo hygiene, config drift, and PR mistakes.

## Commands

```sh
nimble build
nimble run
nimble test
./scour --help
```

## Automation

Pull requests and pushes to `main` run the CI workflow:

```sh
nimble build -y
nimble test -y
bash tests/test_distribution.sh
./scour --help
./scour --version
```

## Install

Install the latest Linux or macOS release:

```sh
curl -fsSL https://raw.githubusercontent.com/carsonSgit/scour/main/scripts/install.sh | sh
```

Pin a release or change the destination with `SCOUR_VERSION=v0.2.0` and
`SCOUR_INSTALL_DIR=/usr/local/bin`. Release archives support Linux x86_64,
Linux ARM64, macOS Intel, macOS Apple Silicon, and Windows x86_64. Windows
users should download the ZIP archive from GitHub Releases and place
`scour.exe` on `PATH`.

## GitHub Action

Use Scour in a Linux GitHub Actions job:

```yaml
- uses: carsonSgit/scour@v1
  with:
    fail-on: warning
    triage: "true"
```

Inputs are `since`, `staged`, `all`, `format`, `fail-on`, `config`, `version`,
`exit-zero`, and `triage`. Outputs are `total`, `errors`, `warnings`, `info`,
`blockers`, `fix-now`, `review`, `cleanup`, and `json`.

## Releases

Releases are built by `.github/workflows/release.yml`. Pushing a `v*` tag
publishes five platform archives and a SHA-256 checksum file. Before tagging,
run the workflow manually with the intended version to validate packaging on
all five hosted runners.

## CI Output

Scour emits human-readable text by default. CI integrations can select stable JSON
or GitHub workflow annotations:

```sh
scour --format json --fail-on warning
scour --format github
scour --exit-zero
```

`--fail-on` accepts `error`, `warning`, or `info`. Findings at or above that
threshold exit `1`; malformed arguments and invalid config exit `2`.
`--exit-zero` suppresses issue-based failures only.

For a React Doctor-style presentation over the same Scour findings:

```sh
scour --format doctor
scour --format doctor --all
```

This report uses Scour's own issue and score data to render a gauge, an
emoticon-style indicator, a concise issue list, and prioritized next steps.
The `weighted-v2-frequency-capped` score counts every rule but applies
diminishing penalties after repeated findings from the same rule, so a large
generated directory cannot hide the breadth of other repository problems.

The same defaults can be stored in `scour.toml`:

```toml
fail_on = "warning"

[output]
format = "github"
```

Explicit CLI flags override config values.

## Triage

Group findings into a deterministic fix-order report while preserving normal
scan selectors and exit codes:

```sh
scour triage --all
scour triage --staged
scour triage --since main
```

`triage` uses its own text renderer, so it rejects explicit `--format` flags.

## Regression Suite

`nimble test` builds Scour and runs the real binary against committed clean and
dirty fixture repositories. Exact snapshots cover text, JSON, GitHub
annotations, triage output, staged changes, ref comparisons, explicit paths,
config overrides, thresholds, and exit-zero behavior.

## Interactive Demo

Create a disposable nested repository that demonstrates the original 13-rule
scan set:

```sh
bash demo/install.sh
bash demo/run.sh
```

The first two scans show the 12 static findings. The default scan also exposes
`package-lock-drift` through a staged manifest-only edit under `staged/`. Run
`demo/install.sh` again to reset the workspace and rebuild reports.

The demo scripts persist Scour outputs under
`demo/reports`, calculate a launch-demo
score with `scour --score`, write a React Doctor-style report with
`scour --format doctor`, and point to rule explanations for the walkthrough.
The optional `--with-react-doctor` path runs React Doctor against a separate
sample workspace under `demo/react-doctor-workspace` so the Scour baseline
stays stable.
The broader launch
roadmap for turning that demo into a first-class Scour Doctor product lives in
`docs/scour-doctor-launch-plan.md`.

## Rule Discovery

List implemented rules or explain one rule without running a scan:

```sh
scour rules
scour explain console-log
scour --config path/to/scour.toml rules
```

Discovery output includes effective severity and triage values after config
overrides.

## Rule Coverage

Scour ships 17 configurable rules. Source hygiene covers JavaScript,
TypeScript, Python, Ruby, PHP, Go, Rust, JVM, and .NET test conventions.
Repository checks cover tracked env files, generated output, Docker context,
and duplicate package-manager state. Cross-reference checks validate env
contracts, documented and CI commands, GitHub Action pinning, Node locks, and
existing Cargo, Ruby, Composer, Go, Elixir, Poetry, uv, and PDM lockfiles.
High-confidence provider-token and private-key signatures are checked without
printing credential values in findings.
