# scour

[![CI](https://github.com/carsonSgit/scour/actions/workflows/ci.yml/badge.svg)](https://github.com/carsonSgit/scour/actions/workflows/ci.yml)

Fast pre-merge checks for repo hygiene, config drift, and PR mistakes.

## Commands

```sh
nimble build
nimble run
nimble test
nim c -r src/scour.nim -- --help
```

## Automation

Pull requests and pushes to `main` run the CI workflow:

```sh
nimble build -y
nimble test -y
nim c -r src/scour.nim -- --help
nim c -r src/scour.nim -- --version
```

Releases are built by `.github/workflows/release.yml`. Pushing a `v*` tag publishes release archives for Linux, macOS, and Windows. The release workflow can also be started manually from GitHub Actions to validate packaging before tagging.

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

The same defaults can be stored in `scour.toml`:

```toml
fail_on = "warning"

[output]
format = "github"
```

Explicit CLI flags override config values.

## Rule Discovery

List implemented rules or explain one rule without running a scan:

```sh
scour rules
scour explain console-log
scour --config path/to/scour.toml rules
```

Discovery output includes effective severity and triage values after config
overrides.
