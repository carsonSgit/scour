import os, osproc, strutils, unittest

import ../src/scourpkg/cli
import ../src/scourpkg/config
import ../src/scourpkg/errors
import ../src/scourpkg/files
import ../src/scourpkg/issues
import ../src/scourpkg/repo
import ../src/scourpkg/rules/branch_hygiene
import ../src/scourpkg/rules/cross_reference
import ../src/scourpkg/rules/repo_hygiene
import ../src/scourpkg/scan_plan
import ../src/scourpkg/text_output

proc expectFatal(body: proc()) =
  var raised = false
  try:
    body()
  except FatalUserError:
    raised = true
  check raised

template inDir(path: string; body: untyped) =
  let previousDir = getCurrentDir()
  setCurrentDir(path)
  try:
    body
  finally:
    setCurrentDir(previousDir)

proc run(command: string; workingDir = ""): tuple[output: string, exitCode: int] =
  if workingDir.len > 0:
    execCmdEx(command, workingDir = workingDir)
  else:
    execCmdEx(command)

proc initGitRepo(root: string) =
  createDir(root)
  check run("git init", root).exitCode == 0
  check run("git config user.email test@example.com", root).exitCode == 0
  check run("git config user.name Test", root).exitCode == 0
  writeFile(root / "tracked.txt", "tracked\n")
  check run("git add tracked.txt", root).exitCode == 0
  check run("git commit -m initial", root).exitCode == 0

proc cleanDir(path: string) =
  if dirExists(path):
    removeDir(path)

proc testPlan(root: string; candidates: seq[string]): ScanPlan =
  ScanPlan(
    mode: scanExplicitPaths,
    repo: RepoContext(root: root, isGit: false),
    candidates: candidates
  )

proc hasIssue(issues: seq[Issue]; ruleId: string): bool =
  for issue in issues:
    if issue.ruleId == ruleId:
      return true
  false

proc firstIssue(issues: seq[Issue]; ruleId: string): Issue =
  for issue in issues:
    if issue.ruleId == ruleId:
      return issue
  Issue()

suite "CLI parser":
  test "parses supported flags and paths":
    let options = parseCliArgs(@["--config", "scour.toml", "src"])
    check options.configPath == "scour.toml"
    check options.colorMode == colorAuto
    check options.explicitPaths == @["src"]

  test "parses color modes":
    check parseCliArgs(@["--color", "auto"]).colorMode == colorAuto
    check parseCliArgs(@["--color", "always"]).colorMode == colorAlways
    check parseCliArgs(@["--color", "never"]).colorMode == colorNever

  test "rejects invalid flags":
    expectFatal(proc() = discard parseCliArgs(@["--wat"]))
    expectFatal(proc() = discard parseCliArgs(@["--color", "sometimes"]))
    expectFatal(proc() = discard parseCliArgs(@["--color"]))

  test "rejects conflicting scan modes":
    expectFatal(proc() = discard parseCliArgs(@["--staged", "--all"]))
    expectFatal(proc() = discard parseCliArgs(@["--since", "main", "src"]))

suite "issue summaries":
  test "summarizes empty issue lists":
    let summary = summarizeIssues(@[])
    check summary.total == 0
    check summary.bySeverity.errors == 0
    check summary.bySeverity.warnings == 0
    check summary.bySeverity.infos == 0
    check summary.affectedFiles == 0

  test "counts mixed severities":
    let issues = @[
      Issue(ruleId: "rule/a", severity: severityError, file: "a.nim"),
      Issue(ruleId: "rule/b", severity: severityWarning, file: "b.nim"),
      Issue(ruleId: "rule/c", severity: severityInfo, file: "c.nim"),
      Issue(ruleId: "rule/d", severity: severityWarning, file: "d.nim")
    ]
    let summary = summarizeIssues(issues)
    check summary.total == 4
    check summary.bySeverity.errors == 1
    check summary.bySeverity.warnings == 2
    check summary.bySeverity.infos == 1

  test "counts duplicate files once":
    let issues = @[
      Issue(ruleId: "rule/a", severity: severityError, file: "a.nim"),
      Issue(ruleId: "rule/b", severity: severityWarning, file: "a.nim"),
      Issue(ruleId: "rule/c", severity: severityInfo, file: "b.nim")
    ]
    check summarizeIssues(issues).affectedFiles == 2

