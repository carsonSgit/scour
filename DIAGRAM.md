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
  -> emit scan-plan summary
       repo root
       Git detected
       config path or none
       scan mode
       base ref when selected
       candidate file count and list
```
