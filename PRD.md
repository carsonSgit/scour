# Product Requirements Document: Scour

## 1. Product Summary

### Product Name

**Scour**

### Tagline

**Scrub your diff before review.**

### One-Sentence Description

Scour is a fast native CLI and GitHub Action that scans changed files, repository metadata, docs, config, and CI workflows to catch repo junk, config drift, debug leftovers, and CI-breaking mistakes before code reaches main.

### Product Category

Developer tooling / CI automation / repository hygiene / pre-merge validation.

### Primary Form Factors

1. **Native CLI binary**
2. **GitHub Action**
3. **CI-compatible output generator**
4. **Issue triage report**
5. Future: configurable rule packs and custom patterns

### Core Positioning

Scour is not a formatter, linter, type checker, dependency auditor, or full secret scanner.

Scour is a **pre-merge sanity scanner**. It catches practical mistakes that conventional tooling often misses:

* focused tests
* skipped tests
* debugger statements
* debug print statements
* merge conflict markers
* undocumented environment variables
* stale README commands
* package-manager drift
* CI workflows calling missing scripts
* Docker setup mistakes
* generated files accidentally committed
* case-sensitive path conflicts
* oversized committed files
* obvious secret-shaped strings

Scour should be fast enough to run locally before every commit and reliable enough to run as a required CI check.

---

## 2. Problem Statement

Modern repositories accumulate small inconsistencies that are not always caught by standard tooling.

Linters catch style. Type checkers catch type errors. Test suites catch runtime regressions. Dependency scanners catch vulnerabilities.

However, many merge-blocking issues live between those systems:

* A developer commits `test.only`.
* A README references `pnpm dev:web`, but that script was renamed.
* Code uses `DATABASE_URL`, but `.env.example` was not updated.
* A Dockerfile exists, but `.dockerignore` is missing.
* A GitHub Actions workflow runs `npm run test`, but no `test` script exists.
* A PR changes `package.json` without changing the lockfile.
* A generated `dist/` directory is committed.
* A merge conflict marker remains in a Markdown file.
* A file works on macOS but breaks Linux CI because of filename casing.

These issues waste reviewer time, cause avoidable CI failures, slow onboarding, and make repositories feel sloppy.

Scour exists to automate those checks and present them in a way that supports quick **issue triage**: what blocks merge, what should be fixed, what can be ignored, and what requires human judgment.

---

## 3. Goals

### 3.1 Product Goals

1. **Catch PR hygiene issues before review**

   Detect common mistakes in changed files and repository metadata.

2. **Reduce avoidable CI failures**

   Identify CI drift, package drift, missing scripts, and config mismatches before full CI runs.

3. **Improve repository consistency**

   Keep docs, env examples, package scripts, Docker files, and workflows aligned.

4. **Support issue triage**

   Group findings by severity, category, file, and likely fix effort so developers can act quickly.

5. **Be fast enough for local use**

   The default command should complete quickly on normal repositories.

6. **Be simple enough to trust**

   Rules should be deterministic, explainable, and easy to disable or reclassify.

7. **Work well in CI**

   GitHub Actions annotations, predictable exit codes, and stable JSON output should be first-class.

8. **Ship as a small native binary**

   No Node, Python, Ruby, or JVM runtime should be required.

---

## 4. Non-Goals

Scour should not become:

1. **A full programming language linter**

   It should not compete with ESLint, Biome, Ruff, Clippy, GolangCI-Lint, or similar tools.

2. **A full type checker**

   It should not parse and type-check full projects.

3. **A full secret scanner**

   It may detect obvious secret-shaped strings later, but should not compete with Gitleaks or TruffleHog.

4. **A vulnerability scanner**

   It should not replace Dependabot, OSV Scanner, Snyk, or npm audit.

5. **A documentation testing framework**

   README command validation should remain pragmatic and bounded.

6. **An AI review tool**

   No LLM dependency in the core product.

7. **A daemon**

   No background process in v1.

8. **A TUI-first application**

   The primary interface is CLI and CI output.

---

## 5. Target Users

### 5.1 Individual Developers

Developers who want to run a fast sanity check before committing or opening a PR.

Needs:

* quick local command
* clean terminal output
* low setup
* low false-positive rate
* changed-file scanning
* obvious remediation guidance

### 5.2 Small Engineering Teams

Teams that want a lightweight CI gate for common PR mistakes.

Needs:

* GitHub Action support
* configurable severity
* branch-aware scanning
* inline PR annotations
* stable exit codes
* issue triage summary

### 5.3 Open Source Maintainers

Maintainers who want fewer repetitive review comments.

Needs:

* easy installation
* contributor-friendly output
* clear rule explanations
* minimal dependencies
* cross-platform binaries

### 5.4 Platform Engineers

Engineers maintaining standards across many repositories.

Needs:

* config file
* JSON output
* predictable rule IDs
* CI integration
* future custom rules
* aggregate reporting

### 5.5 Tech Leads

Leads who want practical merge-readiness checks.

Needs:

* low-friction adoption
* fail-on-error behavior
* warning-only policies where needed
* category-based triage
* rule explanations for team buy-in

---

## 6. User Stories

### 6.1 Local Developer

As a developer, I want to run:

```bash
scour
```

so that I can quickly see whether my branch contains obvious merge-blocking mistakes.

### 6.2 Developer Checking Staged Files

As a developer, I want to run:

```bash
scour --staged
```

so that I can check only what I am about to commit.

### 6.3 Developer Comparing Against Main

As a developer, I want to run:

```bash
scour --since origin/main
```

so that I can scan only files changed in my current branch.

### 6.4 Developer Doing Issue Triage

As a developer, I want to run:

```bash
scour triage
```

so that I can see issues grouped by severity, category, and likely fix priority.

### 6.5 CI Maintainer

As a CI maintainer, I want to use Scour in GitHub Actions and receive inline annotations so that contributors can fix issues directly from the PR UI.

### 6.6 Team Lead

As a team lead, I want to configure which rules are errors, warnings, info, or disabled so that Scour matches our team’s standards.

### 6.7 Open Source Maintainer

As a maintainer, I want simple installation instructions and prebuilt binaries so contributors do not need Nim installed.

### 6.8 Platform Engineer

As a platform engineer, I want JSON output so I can aggregate Scour results across repositories.

---

## 7. Core Product Principles

### 7.1 Fast by Default

Scour should avoid scanning the entire repository when unnecessary.

Preferred scan order:

1. CI PR diff, when available.
2. Changed files against detected base branch.
3. Staged files.
4. Current directory fallback.

### 7.2 Deterministic

The same inputs should produce the same findings.

No probabilistic behavior in v1.

### 7.3 Low Noise

Rules should be conservative. Scour should avoid becoming a nagging tool that developers immediately disable.

### 7.4 Explainable

Every finding must include:

* rule ID
* severity
* file path
* line number when available
* column number when available
* concise message
* recommended action when useful
* category
* triage classification

### 7.5 Triage-Oriented

Scour should not only list issues. It should help users decide what to do next.