suite "text output":
  test "renders clean scan pass message":
    check renderIssues(@[], colorNever) == "Scour passed. No failing issues found.\n"

  test "renders issue details and summary":
    let output = renderIssues(@[
      Issue(
        ruleId: "config/missing",
        severity: severityError,
        category: "config",
        triage: triageBlocker,
        file: "src/scour.nim",
        line: 10,
        column: 4,
        message: "Missing required config.",
        suggestion: "Add scour.toml."
      ),
      Issue(
        ruleId: "docs/stale",
        severity: severityWarning,
        category: "docs",
        triage: triageReview,
        file: "README.md",
        message: "README is stale."
      )
    ], colorNever)
    check "error config/missing src/scour.nim:10:4 - Missing required config." in output
    check "Suggestion: Add scour.toml." in output
    check "warning docs/stale README.md - README is stale." in output
    check "Summary: 2 issue(s), 1 error(s), 1 warning(s), 0 info(s), 2 file(s)" in output

  test "formats locations with optional line and column":
    check location(Issue(file: "a.nim")) == "a.nim"
    check location(Issue(file: "a.nim", line: 3)) == "a.nim:3"
    check location(Issue(file: "a.nim", line: 3, column: 9)) == "a.nim:3:9"

  test "controls ANSI color output":
    let issues = @[Issue(ruleId: "rule/a", severity: severityError, file: "a.nim", message: "Bad.")]
    check "\e[" notin renderIssues(issues, colorNever)
    check "\e[" in renderIssues(issues, colorAlways)

suite "repo and config discovery":
  test "uses current directory outside Git":
    let root = getTempDir() / "scour-outside-git"
    cleanDir(root)
    createDir(root)
    inDir root:
      let context = discoverRepo()
      check sameFile(context.root, root)
      check context.isGit == false

  test "finds repository root inside Git":
    let root = getTempDir() / "scour-git-root"
    cleanDir(root)
    initGitRepo(root)
    createDir(root / "nested")
    inDir root / "nested":
      let context = discoverRepo()
      check sameFile(context.root, root)
      check context.isGit == true

  test "discovers config in order and rejects missing explicit config":
    let root = getTempDir() / "scour-config"
    cleanDir(root)
    createDir(root)
    writeFile(root / ".scour.toml", "")
    let context = RepoContext(root: root, isGit: false)
    check discoverConfig(context, "").path == root / ".scour.toml"
    expectFatal(proc() = discard discoverConfig(context, "missing.toml"))

suite "config loading":
  test "defaults all rule settings on when no config is discovered":
    let loaded = loadConfig(ConfigDiscovery(path: "", isExplicit: false))
    check loaded.rules.consoleLog == true

  test "loads discovered console-log rule setting":
    let root = getTempDir() / "scour-runtime-config"
    cleanDir(root)
    createDir(root)
    writeFile(root / "scour.toml", "[rules]\nconsole-log = false\n")
    let discovery = ConfigDiscovery(path: root / "scour.toml", isExplicit: false)
    check loadConfig(discovery).rules.consoleLog == false

  test "rejects invalid explicit config syntax":
    let root = getTempDir() / "scour-invalid-config"
    cleanDir(root)
    createDir(root)
    writeFile(root / "scour.toml", "[rules\n")
    let discovery = ConfigDiscovery(path: root / "scour.toml", isExplicit: true)
    expectFatal(proc() = discard loadConfig(discovery))

