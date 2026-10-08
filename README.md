# scour

[![CI](https://github.com/carsonSgit/scour/actions/workflows/ci.yml/badge.svg)](https://github.com/carsonSgit/scour/actions/workflows/ci.yml)

Fast pre-merge checks for repo hygiene, config drift, and PR mistakes.

## Configuration

`scour.toml` (or `--config <path>`) supports:

```toml
fail_on = "error"          # error, warning, or info

[scan]
max_file_size = "1 MB"     # bytes, KB, or MB
mode = "full"              # full or staged; CLI flags win
respect_gitignore = true   # exclude gitignored files from scanned candidates
follow_symlinks = false    # include symlinked files and directories

[ignore]
paths = ["dist/", "build/**"]

[fix.pin_action]
"actions/checkout@v4" = "5a4ac9002d0be2fb38bd78e4b4dbde5606d7042f"
```

Scan options:             --fix plans fixes to scour-fix.patch without touching
files; --fix-apply applies them after content-hash verification and reruns the scan.
Supported fixes stay bounded to: removing console.log and debugger lines, creating
missing .dockerignore files from dockerignore_entries, and pinning GitHub Action
references through [fix.pin_action] (40-character SHA-1 values only).

Path patterns match repository-relative paths with `/` separators; backslashes
are normalized. `path` and `path/` match the file or directory and everything
below it, `path/**` matches everything below the prefix, and `#` starts a
comment unless it is inside a quoted string.

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

Use Scour in a Linux GitHub Actions job. Pin both the Action reference and the
binary version so repeated runs resolve identical archives:

```yaml
- uses: carsonSgit/scour@v0.4.5
  with:
    version: v0.4.5
    fail-on: warning
    triage: "true"
```

Inputs are `since`, `staged`, `all`, `format`, `fail-on`, `config`, `version`,
`exit-zero`, `triage`, `fix` (none/preview/apply), and `patch-name`. Outputs are
`total`, `errors`, `warnings`, `info`, `blockers`, `fix-now`, `review`,
`cleanup`, `json`, `patch-path`, `before-path`, `after-path`, `fixed`,
`remaining`, and `unfixable`. Linux runners only until other runners are tested.
The action never touches Git refs; fixes ship as downloaded artifacts.

## Releases

The release workflow publishes when `main` advances and detects a releasable
Conventional Commit. Pushing to `main` prepares one candidate version (git-cliff
bumps from commit history), builds five platform archives on their runners,
validates the package contents, verifies checksums, and only then publishes
the GitHub release. No `v*` tag is needed by hand; the workflow creates one at
the release commit. Dispatch `mode: validate` runs the full prepare/build/validate
path with no commits, tags, or publications.

Retry after a build or upload failure: run the workflow manually for the same
version. The workflow detects the existing release, inspects its assets, and
either stops (nothing missing) or republishes only the missing assets without a
further version bump. Invalid versions fail during prepare before any write.

Before tagging by hand instead, run the workflow with `mode: validate` to validate
packaging on all five hosted runners.

Scour is MIT-licensed (see `LICENSE`).

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

## Container Image

`container/Dockerfile` builds from precompiled binaries and runs Scour as the
dedicated `scour` user with git, tar, gzip, and curl installed. Mount the repo
read-only (`-v "$PWD":/workspace:ro`) and send outputs to a writable directory:

```sh
docker run --rm -v "$PWD":/workspace:ro -w /workspace scour:v0.4.5 --all --format json > /host/scan.json
```

Verifying the binary's libc dependencies (Alpine/musl): run the musl-static
build (not yet published) or build from source inside the image.

`objdump -p scour-linux-x86_64 | grep -A2 'GLIBC'` verifies glibc requires
against the documented minimum (2.17 for the Alpine/debian-slim mix shipped).


Use the same binary from a version-pinned release. The job needs no Nim
compiler, clones with enough history for `scour --since` (or `--all`), and
retains reports when Scour fails:

```yaml
scour:
  image: curlimages/curl:8.5.0
  stage: test
  script:
    - curl -fsSL "https://github.com/carsonSgit/scour/releases/download/v0.4.5/scour-v0.4.5-linux-x86_64.tar.gz" -o scour.tar.gz
    - curl -fsSL "https://github.com/carsonSgit/scour/releases/download/v0.4.5/scour-v0.4.5-checksums.txt" | grep " scour.tar.gz" - > checksums.txt || true
    - sha256sum scour.tar.gz | grep -q "$(cat checksums.txt)"
    - tar -xzf scour.tar.gz
    - git fetch --unshallow || git fetch --depth=50 origin main || true
    - ./scour --since "$CI_MERGE_REQUEST_DIFF_BASE_SHA" --format codequality > codequality.json || true
  artifacts:
    when: always
    reports:
      codequality: codequality.json
    paths:
      - scour-fix.patch
      - scan-before.json
```

Generic CI (any shell, any provider): install the binary through
`scripts/install.sh` (honors `FAKE`, `NO_PROXY`, `HTTPS_PROXY` through curl;
preinstall `curl`), run `scour --all --format json > scan.json`, and **retain
`scan.json` and `scour-fix.patch` as build artifacts with
`when: always` so fatal failures also keep their evidence.** To apply a patch
that CI produced, pull the artifact and run
`git apply scour-fix.patch && git commit && git push` locally; CI never pushes,
commits, or force-requests changes on your behalf. Read-only fork pipelines need
no write token because all writes land in artifacts.

For SARIF ingestion (GitHub code scanning needs `security-events: write` and the
`github/codeql-action/upload-sarif` step pointed at `output.sarif`), run
`scour --format sarif > output.sarif`. Where native code scanning is
unavailable, attach the artifact and read it directly.

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