Each issue should be classifiable as:

* **blocker**: should stop merge
* **fix-now**: should be resolved before review
* **review**: needs human judgment
* **cleanup**: low-risk cleanup
* **ignored**: explicitly disabled or suppressed

### 7.6 Useful Without Config

Scour should have strong defaults while allowing teams to customize severity, ignored paths, enabled rules, output mode, and triage behavior.

### 7.7 CI-Native

GitHub Actions output should be first-class, not an afterthought.

### 7.8 Native and Lightweight

Scour should ship as a small standalone binary.

---

## 8. Product Surface Area

## 8.1 CLI Commands

### Default Scan

```bash
scour
```

Runs the default scan strategy.

Expected behavior:

* Inside Git repo: scan changed files against detected base branch.
* Outside Git repo: scan current directory.
* In CI: infer PR base when supported.

### Scan Against Ref

```bash
scour --since origin/main
```

Scans files changed relative to a Git ref.

### Scan Staged Files

```bash
scour --staged
```

Scans staged files only.

### Scan Entire Repository

```bash
scour --all
```

Scans the entire repository, respecting ignore rules unless disabled.

### Explicit Path Mode

```bash
scour src tests README.md
```

Scans explicit files or directories.

### Triage View

```bash
scour triage
```

Runs a scan and groups findings by practical priority.

Example groupings:

```txt
Blockers
Fix Now
Needs Review
Cleanup
```

### Explain Rule

```bash
scour explain env-drift
```

Shows rule purpose, examples, severity, triage behavior, and recommended fix.

### List Rules

```bash
scour rules
```

Lists all available rules and active severities.

### Output Format

```bash
scour --format text
scour --format json
scour --format github
```

Supported output formats:

* `text`
* `json`
* `github`
* future: `sarif`

### Failure Threshold

```bash
scour --fail-on error
scour --fail-on warning
scour --fail-on info
```

Controls which severities cause exit code `1`.

### Exit Zero

```bash
scour --exit-zero
```

Always returns exit code `0`, useful for non-blocking CI reporting.

### Config Path

```bash
scour --config scour.toml
```

Uses a specific config file.

### Version

```bash
scour --version
```

Shows version, commit hash if available, and build target.

---

## 9. Scan Modes

### 9.1 Changed Mode

Default mode for Git repositories.

Command:

```bash
scour --since origin/main
```

Implementation:

```bash
git diff --name-only --diff-filter=ACMR origin/main...HEAD
```

Should include:

* added files
* copied files
* modified files
* renamed files

Should exclude:

* deleted files
* ignored paths
* binary files unless relevant rule needs them

### 9.2 Staged Mode

Command:

```bash
scour --staged
```

Implementation:

```bash
git diff --cached --name-only --diff-filter=ACMR
```

### 9.3 All Mode

Command:

```bash
scour --all
```

Scans the repository recursively.

Should respect:

* `.gitignore`
* config ignore paths
* default ignored directories
* max file size

### 9.4 Explicit Path Mode

Command:

```bash
scour src tests README.md
```

Scans explicit files and directories.

### 9.5 CI Mode

When running in GitHub Actions, Scour should infer:

* base ref
* head ref
* repository root
* PR context
* annotation output when requested

Environment variables to inspect:

```txt
GITHUB_ACTIONS
GITHUB_BASE_REF
GITHUB_HEAD_REF
GITHUB_REF
GITHUB_SHA
GITHUB_WORKSPACE
```

---

## 10. Issue Triage

Issue triage is a core Scour workflow.

The scanner should not only emit raw findings. It should organize them into a decision-oriented view.

### 10.1 Triage Fields

Each issue should include:

```txt
rule_id
severity
category
triage_level
file
line
column
message
suggestion
```

Current implementation status after issue #2:

* Implemented in `src/scourpkg/issues.nim` as the shared `Issue` model.
* Implemented fields: `ruleId`, `severity`, `category`, `triage`, `file`, `line`, `column`, `message`, and `suggestion`.
* Implemented severities: `error`, `warning`, and `info`.
* Implemented triage levels: `blocker`, `fixNow`, `review`, `cleanup`, and `ignored`.
* `off` remains a rule/config severity state rather than an emitted issue severity.

### 10.2 Triage Levels

| Triage Level | Meaning                                                        |
| ------------ | -------------------------------------------------------------- |
| `blocker`    | Should prevent merge.                                          |
| `fix-now`    | Should be fixed before review, but may not fail CI by default. |
| `review`     | Requires human judgment.                                       |
| `cleanup`    | Low-risk cleanup or consistency issue.                         |
| `ignored`    | Suppressed by config or inline ignore.                         |

### 10.3 Default Triage Mapping

| Severity  | Default Triage Level |
| --------- | -------------------- |
| `error`   | `blocker`            |
| `warning` | `fix-now`            |
| `info`    | `cleanup`            |
| `off`     | `ignored`            |

Rules may override the default mapping.

Example:

```txt
console-log: warning + review
skipped-test: warning + review
duplicate-lockfiles: warning + fix-now
```

### 10.4 Triage Output Example

```txt
scour triage found 7 issues

Blockers
  ERROR   focused-test       tests/auth.test.ts:12:3
          Focused test committed: test.only(...)

  ERROR   env-drift          src/db/client.ts:8:17
          DATABASE_URL is used but missing from .env.example.

Fix Now
  WARNING duplicate-lockfiles package.json
          Multiple lockfiles found: package-lock.json, pnpm-lock.yaml

Needs Review
  WARNING skipped-test       tests/payment.test.ts:18:1
          Skipped test found.

Cleanup
  INFO    temporary-code     src/api/users.ts:91:5
          Temporary-code marker found: "quick fix".

Summary
  2 blockers
  1 fix-now
  1 needs-review
  1 cleanup
```

### 10.5 Triage Goals

The triage view should answer:

1. What blocks merge?
2. What should be fixed before review?
3. What needs human judgment?
4. What is low-priority cleanup?
5. Which files are creating the most noise?
6. Which categories are most problematic?

---

## 11. Rule System

### 11.1 Rule Model

Each rule has:

```txt
id
name
description
category
default_severity
default_triage_level
enabled_by_default
scan_scope
requires_git
supports_line_location
supports_column_location
```

### 11.2 Severity Levels

Supported severities:

```txt
error
warning
info
off
```

| Severity  | Meaning                                                    |
| --------- | ---------------------------------------------------------- |
| `error`   | Should block merge by default.                             |
| `warning` | Should be fixed or reviewed, but may not block by default. |
| `info`    | Advisory or educational.                                   |
| `off`     | Rule disabled.                                             |

### 11.3 Rule Categories

| Category         | Purpose                                                       |
| ---------------- | ------------------------------------------------------------- |
| `branch-hygiene` | Detects risky code left in PRs.                               |
| `env-drift`      | Detects undocumented environment variables.                   |
| `docs-drift`     | Detects README or docs that reference missing commands/files. |
| `package-drift`  | Detects package manager and lockfile inconsistency.           |
| `ci-drift`       | Detects CI workflows that call missing commands.              |
| `docker-drift`   | Detects common Docker config mistakes.                        |
| `repo-hygiene`   | Detects generated files, case conflicts, large files, etc.    |
| `security-lite`  | Detects obvious secret-shaped strings.                        |
| `architecture`   | Future configurable boundary checks.                          |