suite "branch hygiene rules":
  test "reports each hygiene rule with file line and column":
    let root = getTempDir() / "scour-rules"
    cleanDir(root)
    createDir(root)
    writeFile(root / "app.ts", [
      "const ok = 1;",
      "<<<<<<< HEAD",
      "debugger;",
      "describe.only('focused', () => {});",
      "it.skip('skipped', () => {});",
      "console.log('debug');",
      "// @ts-ignore",
      "const value: string = 1;"
    ].join("\n"))

    let issues = scanBranchHygiene(testPlan(root, @["app.ts"]))
    check issues.hasIssue("merge-conflict")
    check issues.hasIssue("debugger")
    check issues.hasIssue("focused-test")
    check issues.hasIssue("skipped-test")
    check issues.hasIssue("console-log")
    check issues.hasIssue("ts-ignore")

    let consoleIssue = issues.firstIssue("console-log")
    check consoleIssue.file == "app.ts"
    check consoleIssue.line == 6
    check consoleIssue.column == 1

    let tsIgnore = issues.firstIssue("ts-ignore")
    check tsIgnore.line == 7
    check tsIgnore.column == 4

  test "recognizes alternate focused and skipped test forms":
    let root = getTempDir() / "scour-test-forms"
    cleanDir(root)
    createDir(root)
    writeFile(root / "spec.ts", "fdescribe('a', () => {});\nfit('b', () => {});\nxdescribe('c', () => {});\nxit('d', () => {});\n")
    let issues = scanBranchHygiene(testPlan(root, @["spec.ts"]))
    check issues.firstIssue("focused-test").line == 1
    check issues.firstIssue("skipped-test").line == 3

  test "keeps low false positive behavior":
    let root = getTempDir() / "scour-rule-negatives"
    cleanDir(root)
    createDir(root)
    writeFile(root / "app.ts", [
      "// debugger;",
      "// console.log('commented');",
      "console.error('real but allowed');",
      "const profit = 1;",
      "// @ts-expect-error",
      "const value: string = 1;"
    ].join("\n"))
    let issues = scanBranchHygiene(testPlan(root, @["app.ts"]))
    check issues.len == 0

  test "disables console-log through runtime config":
    let root = getTempDir() / "scour-console-disabled"
    cleanDir(root)
    createDir(root)
    writeFile(root / "app.ts", "console.log('debug');\n")
    let cfg = RuntimeConfig(rules: RuleSettings(consoleLog: false))
    let issues = scanBranchHygiene(testPlan(root, @["app.ts"]), cfg)
    check issues.hasIssue("console-log") == false

  test "scopes JavaScript and TypeScript rules to matching files":
    let root = getTempDir() / "scour-rule-scope"
    cleanDir(root)
    createDir(root)
    writeFile(root / "notes.txt", "debugger;\nconsole.log('debug');\n@ts-ignore\n")
    let issues = scanBranchHygiene(testPlan(root, @["notes.txt"]))
    check issues.len == 0

suite "repository hygiene rules":
  test "reports duplicate lockfiles in one package root":
    let root = getTempDir() / "scour-duplicate-lockfiles"
    cleanDir(root)
    createDir(root / "app")
    writeFile(root / "app" / "package.json", "{}\n")
    writeFile(root / "app" / "package-lock.json", "{}\n")
    writeFile(root / "app" / "yarn.lock", "\n")

    let issues = scanRepoHygiene(testPlan(root, @[
      "app/package.json",
      "app/package-lock.json",
      "app/yarn.lock"
    ]))
    check issues.hasIssue("duplicate-lockfiles")

    let issue = issues.firstIssue("duplicate-lockfiles")
    check issue.file == "app/package.json"
    check issue.category == "package-drift"
    check issue.triage == triageFixNow
    check issue.severity == severityWarning

  test "allows different package roots with one lockfile each":
    let root = getTempDir() / "scour-lockfiles-by-root"
    cleanDir(root)
    createDir(root / "app")
    createDir(root / "site")
    writeFile(root / "app" / "package.json", "{}\n")
    writeFile(root / "app" / "package-lock.json", "{}\n")
    writeFile(root / "site" / "package.json", "{}\n")
    writeFile(root / "site" / "yarn.lock", "\n")

    let issues = scanRepoHygiene(testPlan(root, @[
      "app/package.json",
      "app/package-lock.json",
      "site/package.json",
      "site/yarn.lock"
    ]))
    check issues.hasIssue("duplicate-lockfiles") == false

  test "reports Dockerfile without same-directory dockerignore":
    let root = getTempDir() / "scour-dockerignore-missing"
    cleanDir(root)
    createDir(root / "services" / "api")
    writeFile(root / "services" / "api" / "Dockerfile", "FROM scratch\n")

    let issues = scanRepoHygiene(testPlan(root, @["services/api/Dockerfile"]))
    check issues.hasIssue("dockerignore-missing")

    let issue = issues.firstIssue("dockerignore-missing")
    check issue.file == "services/api/Dockerfile"
    check issue.category == "docker-drift"
    check issue.triage == triageFixNow
    check issue.severity == severityWarning

  test "allows Dockerfile with same-directory dockerignore":
    let root = getTempDir() / "scour-dockerignore-present"
    cleanDir(root)
    createDir(root / "services" / "api")
    writeFile(root / "services" / "api" / "Dockerfile.prod", "FROM scratch\n")
    writeFile(root / "services" / "api" / ".dockerignore", "node_modules\n")

    let issues = scanRepoHygiene(testPlan(root, @[
      "services/api/Dockerfile.prod",
      "services/api/.dockerignore"
    ]))
    check issues.hasIssue("dockerignore-missing") == false

  test "reports generated files at any path segment":
    let root = getTempDir() / "scour-generated-files"
    cleanDir(root)
    createDir(root / "packages" / "web" / "dist")
    createDir(root / "coverage")
    writeFile(root / "packages" / "web" / "dist" / "index.js", "build output\n")
    writeFile(root / "coverage" / "report.txt", "coverage output\n")

    let issues = scanRepoHygiene(testPlan(root, @[
      "packages/web/dist/index.js",
      "coverage/report.txt"
    ]))
    check issues.hasIssue("generated-files")
    check issues.firstIssue("generated-files").category == "repo-hygiene"

  test "ignores untracked generated files in Git repositories":
    let root = getTempDir() / "scour-generated-untracked"
    cleanDir(root)
    initGitRepo(root)
    createDir(root / "dist")
    writeFile(root / "dist" / "index.js", "build output\n")

    let plan = ScanPlan(
      mode: scanAll,
      repo: RepoContext(root: root, isGit: true),
      candidates: @["dist/index.js"]
    )
    let issues = scanRepoHygiene(plan)
    check issues.hasIssue("generated-files") == false

