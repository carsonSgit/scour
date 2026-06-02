# Scan Flow

```text
CLI args
  -> parse options
       --help
       --version
       --staged
       --since <ref>
       --all
       --config <path>
       --format <text|json|github>
       --fail-on <error|warning|info>
       --exit-zero
       --color <auto|always|never>
       triage
       rules
       explain <rule>
       paths...
       reject conflicting scan modes
  -> resolve repo
       git rev-parse --show-toplevel
       outside Git: current working directory
  -> find config
       explicit --config path
       scour.toml
       .scour.toml
       .config/scour.toml
       none
  -> discovery command?
       rules: render every catalog entry with effective severity and triage
       explain <rule>: render catalog metadata and effective config values
       exit before scan-mode selection and candidate collection
  -> choose scan mode
       explicit paths
       staged
       changed since ref
       all
       default inside Git: changed
       default outside Git: all/current directory
  -> collect candidate files
       staged: git diff --cached --name-only --diff-filter=ACMR
       since: git diff --name-only --diff-filter=ACMR <ref>...HEAD
       default changed: origin/main, main, master, staged, all
       all: recursive files under root
       explicit paths: expand files and directories
       always skip .git, missing files, and binary files
       apply config ignore paths after collection
       apply scan.max_file_size to text candidates
  -> build scan plan
       repo root and Git status
       config discovery result
       scan mode
       base ref when selected
       candidate files
  -> run branch hygiene rules on candidate files
       merge-conflict
       debugger
       console-log
       focused-test
       skipped-test
       ts-ignore
       applies rule severity/off and triage overrides
  -> run repository hygiene rules on repository metadata
       inside Git: git ls-files tracked-file inventory
       outside Git: candidate files from the scan plan
       duplicate-lockfiles
       dockerignore-missing
       generated-files
       applies rule severity/off and triage overrides
  -> run cross-reference rules
       candidate files for changed source and package manifests
       repository inventory for tracked docs, workflows, env examples, package metadata, and task files
       env-drift compares literal env usages with configured env example/default files
       env-drift skips configured ignored env vars
       readme-command-drift validates README.md and docs/**/*.md commands against known scripts and targets
       ci-command-drift validates workflow run commands against known scripts and targets
       package-lock-drift checks changed Node package.json files against existing same-directory lockfiles
       applies rule severity/off and triage overrides
  -> combine issues
       branch hygiene issues
       repository hygiene issues
       cross-reference issues
  -> resolve output and failure settings
       output.color config default applies unless --color was passed
       output.format config default applies unless --format was passed
       top-level fail_on config default applies unless --fail-on was passed
  -> render selected output
       text: pass message, issue rows, suggestions, and summary
       json: stable summary, triage counts, and issue fields
       github: workflow annotations, no output for a clean scan
       triage: deterministic non-empty groups followed by triage counts
  -> choose exit code
       fatal arguments or config: 2
       findings at or above failure threshold: 1
       --exit-zero overrides issue-based failure only
       otherwise: 0
  -> text output details
       pass message when no issues
       issue rows with severity, rule id, location, and message
       suggestions when present
       summary counts by severity and affected files
```

# Distribution Flow

```text
GitHub Action (Linux only)
  -> install requested release into runner temp storage
  -> run JSON scan to populate Action outputs
  -> run selected output format and preserve Scour exit code
  -> optionally append triage report to step summary

scripts/install.sh (Linux and macOS)
  -> resolve latest or pinned vX.Y.Z release
  -> select OS and architecture archive
  -> download archive and checksum file
  -> verify SHA-256, extract, and atomically install scour

release workflow
  -> build native binaries on five hosted runners
  -> package scour and README.md into versioned archives
  -> generate SHA-256 checksums and publish tagged releases
```