Current implementation status after issue #5:

* Implemented branch hygiene scanning in `src/scourpkg/rules/branch_hygiene.nim`.
* The scanner runs over candidate files produced by the existing scan modes: default changed-file mode, `--all`, `--staged`, `--since <ref>`, and explicit paths.
* Implemented first-pass rule IDs: `merge-conflict`, `debugger`, `focused-test`, `skipped-test`, `console-log`, and `ts-ignore`.
* All emitted branch hygiene issues currently use severity `error`, category `hygiene`, and triage `fixNow`.
* JavaScript/TypeScript-only checks are scoped to JS/TS extensions, while `ts-ignore` is scoped to TypeScript extensions.
* Full-line comments are ignored for JS/TS hygiene patterns to reduce obvious false positives.
* Implemented repository hygiene scanning in `src/scourpkg/rules/repo_hygiene.nim`.
* Repository hygiene rules run after branch hygiene and are combined into the same issue output.
* In Git repositories, repository hygiene rules inspect tracked files via `git ls-files`; outside Git, they inspect the scan plan's candidate files.
* Implemented repository rule IDs: `duplicate-lockfiles`, `dockerignore-missing`, and `generated-files`.
* Repository hygiene issues currently emit severity `warning` and triage `fixNow`.
* Implemented cross-reference scanning in `src/scourpkg/rules/cross_reference.nim`.
* Cross-reference rules run after branch and repository hygiene and are combined into the same issue output.
* In Git repositories, cross-reference rules use `git ls-files` as repository inventory for docs, workflows, env examples, package metadata, and task files; outside Git, they use the scan plan's candidate files.
* Implemented cross-reference rule IDs: `env-drift`, `readme-command-drift`, `ci-command-drift`, and Node-focused `package-lock-drift`.
* `env-drift` emits severity `error`, category `env-drift`, and triage `blocker`.
* `readme-command-drift` emits severity `warning`, category `docs-drift`, and triage `fixNow`.
* `ci-command-drift` emits severity `error`, category `ci-drift`, and triage `blocker`.
* `package-lock-drift` currently emits severity `warning`, category `package-drift`, and triage `fixNow` in all contexts until CI/local severity switching lands.

---

## 12. MVP Rules

### 12.1 `merge-conflict`

Category: `branch-hygiene`
Default severity: `error`
Default triage level: `blocker`
Implementation status: implemented.

Detects merge conflict markers.

Patterns:

```txt
\<<<<<<<
\=======
\>>>>>>>
```

Example:

```txt
ERROR merge-conflict README.md:44:1
Merge conflict marker found.
```

Recommended fix:

Resolve the merge conflict and remove the conflict markers before merging.

---

### 12.2 `debugger`

Category: `branch-hygiene`
Default severity: `error`
Default triage level: `blocker`
Implementation status: partially implemented for JavaScript/TypeScript `debugger;`.

Detects debugger statements.

Patterns:

```txt
debugger
binding.pry
byebug
pdb.set_trace
breakpoint()
```

Example:

```txt
ERROR debugger src/auth/login.ts:42:7
Debugger statement found.
```

---

### 12.3 `focused-test`

Category: `branch-hygiene`
Default severity: `error`
Default triage level: `blocker`
Implementation status: implemented for `describe.only`, `it.only`, `test.only`, `context.only`, `fdescribe(`, and `fit(` in JavaScript/TypeScript files.

Detects focused tests that prevent full test suites from running.

Patterns:

```txt
test.only
it.only
describe.only
context.only
specify.only
.only(
fit(
fdescribe(
```

Example:

```txt
ERROR focused-test tests/auth.test.ts:12:3
Focused test committed: test.only(...)
```

---

### 12.4 `skipped-test`

Category: `branch-hygiene`
Default severity: `warning`
Default triage level: `review`
Implementation status: implemented for `describe.skip`, `it.skip`, `test.skip`, `context.skip`, `xdescribe(`, and `xit(` in JavaScript/TypeScript files. Current emitted severity is still `error` until configurable severities land.

Detects skipped tests.

Patterns:

```txt
test.skip
it.skip
describe.skip
context.skip
specify.skip
.skip(
xit(
xdescribe(
```

Example:

```txt
WARNING skipped-test tests/payment.test.ts:18:1
Skipped test found.
```

---

### 12.5 `console-log`

Category: `branch-hygiene`
Default severity: `warning`
Default triage level: `review`
Implementation status: implemented for `console.log(` in JavaScript/TypeScript files. It can be disabled with `[rules] console-log = false`; current emitted severity is still `error` until configurable severities land.

Detects common debug print statements.

Patterns:

```txt
console.log
console.debug
console.dir
println!
dbg!
print(
printf(
echo
```

This rule must be configurable because some languages and CLIs use printing legitimately.

Example:

```txt
WARNING console-log src/api/users.ts:88:3
Debug print statement found.
```

---

### 12.6 `ts-ignore`

Category: `branch-hygiene`
Default severity: `warning`
Default triage level: `review`
Implementation status: implemented for `@ts-ignore` in TypeScript files. Current emitted severity is still `error` until configurable severities land.

Detects TypeScript suppression comments.

Patterns:

```txt
@ts-ignore
@ts-nocheck
```

Example:

```txt
WARNING ts-ignore src/config.ts:12:5
TypeScript suppression found.
```

---

### 12.7 `duplicate-lockfiles`

Category: `package-drift`
Default severity: `warning`
Default triage level: `fix-now`
Implementation status: implemented.

Detects multiple package manager lockfiles in the same package root.

Files:

```txt
package-lock.json
npm-shrinkwrap.json
pnpm-lock.yaml
yarn.lock
bun.lock
bun.lockb
```

Example:

```txt
WARNING duplicate-lockfiles package.json
Multiple lockfiles found: package-lock.json, pnpm-lock.yaml
```

Recommended fix:

Keep only the lockfile for the package manager used by the project.

---

### 12.8 `package-lock-drift`

Category: `package-drift`
Default severity: `error` in CI, `warning` locally
Default triage level: `blocker` in CI, `fix-now` locally
Implementation status: implemented for Node package roots where `package.json` is a scan candidate and exactly one same-directory Node lockfile already exists in repository inventory. Current emitted severity is `warning` with triage `fixNow` in all contexts until CI/local severity switching lands.

Detects when package manifest files changed but expected lockfiles did not.

Manifest files:

```txt
package.json
pyproject.toml
Cargo.toml
go.mod
Gemfile
composer.json
```

Lockfiles:

```txt
package-lock.json
pnpm-lock.yaml
yarn.lock
bun.lock
bun.lockb
uv.lock
poetry.lock
Cargo.lock
go.sum
Gemfile.lock
composer.lock
```