suite "cross-reference rules":
  test "reports env usage missing from env examples":
    let root = getTempDir() / "scour-env-drift"
    cleanDir(root)
    createDir(root)
    writeFile(root / "app.ts", "const token = process.env.API_TOKEN;\n")

    let issues = scanCrossReference(testPlan(root, @["app.ts"]))
    check issues.hasIssue("env-drift")
    let issue = issues.firstIssue("env-drift")
    check issue.file == "app.ts"
    check issue.line == 1
    check issue.column == 15
    check issue.category == "env-drift"
    check issue.triage == triageBlocker
    check issue.severity == severityError

  test "does not report ignored or documented env vars":
    let root = getTempDir() / "scour-env-drift-negatives"
    cleanDir(root)
    createDir(root)
    writeFile(root / ".env.example", "API_TOKEN=\n")
    writeFile(root / "app.ts", "const mode = process.env.NODE_ENV;\nconst token = process.env.API_TOKEN;\n")

    let issues = scanCrossReference(testPlan(root, @["app.ts", ".env.example"]))
    check issues.hasIssue("env-drift") == false

  test "reports README command with missing script target":
    let root = getTempDir() / "scour-readme-command-drift"
    cleanDir(root)
    createDir(root)
    writeFile(root / "README.md", "```sh\nnpm run missing\n```\n")
    writeFile(root / "package.json", """{"scripts":{"test":"nimble test"}}""" & "\n")

    let issues = scanCrossReference(testPlan(root, @["README.md", "package.json"]))
    check issues.hasIssue("readme-command-drift")
    let issue = issues.firstIssue("readme-command-drift")
    check issue.file == "README.md"
    check issue.category == "docs-drift"
    check issue.triage == triageFixNow
    check issue.severity == severityWarning

  test "accepts README commands with existing package scripts and task targets":
    let root = getTempDir() / "scour-readme-command-valid"
    cleanDir(root)
    createDir(root)
    writeFile(root / "README.md", "```sh\nnpm run test\nmake build\njust lint\ntask docs\n```\n")
    writeFile(root / "package.json", """{"scripts":{"test":"nimble test"}}""" & "\n")
    writeFile(root / "Makefile", "build:\n\ttrue\n")
    writeFile(root / "justfile", "lint:\n  true\n")
    writeFile(root / "Taskfile.yml", "tasks:\n  docs:\n    cmds:\n      - true\n")

    let issues = scanCrossReference(testPlan(root, @[
      "README.md",
      "package.json",
      "Makefile",
      "justfile",
      "Taskfile.yml"
    ]))
    check issues.hasIssue("readme-command-drift") == false

  test "reports CI run command with missing script target":
    let root = getTempDir() / "scour-ci-command-drift"
    cleanDir(root)
    createDir(root / ".github" / "workflows")
    writeFile(root / ".github" / "workflows" / "ci.yml", "jobs:\n  test:\n    steps:\n      - run: npm run missing\n")
    writeFile(root / "package.json", """{"scripts":{"test":"nimble test"}}""" & "\n")

    let issues = scanCrossReference(testPlan(root, @[
      ".github/workflows/ci.yml",
      "package.json"
    ]))
    check issues.hasIssue("ci-command-drift")
    let issue = issues.firstIssue("ci-command-drift")
    check issue.file == ".github/workflows/ci.yml"
    check issue.category == "ci-drift"
    check issue.triage == triageBlocker
    check issue.severity == severityError

  test "accepts CI run commands with valid inline and block targets":
    let root = getTempDir() / "scour-ci-command-valid"
    cleanDir(root)
    createDir(root / ".github" / "workflows")
    writeFile(root / ".github" / "workflows" / "ci.yml", "jobs:\n  test:\n    steps:\n      - run: npm run test\n      - run: |\n          make build\n")
    writeFile(root / "package.json", """{"scripts":{"test":"nimble test"}}""" & "\n")
    writeFile(root / "Makefile", "build:\n\ttrue\n")

    let issues = scanCrossReference(testPlan(root, @[
      ".github/workflows/ci.yml",
      "package.json",
      "Makefile"
    ]))
    check issues.hasIssue("ci-command-drift") == false

  test "reports package lock drift in Git inventory":
    let root = getTempDir() / "scour-package-lock-git"
    cleanDir(root)
    initGitRepo(root)
    createDir(root / "app")
    writeFile(root / "app" / "package.json", "{}\n")
    writeFile(root / "app" / "package-lock.json", "{}\n")
    check run("git add app/package.json app/package-lock.json", root).exitCode == 0
    check run("git commit -m package", root).exitCode == 0
    writeFile(root / "app" / "package.json", """{"scripts":{"test":"true"}}""" & "\n")

    let issues = scanCrossReference(ScanPlan(
      mode: scanChanged,
      repo: RepoContext(root: root, isGit: true),
      candidates: @["app/package.json"]
    ))
    check issues.hasIssue("package-lock-drift")
    let issue = issues.firstIssue("package-lock-drift")
    check issue.file == "app/package.json"
    check issue.category == "package-drift"
    check issue.triage == triageFixNow
    check issue.severity == severityWarning

  test "does not report package lock drift when lockfile changed or no lockfile exists":
    let root = getTempDir() / "scour-package-lock-negatives"
    cleanDir(root)
    initGitRepo(root)
    createDir(root / "with-lock")
    createDir(root / "no-lock")
    writeFile(root / "with-lock" / "package.json", "{}\n")
    writeFile(root / "with-lock" / "package-lock.json", "{}\n")
    writeFile(root / "no-lock" / "package.json", "{}\n")
    check run("git add with-lock/package.json with-lock/package-lock.json no-lock/package.json", root).exitCode == 0
    check run("git commit -m packages", root).exitCode == 0

    let withLockIssues = scanCrossReference(ScanPlan(
      mode: scanChanged,
      repo: RepoContext(root: root, isGit: true),
      candidates: @["with-lock/package.json", "with-lock/package-lock.json"]
    ))
    check withLockIssues.hasIssue("package-lock-drift") == false

    let noLockIssues = scanCrossReference(ScanPlan(
      mode: scanChanged,
      repo: RepoContext(root: root, isGit: true),
      candidates: @["no-lock/package.json"]
    ))
    check noLockIssues.hasIssue("package-lock-drift") == false

