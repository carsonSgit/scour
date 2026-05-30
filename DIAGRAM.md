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
  -> render text output
       output.color config default applies unless --color was passed
       output.format currently supports text
       pass message when no issues
       issue rows with severity, rule id, location, and message
       suggestions when present
       summary counts by severity and affected files
```