MVP starts with Node package files only. It does not inspect dependency diffs, infer package manager choice when no lockfile exists, or report package roots with multiple lockfiles because `duplicate-lockfiles` already handles that case.

Example:

```txt
ERROR package-lock-drift package.json
package.json changed but pnpm-lock.yaml was not changed.
```

---

### 12.9 `dockerignore-missing`

Category: `docker-drift`
Default severity: `warning`
Default triage level: `fix-now`
Implementation status: implemented.

Detects Dockerfile without `.dockerignore`.

Files:

```txt
Dockerfile
Dockerfile.*
```

Expected:

```txt
.dockerignore
```

Example:

```txt
WARNING dockerignore-missing Dockerfile
Dockerfile exists but .dockerignore is missing.
```

---

### 12.10 `generated-files`

Category: `repo-hygiene`
Default severity: `warning`
Default triage level: `fix-now`
Implementation status: implemented.

Detects common generated output committed to the repository.

Paths:

```txt
dist/
build/
coverage/
.next/
.nuxt/
out/
target/
.cache/
.parcel-cache/
.turbo/
```

Should primarily inspect tracked files via Git:

```bash
git ls-files
```

Example:

```txt
WARNING generated-files dist/index.js
Generated output appears to be tracked.
```

---

### 12.11 `env-drift`

Category: `env-drift`
Default severity: `error`
Default triage level: `blocker`
Implementation status: implemented for literal usage patterns in scan candidate files.

Detects environment variables used in code but missing from env example files.

Usage patterns:

```txt
process.env.NAME
import.meta.env.NAME
Deno.env.get("NAME")
os.Getenv("NAME")
std::env::var("NAME")
System.getenv("NAME")
ENV["NAME"]
getenv("NAME")
```

Reference files:

```txt
.env.example
.env.sample
.env.template
.env.defaults
```

Default ignored env names:

```txt
NODE_ENV
CI
PATH
HOME
USER
SHELL
PWD
OLDPWD
```

The implementation intentionally ignores dynamic env names and only compares against variables listed in `.env.example`, `.env.sample`, `.env.template`, and `.env.defaults` files present in repository inventory.

Example:

```txt
ERROR env-drift src/db/client.ts:8:17
DATABASE_URL is used but missing from .env.example.
```

---

### 12.12 `readme-command-drift`

Category: `docs-drift`
Default severity: `warning`
Default triage level: `fix-now`
Implementation status: implemented for conservative command extraction in `README.md` and `docs/**/*.md`.

Detects README commands that reference missing scripts or targets.

Sources:

```txt
README.md
docs/**/*.md
```

Command patterns:

```txt
npm run <script>
pnpm <script>
pnpm run <script>
yarn <script>
yarn run <script>
bun run <script>
make <target>
just <recipe>
task <task>
```

Validation targets:

```txt
package.json scripts
Makefile targets
justfile recipes
Taskfile.yml tasks
```

The implementation validates against matching scripts or targets anywhere in repository inventory. It focuses on shell-like fenced blocks and simple command lines, and does not attempt to emulate Markdown rendering or shell expansion.

Example:

```txt
WARNING readme-command-drift README.md:31:1
README references `pnpm dev:web`, but no matching package script exists.
```

---

### 12.13 `ci-command-drift`

Category: `ci-drift`
Default severity: `error`
Default triage level: `blocker`
Implementation status: implemented for simple `run:` commands in GitHub workflow files.

Detects CI workflow commands that call missing scripts or targets.

Sources:

```txt
.github/workflows/*.yml
.github/workflows/*.yaml
```

Command patterns:

```txt
run: npm run <script>
run: pnpm <script>
run: pnpm run <script>
run: yarn <script>
run: bun run <script>
run: make <target>
run: just <recipe>
```

The implementation handles single-line `run:` commands and block-style `run: |` / `run: >` commands. It does not parse the full YAML model or evaluate matrix/template expressions.

Example:

```txt
ERROR ci-command-drift .github/workflows/ci.yml:22:1
Workflow calls `pnpm test`, but package.json has no `test` script.
```

---

## 13. Future Rules

### 13.1 `secret-shape`

Detects obvious secret-like strings.

Patterns:

```txt
-----BEGIN PRIVATE KEY-----
-----BEGIN RSA PRIVATE KEY-----
ghp_
github_pat_
sk-
AKIA
xoxb-
```

Default severity: `error`
Default triage level: `blocker`

This should not claim exhaustive secret detection.

---

### 13.2 `large-file`

Detects large files committed in changed files.

Default threshold:

```txt
5MB
```

Configurable:

```toml
[repo]
max_file_size = "5MB"
```

---

### 13.3 `case-conflict`

Detects files that differ only by case.

Example:

```txt
src/Button.tsx
src/button.tsx
```

Important for cross-platform repositories.

---

### 13.4 `broken-local-link`

Detects Markdown links to missing local files.

Example:

```md
[Setup](docs/setup.md)
```

If `docs/setup.md` does not exist, report warning.

---

### 13.5 `workspace-drift`

Detects monorepo workspace inconsistencies.

Examples:

* package folder missing `package.json`
* workspace glob references no packages
* package exists but is not included by workspace config
* duplicate package names

---

### 13.6 `architecture-seam`

Detects forbidden imports based on configured boundaries.

Example config:

```toml
[[architecture.boundaries]]
name = "frontend-cannot-import-server"
from = "apps/web/**"
forbid = ["packages/server/**", "packages/db/**"]
severity = "error"
```

---

## 14. Output Requirements

### 14.1 Text Output

Default human-readable output.

Example:

```txt
Scour found 7 issue(s).

error merge-conflict README.md:44:1 - Merge conflict marker found.

error focused-test tests/auth.test.ts:12:3 - Focused test committed: test.only(...)

error env-drift src/db/client.ts:8:17 - DATABASE_URL is used but missing from .env.example.
  Suggestion: Add DATABASE_URL to .env.example or configure it as ignored.

warning readme-command-drift README.md:31:1 - README references `pnpm dev:web`, but no matching package script exists.

warning package-lock-drift package.json - package.json changed but pnpm-lock.yaml was not changed.

info temporary-code src/api/users.ts:91:5 - Temporary-code marker found: "quick fix".

Summary: 6 issue(s), 3 error(s), 2 warning(s), 1 info(s), 6 file(s)
```

Text output must be:

* readable
* stable
* non-verbose by default
* colored when terminal supports color
* non-colored when output is piped unless forced

Current implementation status after issue #2:

* Clean scans print `Scour passed. No failing issues found.`
* Issue output prints severity, rule ID, location, and message in one stable line.
* Suggestions print on an indented follow-up line when present.
* Summary counts include total issues, counts by severity, and affected file count.
* `--color auto`, `--color always`, and `--color never` are supported.
* `auto` uses terminal detection, `always` forces ANSI color, and `never` disables ANSI color.

Flags:

```bash
--color auto
--color always
--color never
```

---

### 14.2 Triage Output

Command:

```bash
scour triage
```

Example:

```txt
scour triage found 7 issues

Blockers
  ERROR   focused-test       tests/auth.test.ts:12:3
          Focused test committed: test.only(...)

  ERROR   env-drift          src/db/client.ts:8:17
          DATABASE_URL is used but missing from .env.example.

Fix Now
  WARNING package-lock-drift package.json
          package.json changed but pnpm-lock.yaml was not changed.

Needs Review
  WARNING skipped-test       tests/payment.test.ts:18:1
          Skipped test found.

Cleanup
  INFO    temporary-code     src/api/users.ts:91:5
          Temporary-code marker found: "quick fix".

Summary
  2 blockers
  1 fix-now
  1 needs-review
  1 cleanup
```

---

### 14.3 JSON Output

Command:

```bash
scour --format json
```

Shape:

```json
{
  "summary": {
    "errors": 3,
    "warnings": 3,
    "info": 1,
    "total": 7,
    "files": 6,
    "triage": {
      "blockers": 3,
      "fix_now": 2,
      "review": 1,
      "cleanup": 1
    }
  },
  "issues": [
    {
      "rule": "env-drift",
      "severity": "error",
      "triage_level": "blocker",
      "category": "env-drift",
      "file": "src/db/client.ts",
      "line": 8,
      "column": 17,
      "message": "DATABASE_URL is used but missing from .env.example.",
      "suggestion": "Add DATABASE_URL to .env.example or configure it as ignored."
    }
  ]
}
```

JSON output should be stable for downstream parsing.

---

### 14.4 GitHub Actions Output

Command:

```bash
scour --format github
```

Shape:

```txt
::error file=src/db/client.ts,line=8,col=17,title=env-drift::DATABASE_URL is used but missing from .env.example.
::warning file=README.md,line=31,col=1,title=readme-command-drift::README references pnpm dev:web, but no matching package script exists.
```

Rules:

* `error` maps to `::error`
* `warning` maps to `::warning`
* `info` maps to `::notice`

Must escape GitHub annotation characters correctly.

Characters requiring escaping:

```txt
%
\r
\n
:
,
```

---

### 14.5 Future SARIF Output

Command:

```bash
scour --format sarif
```

Purpose:

* GitHub code scanning integration
* richer security/tooling integration

Not required for MVP.

---

## 15. Exit Codes

| Code | Meaning                                                                  |
| ---: | ------------------------------------------------------------------------ |
|  `0` | No issues at or above failure threshold.                                 |
|  `1` | Issues found at or above failure threshold.                              |
|  `2` | Fatal error: invalid args, unreadable repo, invalid config, Git failure. |

Default failure threshold:

```txt
error
```

Examples:

```bash
scour --fail-on error
scour --fail-on warning
scour --exit-zero
```

Behavior:

* `--exit-zero` always exits `0` unless the tool itself crashes unexpectedly.
* Invalid arguments should still exit `2`.

---

## 16. Configuration

### 16.1 Config File Name

Default lookup order:

```txt
scour.toml
.scour.toml
.config/scour.toml
```

Explicit path:

```bash
scour --config path/to/scour.toml
```

### 16.2 Example Config

```toml
base = "origin/main"
fail_on = "error"

[scan]
mode = "changed"
respect_gitignore = true
max_file_size = "1MB"
follow_symlinks = false

[output]
format = "text"
color = "auto"

[rules]
merge_conflict = "error"
debugger = "error"
focused_test = "error"
skipped_test = "warning"
console_log = "warning"
ts_ignore = "warning"
duplicate_lockfiles = "warning"
package_lock_drift = "error"
dockerignore_missing = "warning"
generated_files = "warning"
env_drift = "error"
readme_command_drift = "warning"
ci_command_drift = "error"

[triage]
merge_conflict = "blocker"
debugger = "blocker"
focused_test = "blocker"
skipped_test = "review"
console_log = "review"
ts_ignore = "review"
duplicate_lockfiles = "fix-now"
package_lock_drift = "fix-now"
dockerignore_missing = "fix-now"
generated_files = "fix-now"
env_drift = "blocker"
readme_command_drift = "fix-now"
ci_command_drift = "blocker"

[ignore]
paths = [
  "node_modules/**",
  "vendor/**",
  "dist/**",
  "build/**",
  "coverage/**",
  ".git/**"
]

[env]
example_files = [
  ".env.example",
  ".env.sample",
  ".env.template"
]

ignored_vars = [
  "NODE_ENV",
  "CI",
  "PATH",
  "HOME"
]

[package]
preferred_manager = "pnpm"

[custom_patterns]
leftover_print = { severity = "warning", triage = "review", pattern = "print\\(" }
panic_call = { severity = "warning", triage = "review", pattern = "panic\\(" }
```

### 16.3 Config Validation

Invalid config should produce clear errors.

Example:

```txt
Fatal: invalid config at scour.toml:14
Unknown severity `warn`. Expected one of: error, warning, info, off.
```

Exit code: `2`

Current implementation status after issue #6:

* Config discovery is implemented in `src/scourpkg/repo.nim`.
* Automatic lookup checks `scour.toml`, `.scour.toml`, then `.config/scour.toml` at the repository root.
* `--config <path>` is implemented and resolves relative paths from the repository root.
* A minimal TOML-like parser is implemented in `src/scourpkg/config.nim`.
* Supported config sections today are `[rules]`, `[triage]`, `[ignore]`, `[scan]`, `[env]`, and `[output]`.
* Rule keys support the PRD underscore style and legacy hyphen style.
* Rule severities support `error`, `warning`, `info`, and `off`; legacy boolean `false` maps to `off`.
* Triage overrides support `blocker`, `fix-now`, `review`, `cleanup`, and `ignored`.
* Ignore paths support exact paths, directory prefixes, and `/**` suffix patterns.
* `scan.max_file_size`, env example files, ignored env vars, and output color defaults are implemented.
* `output.format` accepts `text`, `json`, and `github`.
* Unknown sections, unknown keys, invalid values, invalid syntax, unsupported output formats, and missing explicit config files produce fatal user errors with exit code `2`.

---

## 17. GitHub Action

### 17.1 Basic Usage

```yaml
name: Scour

on:
  pull_request:

jobs:
  scour:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: carson/scour-action@v1
        with:
          since: origin/main
          format: github
          fail-on: error
```

### 17.2 Action Inputs

| Input       | Required | Default  | Description                                      |
| ----------- | -------: | -------- | ------------------------------------------------ |
| `since`     |       No | inferred | Base ref to compare against.                     |
| `staged`    |       No | `false`  | Scan staged files. Mostly local/self-hosted use. |
| `all`       |       No | `false`  | Scan all files.                                  |
| `format`    |       No | `github` | Output format.                                   |
| `fail-on`   |       No | `error`  | Minimum severity that fails the check.           |
| `config`    |       No | auto     | Path to config file.                             |
| `version`   |       No | latest   | Scour version to install.                        |
| `exit-zero` |       No | `false`  | Always exit 0 for non-blocking mode.             |
| `triage`    |       No | `false`  | Emit triage summary.                             |