suite "scan planning and files":
  test "selects default modes":
    check resolveScanMode(CliOptions(), RepoContext(root: ".", isGit: true)) == scanChanged
    check resolveScanMode(CliOptions(), RepoContext(root: ".", isGit: false)) == scanAll

  test "expands explicit files and directories":
    let root = getTempDir() / "scour-explicit"
    cleanDir(root)
    createDir(root / "src")
    writeFile(root / "src" / "a.nim", "echo 1\n")
    writeFile(root / "src" / "binary.bin", "abc\0def")
    writeFile(root / "top.txt", "top\n")
    let context = RepoContext(root: root, isGit: false)
    let options = CliOptions(explicitPaths: @["src", "top.txt"])
    let collected = collectCandidates(context, scanExplicitPaths, options)
    check collected.files == @["src/a.nim", "top.txt"]

  test "collects staged files from real Git":
    let root = getTempDir() / "scour-staged"
    cleanDir(root)
    initGitRepo(root)
    writeFile(root / "staged.txt", "staged\n")
    check run("git add staged.txt", root).exitCode == 0
    let context = RepoContext(root: root, isGit: true)
    let collected = collectCandidates(context, scanStaged, CliOptions(staged: true))
    check collected.files == @["staged.txt"]

  test "collects files since a real Git ref":
    let root = getTempDir() / "scour-since"
    cleanDir(root)
    initGitRepo(root)
    writeFile(root / "changed.txt", "changed\n")
    check run("git add changed.txt", root).exitCode == 0
    check run("git commit -m changed", root).exitCode == 0
    let context = RepoContext(root: root, isGit: true)
    let options = CliOptions(sinceRef: "HEAD~1")
    let collected = collectCandidates(context, scanChanged, options)
    check collected.baseRef == "HEAD~1"
    check collected.files == @["changed.txt"]