### 17.3 Action Outputs

| Output     | Description                           |
| ---------- | ------------------------------------- |
| `total`    | Total issue count.                    |
| `errors`   | Error count.                          |
| `warnings` | Warning count.                        |
| `info`     | Info count.                           |
| `blockers` | Blocker count.                        |
| `fix-now`  | Fix-now count.                        |
| `review`   | Needs-review count.                   |
| `cleanup`  | Cleanup count.                        |
| `json`     | Optional JSON payload path or string. |

---

## 18. Installation

### 18.1 One-Line Install

```bash
curl -fsSL https://raw.githubusercontent.com/carson/scour/main/install.sh | sh
```

Version pinning:

```bash
SCOUR_VERSION=0.1.0 curl -fsSL https://raw.githubusercontent.com/carson/scour/main/install.sh | sh
```

### 18.2 Prebuilt Binaries

Release assets:

| Platform            | Asset                                  |
| ------------------- | -------------------------------------- |
| Linux x86_64        | `scour-*-x86_64-unknown-linux.tar.gz`  |
| Linux ARM64         | `scour-*-aarch64-unknown-linux.tar.gz` |
| macOS Intel         | `scour-*-x86_64-apple-darwin.tar.gz`   |
| macOS Apple Silicon | `scour-*-aarch64-apple-darwin.tar.gz`  |
| Windows x86_64      | `scour-*-x86_64-pc-windows.zip`        |

### 18.3 From Source

The project has been initialized with Nimble.

```bash
git clone https://github.com/carson/scour
cd scour
nimble build
```

Expected local development commands:

```bash
nimble build
nimble run
nimble test
```

---

## 19. Technical Requirements

### 19.1 Implementation Language

Scour will be implemented in **Nim**.

Rationale:

* native binary output
* fast startup
* strong fit for filesystem scanning
* good CLI ergonomics
* productive standard library
* Nimble package/project workflow
* more distinctive than another Go or TypeScript CLI
* appropriate for a small, fast developer tool

### 19.2 Nimble Project Assumption

The project has already been initialized with:

```bash
nimble init
```

The repository should use the generated Nimble package as the base and evolve toward:

```txt
scour/
  scour.nimble
  README.md
  LICENSE
  config/
    scour.example.toml
  src/
    scour.nim
    scourpkg/
      cli.nim
      config.nim
      git.nim
      scanner.nim
      issue.nim
      severity.nim
      triage.nim
      paths.nim
      files.nim
      rules/
        branch_hygiene.nim
        package_drift.nim
        docker_drift.nim
        repo_hygiene.nim
        env_drift.nim
        docs_drift.nim
        ci_drift.nim
      output/
        text_output.nim
        json_output.nim
        github_output.nim
  tests/
    test_branch_hygiene.nim
    test_output.nim
    test_config.nim
    fixtures/
      clean-node-repo/
      dirty-node-repo/
```

### 19.3 Performance Requirements

MVP targets:

| Scenario                           |                              Target |
| ---------------------------------- | ----------------------------------: |
| Scan 100 changed files             |     under 250 ms on typical machine |
| Scan 1,000 changed files           | under 1 second when files are small |
| Memory usage for changed-file scan |                         under 50 MB |
| Memory usage for full repo scan    |         under 150 MB on medium repo |
| Startup time                       |  near-instant native binary startup |

These are targets, not hard guarantees.

### 19.4 File Handling

Scour should:

* stream file contents where possible
* avoid loading large files into memory
* skip binary files for text-based rules
* respect max file size
* normalize paths internally
* handle Windows path separators
* avoid following symlinks by default
* guard against infinite recursion

### 19.5 Git Integration

Scour may shell out to Git for:

```bash
git rev-parse --show-toplevel
git diff --name-only
git diff --cached --name-only
git ls-files
git check-ignore
```

MVP does not require native Git implementation.

### 19.6 Ignore Handling

Default ignored paths:

```txt
.git/**
node_modules/**
vendor/**
dist/**
build/**
coverage/**
.next/**
.nuxt/**
.cache/**
.turbo/**
```

Respect `.gitignore` by default when scanning all files.

Changed-file mode should trust Git output but still apply configured ignore paths.

### 19.7 Binary Detection

For text rules, skip files that appear binary.

Simple MVP heuristic:

* read first N bytes
* if a null byte appears, treat as binary
* optionally skip files with a high non-printable ratio

### 19.8 Line and Column Detection

For line-based rules:

* line numbers are 1-indexed
* columns are 1-indexed
* column can be byte offset initially
* future: Unicode-aware column handling

---

## 20. Internal Architecture

### 20.1 Proposed Repository Structure

```txt
scour/
  README.md
  LICENSE
  scour.nimble
  scour.toml.example

  src/
    scour.nim

    scourpkg/
      cli.nim
      commands.nim
      help.nim

      core/
        issue.nim
        severity.nim
        triage.nim
        config.nim
        scanner.nim
        paths.nim
        git.nim
        file.nim
        result.nim

      rules/
        branch_hygiene.nim
        env_drift.nim
        package_drift.nim
        docs_drift.nim
        ci_drift.nim
        docker_drift.nim
        repo_hygiene.nim

      output/
        text.nim
        json.nim
        github.nim

  tests/
    test_rules.nim
    test_output.nim
    test_config.nim
    fixtures/

  scripts/
    install.sh

  .github/
    workflows/
      ci.yml
      release.yml
```

### 20.2 Core Types

#### Severity

```txt
Severity:
  Error
  Warning
  Info
  Off
```

#### Triage Level

```txt
TriageLevel:
  Blocker
  FixNow
  Review
  Cleanup
  Ignored
```

#### Issue

```txt
Issue:
  rule_id: string
  severity: Severity
  triage_level: TriageLevel
  category: string
  file: string
  line: int
  column: int
  message: string
  suggestion: string
```

#### Rule

```txt
Rule:
  id: string
  category: string
  default_severity: Severity
  default_triage_level: TriageLevel
  run(context) -> seq[Issue]
```

#### Scan Context

```txt
ScanContext:
  root_path
  files
  changed_files
  config
  git_info
  package_info
  env_example_info
```

### 20.3 Rule Execution Model

MVP should use simple rule execution:

1. Resolve repository root.
2. Load config.
3. Determine scan mode.
4. Collect candidate files.
5. Load lightweight repository metadata:

   * package scripts
   * lockfiles
   * env examples
   * workflow files
6. Run enabled rules.
7. Aggregate issues.
8. Apply severity and triage mapping.
9. Print output.
10. Exit according to threshold.

### 20.4 Rule Types

#### File-Line Rules

Rules that scan text lines in candidate files.

Examples:

* merge conflict
* debugger
* focused test
* skipped test
* console log
* ts-ignore

#### Repository Metadata Rules

Rules that inspect file existence and repository-level state.

Examples:

* duplicate lockfiles
* dockerignore missing
* generated files

#### Cross-Reference Rules