suite "command behavior":
  test "help version invalid and basic scan commands":
    let binary = getTempDir() / "scour-test-bin"
    let cache = getTempDir() / "scour-test-nimcache"
    if fileExists(binary):
      removeFile(binary)
    cleanDir(cache)
    let build = run("nim c --nimcache:" & cache.quoteShell & " -o:" & binary.quoteShell & " src/scour.nim")
    check build.exitCode == 0

    check run(binary.quoteShell & " --help").exitCode == 0
    check run(binary.quoteShell & " --version").exitCode == 0
    check run(binary.quoteShell & " --not-a-flag").exitCode == 2
    check run(binary.quoteShell & " --color sometimes").exitCode == 2

    let root = getTempDir() / "scour-command"
    cleanDir(root)
    initGitRepo(root)
    writeFile(root / "new.txt", "new\n")
    let allResult = run(binary.quoteShell & " --all", root)
    check allResult.exitCode == 0
    check allResult.output == "Scour passed. No failing issues found.\n"
    check run(binary.quoteShell & " new.txt", root).exitCode == 0
    check run("git add new.txt", root).exitCode == 0
    check run(binary.quoteShell & " --staged", root).exitCode == 0
    check run(binary.quoteShell & " --since HEAD", root).exitCode == 0

  test "scan commands render hygiene issues across modes":
    let binary = getTempDir() / "scour-test-bin-rules"
    let cache = getTempDir() / "scour-test-nimcache-rules"
    if fileExists(binary):
      removeFile(binary)
    cleanDir(cache)
    let build = run("nim c --nimcache:" & cache.quoteShell & " -o:" & binary.quoteShell & " src/scour.nim")
    check build.exitCode == 0

    let root = getTempDir() / "scour-command-rules"
    cleanDir(root)
    initGitRepo(root)

    writeFile(root / "all.ts", "console.log('all');\n")
    let allResult = run(binary.quoteShell & " --all", root)
    check allResult.exitCode == 0
    check "error console-log all.ts:1:1 - console.log call found." in allResult.output

    writeFile(root / "explicit.ts", "debugger;\n")
    let explicitResult = run(binary.quoteShell & " explicit.ts", root)
    check explicitResult.exitCode == 0
    check "error debugger explicit.ts:1:1 - Debugger statement found." in explicitResult.output

    writeFile(root / "staged.ts", "it.only('focused', () => {});\n")
    check run("git add staged.ts", root).exitCode == 0
    let stagedResult = run(binary.quoteShell & " --staged", root)
    check stagedResult.exitCode == 0
    check "error focused-test staged.ts:1:1 - Focused test left in source." in stagedResult.output

    check run("git add all.ts explicit.ts", root).exitCode == 0
    check run("git commit -m hygiene-fixtures", root).exitCode == 0
    writeFile(root / "since.ts", "test.skip('skipped', () => {});\n")
    check run("git add since.ts", root).exitCode == 0
    check run("git commit -m since-fixture", root).exitCode == 0
    let sinceResult = run(binary.quoteShell & " --since HEAD~1", root)
    check sinceResult.exitCode == 0
    check "error skipped-test since.ts:1:1 - Skipped test left in source." in sinceResult.output

    writeFile(root / "scour.toml", "[rules]\nconsole-log = false\n")
    let disabledResult = run(binary.quoteShell & " --config scour.toml all.ts", root)
    check disabledResult.exitCode == 0
    check disabledResult.output == "Scour passed. No failing issues found.\n"

  test "scan commands render repository hygiene issue ids":
    let binary = getTempDir() / "scour-test-bin-repo-rules"
    let cache = getTempDir() / "scour-test-nimcache-repo-rules"
    if fileExists(binary):
      removeFile(binary)
    cleanDir(cache)
    let build = run("nim c --nimcache:" & cache.quoteShell & " -o:" & binary.quoteShell & " src/scour.nim")
    check build.exitCode == 0

    let root = getTempDir() / "scour-command-repo-rules"
    cleanDir(root)
    initGitRepo(root)
    createDir(root / "app")
    createDir(root / "dist")
    writeFile(root / "app" / "package.json", "{}\n")
    writeFile(root / "app" / "package-lock.json", "{}\n")
    writeFile(root / "app" / "pnpm-lock.yaml", "\n")
    writeFile(root / "Dockerfile", "FROM scratch\n")
    writeFile(root / "dist" / "index.js", "build output\n")
    check run("git add app/package.json app/package-lock.json app/pnpm-lock.yaml Dockerfile dist/index.js", root).exitCode == 0

    let result = run(binary.quoteShell & " --all", root)
    check result.exitCode == 0
    check "warning duplicate-lockfiles app/package.json - Multiple package manager lockfiles found in the same package root." in result.output
    check "warning dockerignore-missing Dockerfile - Dockerfile has no same-directory .dockerignore." in result.output
    check "warning generated-files dist/index.js - Generated output is tracked in the repository." in result.output

  test "scan commands render cross-reference issue ids":
    let binary = getTempDir() / "scour-test-bin-cross-rules"
    let cache = getTempDir() / "scour-test-nimcache-cross-rules"
    if fileExists(binary):
      removeFile(binary)
    cleanDir(cache)
    let build = run("nim c --nimcache:" & cache.quoteShell & " -o:" & binary.quoteShell & " src/scour.nim")
    check build.exitCode == 0

    let root = getTempDir() / "scour-command-cross-rules"
    cleanDir(root)
    initGitRepo(root)
    createDir(root / ".github" / "workflows")
    createDir(root / "app")
    writeFile(root / "app" / "package.json", "{}\n")
    writeFile(root / "app" / "package-lock.json", "{}\n")
    writeFile(root / "README.md", "```sh\nnpm run missing\n```\n")
    writeFile(root / ".github" / "workflows" / "ci.yml", "jobs:\n  test:\n    steps:\n      - run: npm run missing\n")
    writeFile(root / "app.ts", "const token = process.env.API_TOKEN;\n")
    check run("git add app/package.json app/package-lock.json README.md .github/workflows/ci.yml app.ts", root).exitCode == 0
    check run("git commit -m cross-reference-fixtures", root).exitCode == 0
    writeFile(root / "app" / "package.json", """{"scripts":{"test":"true"}}""" & "\n")

    let result = run(binary.quoteShell & " app.ts README.md .github/workflows/ci.yml app/package.json", root)
    check result.exitCode == 0
    check "error env-drift app.ts:1:15 - Environment variable API_TOKEN is used but absent from env example files." in result.output
    check "warning readme-command-drift README.md:2:1 - Command `npm run missing` references a missing script or task target." in result.output
    check "error ci-command-drift .github/workflows/ci.yml:4:14 - Command `npm run missing` references a missing script or task target." in result.output
    check "warning package-lock-drift app/package.json - package.json changed without its existing Node lockfile." in result.output