Rules that compare one source of truth with another.

Examples:

* env drift
* README command drift
* CI command drift

---

## 21. UX Requirements

### 21.1 Default Output Should Be Useful

Running:

```bash
scour
```

should produce one of:

Clean output:

```txt
Scour passed. No failing issues found.
```

Issue output:

```txt
scour found 4 issues

ERROR   focused-test  tests/auth.test.ts:12:3
        Focused test committed: test.only(...)

WARNING console-log   src/api/users.ts:88:3
        Debug print statement found.

Found 1 error, 1 warning across 2 files.
```

### 21.2 No Stack Traces for Normal Errors

Bad user input should produce clear messages, not raw stack traces.

Example:

```txt
Fatal: unknown output format `xml`.
Expected one of: text, json, github.
```

### 21.3 Rule Explainers

Command:

```bash
scour explain focused-test
```

Output:

```txt
Rule: focused-test
Severity: error
Triage: blocker
Category: branch-hygiene

Detects focused test declarations such as test.only, it.only, describe.only,
fit, and fdescribe.

Why it matters:
Focused tests can cause CI to run only a subset of tests, allowing regressions to merge.

Example:
tests/auth.test.ts:12:3
test.only("logs in user", () => {})

Fix:
Remove `.only` before merging.
```

### 21.4 Triage Summary

The triage summary should make it obvious what to fix first.

Example:

```txt
Triage
  3 blockers
  2 fix-now
  1 needs-review
  1 cleanup
```

---

## 22. Acceptance Criteria

### 22.1 CLI

- [x] Running `scour --help` displays usable help text.
- [x] Running `scour --version` displays version information.
- [x] Running `scour` inside a Git repo performs a scan.
- [x] Running `scour --all` scans all eligible files.
- [x] Running `scour --staged` scans staged files.
- [x] Running `scour --since <ref>` scans changed files.
- [x] Running `scour rules` lists implemented rules with effective defaults.
- [x] Running `scour explain <rule>` describes an implemented rule.
- [x] Running `scour triage` prints grouped issue triage.
- [x] Invalid flags exit with code `2`.

### 22.2 Output

- [x] Findings are normalized into a single issue model with severity and triage fields.
- [x] Text output includes severity, rule ID, file, line, column, and message.
- [x] Summary counts include total issues, severity counts, and affected file count.
- [x] Clean scans produce a concise pass message instead of noisy output.
- [x] Color output can be auto-detected, forced, or disabled.
- [x] Triage output groups issues by blocker, fix-now, review, and cleanup.
- [x] JSON output is valid JSON.
- [x] JSON output includes severity and triage fields.
- [x] GitHub output uses valid workflow command syntax.

### 22.3 Rules

MVP must implement:

- [x] `merge-conflict`
- [x] `debugger` for JavaScript/TypeScript `debugger;`
- [x] `focused-test` for common JS/TS focus forms
- [x] `skipped-test` for common JS/TS skip forms
- [x] `console-log` for JS/TS `console.log(`
- [x] `ts-ignore` for TypeScript `@ts-ignore`
- [x] `duplicate-lockfiles`
- [x] `package-lock-drift` for Node package roots with one existing lockfile
- [x] `dockerignore-missing`
- [x] `generated-files`
- [x] `env-drift`
- [x] `readme-command-drift`
- [x] `ci-command-drift`

### 22.4 Config

- [x] Scour loads `scour.toml` automatically.
- [x] Scour loads `.scour.toml` automatically.
- [x] Scour loads `.config/scour.toml` automatically.
- [x] `--config <path>` loads an explicit config file.
- [x] Rule severity can be changed.
- [x] Rule triage level can be changed.
- [x] `console-log` can be disabled with `[rules] console-log = false`.
- [x] General rules can be disabled with `off`.
- [x] Ignore paths are respected.
- [x] Invalid config exits with code `2`.

### 22.5 CI

* GitHub Actions annotation output works.
* Exit code `1` occurs when issues at or above the failure threshold are found.
* `--exit-zero` prevents issue-based failure.
* Action can run on `pull_request`.
* Action can emit a triage summary.

### 22.6 Performance

* Changed-file scan must avoid scanning the entire repo.
* Files larger than configured max size are skipped for text rules.
* Binary files are skipped for text rules.
* Memory usage should remain bounded by streaming file reads.

---

## 23. MVP Release Plan

### Version 0.1.0 — Local Scanner

Scope:

- [x] Nimble project setup
- [x] CLI parser
- [x] text output
- [x] changed/staged/all scan modes
- [x] explicit path scan mode
- [x] repository/config discovery
- [x] first-pass branch hygiene rules
- [x] duplicate lockfile check
- [x] Dockerfile without `.dockerignore` check
- [x] generated tracked files check
- [x] rule severity and triage defaults per rule
* basic issue triage summary

Rules:

```txt
merge-conflict        implemented
debugger              partially implemented for JS/TS debugger;
focused-test          implemented for common JS/TS forms
skipped-test          implemented for common JS/TS forms
console-log           implemented for JS/TS console.log(
ts-ignore             implemented for TypeScript @ts-ignore
duplicate-lockfiles   implemented for package roots with multiple Node/Bun lockfiles
dockerignore-missing  implemented for Dockerfile and Dockerfile.* without same-directory .dockerignore
generated-files       implemented for tracked generated output directories
```

Success criteria:

* Can scan a repo locally.
* Can detect obvious PR hygiene issues.
* Can print clean text output.
* Can group issues by triage level.
* Can return useful exit codes.

---

### Version 0.2.0 — CI Ready

Scope:

* JSON output
* GitHub Actions output
* `--fail-on`
* `--exit-zero`
* install script
* release binaries
* GitHub Action wrapper

Rules added:

```txt
generated-files
package-lock-drift
```

Success criteria:

* Can be used in GitHub Actions.
* Can annotate PRs.
* Can be installed without Nim.
* Can emit machine-readable triage data.

---

### Version 0.3.0 — Drift Detection

Scope:

* config file
* env drift
* README command drift
* CI command drift
* rule explanations

Rules added:

```txt
env-drift
readme-command-drift
ci-command-drift
```

Success criteria:

* Tool becomes meaningfully differentiated from simple grep scanners.
* Can detect docs/config/CI drift.
* Can explain findings clearly.

---

### Version 0.4.0 — Repository Hygiene Expansion

Scope:

* large file detection
* case conflict detection
* broken local Markdown links
* secret-shaped strings
* improved package manager detection

Success criteria:

* Scour becomes a broad pre-merge sanity gate.

---

### Version 1.0.0 — Stable Release

Requirements:

* stable config format
* stable JSON schema
* stable rule IDs
* stable triage fields
* stable exit behavior
* documented GitHub Action
* documented install process
* cross-platform release binaries
* internal test suite
* clear README
* changelog

---

## 24. Testing Strategy

### 24.1 Unit Tests

Test:

* pattern matching
* severity parsing
* triage parsing
* config parsing
* output formatting
* GitHub annotation escaping
* package script extraction
* env var extraction
* README command extraction

### 24.2 Fixture Tests

Use fixture repositories:

```txt
fixtures/
  clean-node-repo/
  dirty-node-repo/
  docker-repo-missing-ignore/
  env-drift-repo/
  readme-drift-repo/
  ci-drift-repo/
  generated-files-repo/
```

Each fixture should have expected output snapshots.

### 24.3 Integration Tests

Test commands:

```bash
scour --all
scour --staged
scour --since main
scour triage
scour --format json
scour --format github
scour --fail-on warning
scour --exit-zero
```

### 24.4 Regression Tests

Every bug fix should add a fixture or unit test.

Current implementation status after issue #9:

* Committed clean and dirty fixture repositories are copied into temporary
  directories and initialized as real Git repositories.
* Integration tests build and execute the real Scour binary.
* Exact snapshots cover clean and dirty text, JSON, GitHub annotations, and
  grouped triage output.
* Regression coverage exercises `--all`, `--staged`, `--since`, explicit
  paths, config overrides, `--fail-on warning`, `--exit-zero`, and `--`.

---

## 25. Risks and Mitigations

### Risk: False Positives

Examples:

* README intentionally documents optional scripts.
* `console.log` is legitimate in CLI apps.
* skipped tests are intentional.

Mitigation:

* configurable severity
* configurable triage level
* per-rule disable
* ignore paths
* future inline ignore comments
* conservative defaults

### Risk: Tool Becomes Too Broad

Scour could become a messy collection of unrelated checks.

Mitigation:

* keep product frame strict: pre-merge sanity scanner
* reject checks that do not affect merge readiness
* group rules by category
* maintain rule explanations

### Risk: Nim Ecosystem Friction

Nim may have less standardization around TOML, YAML, globbing, release packaging, and cross-platform CLI conventions than Go or Node.

Mitigation:

* start simple
* shell out to Git
* use pragmatic parsing for CI YAML in MVP
* avoid full YAML parser initially
* keep dependencies minimal
* treat Nimble as the canonical development workflow

### Risk: CI Diff Detection Complexity

GitHub Actions shallow clones can break diff logic.

Mitigation:

* document `fetch-depth: 0`
* provide clear error if base ref is missing
* fallback to scanning all files if configured
* support explicit `--since`

### Risk: Performance Degrades With Full Repo Scans

Large repos can be expensive.

Mitigation:

* changed-file default
* file size limit
* binary skip
* ignore paths
* streaming reads

---

## 26. Open Questions

1. Should the default command scan changed files against `origin/main`, or staged files first?
2. Should warnings fail CI by default, or only errors?
3. Should `console-log` be enabled by default for all languages?
4. Should README drift scan only `README.md`, or all Markdown docs?
5. Should inline ignore comments exist in v1?
6. Should `secret-shape` ship before 1.0?
7. Should SARIF output be prioritized for GitHub code scanning?
8. Should the tool support non-Git directories in v1?
9. Should config use TOML only, or also support JSON/YAML?
10. Should package drift support only Node initially, or include Python/Rust/Go from the start?
11. Should `scour triage` be a separate command, or should triage always appear in normal output?
12. Should triage level be configurable independently from severity?
13. Should custom patterns be supported in v1, or wait until after core rules are stable?

---

## 27. Recommended Defaults

### 27.1 Default Enabled Rules

```txt
merge-conflict: error
debugger: error
focused-test: error
skipped-test: warning
console-log: warning
ts-ignore: warning
duplicate-lockfiles: warning
package-lock-drift: error
dockerignore-missing: warning
generated-files: warning
env-drift: error
readme-command-drift: warning
ci-command-drift: error
```

### 27.2 Default Triage Mapping

```txt
merge-conflict: blocker
debugger: blocker
focused-test: blocker
skipped-test: review
console-log: review
ts-ignore: review
duplicate-lockfiles: fix-now
package-lock-drift: fix-now
dockerignore-missing: fix-now
generated-files: fix-now
env-drift: blocker
readme-command-drift: fix-now
ci-command-drift: blocker
```

### 27.3 Default Failure Threshold

```txt
error
```

### 27.4 Default Scan Mode

```txt
changed
```

Fallback order:

```txt
CI PR diff
origin/main
main
master
staged
all
```

### 27.5 Default Max File Size

```txt
1MB for text scanning
```

### 27.6 Default Output

```txt
text locally
github in GitHub Action wrapper
```

---

## 28. README Positioning Draft

````md
# Scour

Fast pre-merge checks for repo grime, config drift, and PR mistakes.

Scour catches the junk linters miss before review does:

- focused tests
- debugger statements
- merge conflict markers
- skipped tests
- debug logs
- undocumented environment variables
- stale README commands
- package-manager drift
- CI commands that no longer exist
- Dockerfile without `.dockerignore`
- generated files accidentally committed

It runs locally as a small native CLI and in CI as a GitHub Action.

## Example

```bash
scour --since origin/main
````

```txt
ERROR   focused-test         tests/auth.test.ts:12:3
        Focused test committed: test.only(...)

ERROR   env-drift            src/db/client.ts:8:17
        DATABASE_URL is used but missing from .env.example.

WARNING readme-command-drift README.md:31:1
        README references `pnpm dev:web`, but no matching package script exists.

Found 2 errors, 1 warning across 3 files.
```

## Triage

```bash
scour triage
```

```txt
Blockers
  ERROR focused-test tests/auth.test.ts:12:3
        Focused test committed: test.only(...)

Fix Now
  WARNING readme-command-drift README.md:31:1
          README references `pnpm dev:web`, but no matching package script exists.

Summary
  1 blocker
  1 fix-now
```

```

---

## 29. Success Metrics

### 29.1 Product Metrics

- Number of repos using Scour in CI.
- Number of GitHub Action installs.
- Number of release downloads.
- Number of stars/forks.
- Number of issues detected per run.
- Percentage of issue-free runs.
- Number of false-positive reports.
- Number of triaged issues by category.

### 29.2 User Value Metrics

- Reduced repeated reviewer comments.
- Fewer CI failures caused by missing scripts/config drift.
- Faster PR cleanup.
- Easier onboarding due to more accurate README/env docs.
- Faster identification of merge blockers.

### 29.3 Technical Metrics

- Average runtime in changed-file mode.
- Memory usage in changed-file mode.
- Binary size.
- Crash rate.
- Config parse failure rate.
- Rule false-positive rate.

---

## 30. Final Recommendation

Build Scour in four phases:

1. **Branch hygiene scanner**

   Fast, simple, immediately useful.

2. **CI output and packaging**

   Makes it usable as a real pre-merge gate.

3. **Drift detection**

   Differentiates it from grep-style scanners.

4. **Repo hygiene expansion**

   Turns it into a serious repository sanity tool.

The first version should not try to be clever. It should be fast, deterministic, and useful.

The long-term product should become a configurable pre-merge quality gate that catches practical issues ignored by conventional linting and testing tools, while presenting findings in a triage-oriented way that helps developers fix the right things first.
```
