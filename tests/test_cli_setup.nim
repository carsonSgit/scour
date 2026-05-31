import json, os, osproc, strutils, unittest

import ../src/scourpkg/cli
import ../src/scourpkg/config
import ../src/scourpkg/errors
import ../src/scourpkg/files
import ../src/scourpkg/issues
import ../src/scourpkg/github_output
import ../src/scourpkg/json_output
import ../src/scourpkg/repo
import ../src/scourpkg/rule_catalog
import ../src/scourpkg/rule_output
import ../src/scourpkg/rules/branch_hygiene
import ../src/scourpkg/rules/cross_reference
import ../src/scourpkg/rules/repo_hygiene
import ../src/scourpkg/scan_plan
import ../src/scourpkg/text_output
import ../src/scourpkg/triage_output

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

proc run(command: string; workingDir = ""): tuple[output: string;
    exitCode: int] =
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

proc copyFixture(name, root: string) =
  let source = getCurrentDir() / "tests" / "fixtures" / name
  for path in walkDirRec(source, relative = true):
    let destination = root / path
    createDir(destination.parentDir())
    copyFile(source / path, destination)

proc initFixtureRepo(name, root: string) =
  cleanDir(root)
  createDir(root)
  copyFixture(name, root)
  check run("git init", root).exitCode == 0
  check run("git config user.email test@example.com", root).exitCode == 0
  check run("git config user.name Test", root).exitCode == 0
  check run("git add .", root).exitCode == 0
  check run("git commit -m fixture", root).exitCode == 0

proc fixtureBinary(): string =
  result = getTempDir() / "scour-fixture-bin"
  if fileExists(result):
    return
  let cache = getTempDir() / "scour-fixture-nimcache"
  cleanDir(cache)
  check run("nim c --nimcache:" & cache.quoteShell & " -o:" &
      result.quoteShell & " src/scour.nim").exitCode == 0

proc snapshot(name: string): string =
  readFile(getCurrentDir() / "tests" / "snapshots" / name)

proc checkSnapshot(result: tuple[output: string; exitCode: int];
    name: string; exitCode: int) =
  check result.exitCode == exitCode
  check result.output == snapshot(name)

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

proc hasSeverityOverride(config: RuntimeConfig; ruleId: string;
    severity: RuleSeverity): bool =
  let setting = config.ruleOverride(ruleId)
  setting.hasSeverity and setting.severity == severity

proc hasTriageOverride(config: RuntimeConfig; ruleId: string;
    triage: TriageLevel): bool =
  let setting = config.ruleOverride(ruleId)
  setting.hasTriage and setting.triage == triage

suite "CLI parser":
  test "parses supported flags and paths":
    let options = parseCliArgs(@["--config", "scour.toml", "src"])
    check options.configPath == "scour.toml"
    check options.colorMode == colorAuto
    check options.explicitPaths == @["src"]
    check parseCliArgs(@["--", "-dash.ts"]).explicitPaths == @["-dash.ts"]

  test "parses color modes":
    check parseCliArgs(@["--color", "auto"]).colorMode == colorAuto
    check parseCliArgs(@["--color", "always"]).colorMode == colorAlways
    check parseCliArgs(@["--color", "never"]).colorMode == colorNever

  test "parses CI output options":
    let options = parseCliArgs(@[
      "--format", "github", "--fail-on", "warning", "--exit-zero"
    ])
    check options.outputFormat == formatGitHub
    check options.formatExplicit
    check options.failOn == failOnWarning
    check options.failOnExplicit
    check options.exitZero

  test "rejects invalid flags":
    expectFatal(proc() = discard parseCliArgs(@["--wat"]))
    expectFatal(proc() = discard parseCliArgs(@["--color", "sometimes"]))
    expectFatal(proc() = discard parseCliArgs(@["--color"]))
    expectFatal(proc() = discard parseCliArgs(@["--format", "xml"]))
    expectFatal(proc() = discard parseCliArgs(@["--fail-on", "warn"]))

  test "rejects conflicting scan modes":
    expectFatal(proc() = discard parseCliArgs(@["--staged", "--all"]))
    expectFatal(proc() = discard parseCliArgs(@["--since", "main", "src"]))

  test "parses discovery commands":
    check parseCliArgs(@["rules"]).command == commandRules
    let explain = parseCliArgs(@["--config", "scour.toml", "explain",
        "console-log"])
    check explain.command == commandExplain
    check explain.explainRuleId == "console-log"
    check parseCliArgs(@["triage", "--all"]).command == commandTriage
    expectFatal(proc() = discard parseCliArgs(@["triage", "--format", "json"]))

  test "rejects invalid discovery commands":
    expectFatal(proc() = discard parseCliArgs(@["explain"]))
    expectFatal(proc() = discard parseCliArgs(@["explain", "missing-rule"]))
    expectFatal(proc() = discard parseCliArgs(@["explain", "console_log"]))
    expectFatal(proc() = discard parseCliArgs(@["rules", "extra"]))
    expectFatal(proc() = discard parseCliArgs(@["--all", "rules"]))
    expectFatal(proc() = discard parseCliArgs(@["--fail-on", "warning",
        "rules"]))

suite "rule catalog":
  test "contains canonical rules in stable alphabetical order":
    let rules = sortedRules()
    check rules.len == 13
    for index in 1 ..< rules.len:
      check rules[index - 1].id < rules[index].id
    check validRuleId("console-log")
    check not validRuleId("console_log")

  test "renders defaults and effective overrides":
    let config = RuntimeConfig(rules: @[
      RuleOverride(ruleId: "console-log", severity: ruleSeverityOff,
        hasSeverity: true, triage: triageCleanup, hasTriage: true)
    ])
    check "console-log  off  cleanup\n" in renderRules(config)
    let explanation = renderExplanation(findRule("console-log"), config)
    check "Severity: off\n" in explanation
    check "Triage: cleanup\n" in explanation

suite "issue summaries":
  test "summarizes empty issue lists":
    let summary = summarizeIssues(@[])
    check summary.total == 0
    check summary.bySeverity.errors == 0
    check summary.bySeverity.warnings == 0
    check summary.bySeverity.infos == 0
    check summary.affectedFiles == 0
    check summary.byTriage.ignored == 0

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

  test "counts triage levels and evaluates thresholds":
    let issues = @[
      Issue(severity: severityError, triage: triageBlocker),
      Issue(severity: severityWarning, triage: triageFixNow),
      Issue(severity: severityInfo, triage: triageReview),
      Issue(severity: severityInfo, triage: triageCleanup),
      Issue(severity: severityInfo, triage: triageIgnored)
    ]
    let summary = summarizeIssues(issues)
    check summary.byTriage.blockers == 1
    check summary.byTriage.fixNow == 1
    check summary.byTriage.review == 1
    check summary.byTriage.cleanup == 1
    check summary.byTriage.ignored == 1
    check @[Issue(severity: severityError)].hasFailingIssues(failOnError)
    check @[Issue(severity: severityWarning)].hasFailingIssues(failOnError) == false
    check @[Issue(severity: severityWarning)].hasFailingIssues(failOnWarning)
    check @[Issue(severity: severityInfo)].hasFailingIssues(failOnInfo)

suite "structured output":
  test "renders stable JSON for clean scans and full issues":
    let clean = parseJson(renderJsonIssues(@[]))
    check clean["summary"]["total"].getInt() == 0
    check clean["summary"]["triage"]["ignored"].getInt() == 0
    check clean["issues"].len == 0
    let rendered = parseJson(renderJsonIssues(@[Issue(
      ruleId: "config/missing", severity: severityWarning,
      triage: triageReview, category: "config", file: "a.nim",
      line: 2, column: 3, message: "Missing.", suggestion: "Add it."
    )]))
    check rendered["issues"][0]["rule"].getStr() == "config/missing"
    check rendered["issues"][0]["severity"].getStr() == "warning"
    check rendered["issues"][0]["triage_level"].getStr() == "review"
    check rendered["issues"][0]["suggestion"].getStr() == "Add it."

  test "renders GitHub annotations with escaping and optional locations":
    check renderGitHubIssues(@[]) == ""
    let output = renderGitHubIssues(@[
      Issue(ruleId: "a:b,c", severity: severityError, file: "a,b.ts",
        line: 2, column: 3, message: "bad%\nline", suggestion: "fix\rnow"),
      Issue(ruleId: "notice", severity: severityInfo, file: "README.md",
        message: "review")
    ])
    check "::error file=a%2Cb.ts,title=a%3Ab%2Cc,line=2,col=3::bad%25%0Aline Suggestion: fix%0Dnow" in output
    check "::notice file=README.md,title=notice::review" in output

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
    let issues = @[Issue(ruleId: "rule/a", severity: severityError,
        file: "a.nim", message: "Bad.")]
    check "\e[" notin renderIssues(issues, colorNever)
    check "\e[" in renderIssues(issues, colorAlways)

  test "renders grouped triage in deterministic order":
    let output = renderTriage(@[
      Issue(ruleId: "review", severity: severityWarning,
        triage: triageReview, file: "b.ts", message: "Review."),
      Issue(ruleId: "block", severity: severityError,
        triage: triageBlocker, file: "a.ts", line: 2, message: "Block.")
    ])
    check output.startsWith("scour triage found 2 issue(s)\n\nBlockers\n")
    check output.find("Blockers") < output.find("Needs Review")
    check "  1 blocker(s)\n" in output
    check "  1 needs-review\n" in output

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
    check loaded.ruleIsOff("console-log") == false
    check loaded.envExampleFiles == @[".env.example", ".env.sample",
        ".env.template", ".env.defaults"]
    check "NODE_ENV" in loaded.ignoredEnvVars
    check loaded.outputColor == colorAuto
    check loaded.outputFormat == formatText
    check loaded.failOn == failOnError

  test "loads discovered console-log rule setting":
    let root = getTempDir() / "scour-runtime-config"
    cleanDir(root)
    createDir(root)
    writeFile(root / "scour.toml", "[rules]\nconsole-log = false\n")
    let discovery = ConfigDiscovery(path: root / "scour.toml",
        isExplicit: false)
    check loadConfig(discovery).ruleIsOff("console-log")

  test "loads PRD-style config sections and underscore rule keys":
    let root = getTempDir() / "scour-prd-config"
    cleanDir(root)
    createDir(root)
    writeFile(root / "scour.toml", [
      "[scan]",
      "max_file_size = \"1KB\"",
      "",
      "[output]",
      "format = \"json\"",
      "color = \"never\"",
      "",
      "[rules]",
      "console_log = \"warning\"",
      "ts_ignore = \"off\"",
      "",
      "[triage]",
      "console_log = \"review\"",
      "",
      "[ignore]",
      "paths = [",
      "  \"dist/**\",",
      "  \"vendor\"",
      "]",
      "",
      "[env]",
      "example_files = [\".env.contract\"]",
      "ignored_vars = [\"NODE_ENV\", \"PUBLIC_URL\"]"
    ].join("\n"))

    let loaded = loadConfig(ConfigDiscovery(path: root / "scour.toml",
        isExplicit: false))
    check loaded.maxFileSize == 1024
    check loaded.outputColor == colorNever
    check loaded.outputFormat == formatJson
    check loaded.hasSeverityOverride("console-log", ruleSeverityWarning)
    check loaded.hasTriageOverride("console-log", triageReview)
    check loaded.ruleIsOff("ts-ignore")
    check loaded.ignorePaths == @["dist/**", "vendor"]
    check loaded.envExampleFiles == @[".env.contract"]
    check loaded.ignoredEnvVars == @["NODE_ENV", "PUBLIC_URL"]

  test "rejects invalid explicit config syntax":
    let root = getTempDir() / "scour-invalid-config"
    cleanDir(root)
    createDir(root)
    writeFile(root / "scour.toml", "[rules\n")
    let discovery = ConfigDiscovery(path: root / "scour.toml", isExplicit: true)
    expectFatal(proc() = discard loadConfig(discovery))

  test "rejects invalid config section key severity triage and output format":
    let root = getTempDir() / "scour-invalid-config-values"
    cleanDir(root)
    createDir(root)

    writeFile(root / "section.toml", "[custom_patterns]\nfoo = \"bar\"\n")
    expectFatal(proc() = discard loadConfig(ConfigDiscovery(path: root /
        "section.toml", isExplicit: true)))

    writeFile(root / "key.toml", "[rules]\nunknown_rule = \"error\"\n")
    expectFatal(proc() = discard loadConfig(ConfigDiscovery(path: root /
        "key.toml", isExplicit: true)))

    writeFile(root / "severity.toml", "[rules]\nconsole_log = \"warn\"\n")
    expectFatal(proc() = discard loadConfig(ConfigDiscovery(path: root /
        "severity.toml", isExplicit: true)))

    writeFile(root / "triage.toml", "[triage]\nconsole_log = \"later\"\n")
    expectFatal(proc() = discard loadConfig(ConfigDiscovery(path: root /
        "triage.toml", isExplicit: true)))

    writeFile(root / "format.toml", "[output]\nformat = \"xml\"\n")
    expectFatal(proc() = discard loadConfig(ConfigDiscovery(path: root /
        "format.toml", isExplicit: true)))

    writeFile(root / "fail-on.toml", "fail_on = \"warn\"\n")
    expectFatal(proc() = discard loadConfig(ConfigDiscovery(path: root /
        "fail-on.toml", isExplicit: true)))

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
    let cfg = RuntimeConfig(rules: @[RuleOverride(ruleId: "console-log",
        severity: ruleSeverityOff, hasSeverity: true)])
    let issues = scanBranchHygiene(testPlan(root, @["app.ts"]), cfg)
    check issues.hasIssue("console-log") == false

  test "disables any rule and applies severity and triage overrides":
    let root = getTempDir() / "scour-rule-overrides"
    cleanDir(root)
    createDir(root)
    writeFile(root / "app.ts", "debugger;\n// @ts-ignore\nconst value: string = 1;\n")
    let cfg = RuntimeConfig(rules: @[
      RuleOverride(ruleId: "debugger", severity: ruleSeverityOff,
          hasSeverity: true),
      RuleOverride(ruleId: "ts-ignore", severity: ruleSeverityWarning,
          hasSeverity: true, triage: triageReview, hasTriage: true)
    ])
    let issues = scanBranchHygiene(testPlan(root, @["app.ts"]), cfg)
    check issues.hasIssue("debugger") == false
    let tsIgnore = issues.firstIssue("ts-ignore")
    check tsIgnore.severity == severityWarning
    check tsIgnore.triage == triageReview

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

  test "uses configured env example files and ignored env vars":
    let root = getTempDir() / "scour-env-config"
    cleanDir(root)
    createDir(root)
    writeFile(root / ".env.contract", "API_TOKEN=\n")
    writeFile(root / "app.ts", "const mode = process.env.PUBLIC_URL;\nconst token = process.env.API_TOKEN;\n")
    let cfg = RuntimeConfig(
      envExampleFiles: @[".env.contract"],
      ignoredEnvVars: @["PUBLIC_URL"],
      outputFormat: formatText
    )

    let issues = scanCrossReference(testPlan(root, @["app.ts",
        ".env.contract"]), cfg)
    check issues.hasIssue("env-drift") == false

  test "reports README command with missing script target":
    let root = getTempDir() / "scour-readme-command-drift"
    cleanDir(root)
    createDir(root)
    writeFile(root / "README.md", "```sh\nnpm run missing\n```\n")
    writeFile(root / "package.json", """{"scripts":{"test":"nimble test"}}""" & "\n")

    let issues = scanCrossReference(testPlan(root, @["README.md",
        "package.json"]))
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
    check run("git add app/package.json app/package-lock.json",
        root).exitCode == 0
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
    check run("git add with-lock/package.json with-lock/package-lock.json no-lock/package.json",
        root).exitCode == 0
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

  test "applies ignored paths and max file size to explicit candidates":
    let root = getTempDir() / "scour-filtered-candidates"
    cleanDir(root)
    createDir(root / "dist")
    createDir(root / "src")
    writeFile(root / "dist" / "ignored.ts", "console.log('ignored');\n")
    writeFile(root / "src" / "small.ts", "console.log('small');\n")
    writeFile(root / "src" / "large.ts", repeat("x", 80))
    let context = RepoContext(root: root, isGit: false)
    let options = CliOptions(explicitPaths: @["dist", "src"])
    let cfg = RuntimeConfig(ignorePaths: @["dist/**"], maxFileSize: 40)
    let collected = collectCandidates(context, scanExplicitPaths, options, cfg)
    check collected.files == @["src/small.ts"]

  test "collects staged files from real Git":
    let root = getTempDir() / "scour-staged"
    cleanDir(root)
    initGitRepo(root)
    writeFile(root / "staged.txt", "staged\n")
    check run("git add staged.txt", root).exitCode == 0
    let context = RepoContext(root: root, isGit: true)
    let collected = collectCandidates(context, scanStaged, CliOptions(staged: true))
    check collected.files == @["staged.txt"]

  test "applies ignored paths to staged files":
    let root = getTempDir() / "scour-staged-ignore"
    cleanDir(root)
    initGitRepo(root)
    createDir(root / "dist")
    writeFile(root / "dist" / "ignored.ts", "console.log('ignored');\n")
    writeFile(root / "kept.ts", "console.log('kept');\n")
    check run("git add dist/ignored.ts kept.ts", root).exitCode == 0
    let context = RepoContext(root: root, isGit: true)
    let cfg = RuntimeConfig(ignorePaths: @["dist/**"])
    let collected = collectCandidates(context, scanStaged, CliOptions(
        staged: true), cfg)
    check collected.files == @["kept.ts"]

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

  test "applies ignored paths to changed files":
    let root = getTempDir() / "scour-changed-ignore"
    cleanDir(root)
    initGitRepo(root)
    createDir(root / "dist")
    writeFile(root / "dist" / "ignored.ts", "old\n")
    writeFile(root / "kept.ts", "old\n")
    check run("git add dist/ignored.ts kept.ts", root).exitCode == 0
    check run("git commit -m baseline", root).exitCode == 0
    writeFile(root / "dist" / "ignored.ts", "console.log('ignored');\n")
    writeFile(root / "kept.ts", "console.log('kept');\n")
    check run("git add dist/ignored.ts kept.ts", root).exitCode == 0
    check run("git commit -m changed", root).exitCode == 0
    let context = RepoContext(root: root, isGit: true)
    let options = CliOptions(sinceRef: "HEAD~1")
    let cfg = RuntimeConfig(ignorePaths: @["dist/**"])
    let collected = collectCandidates(context, scanChanged, options, cfg)
    check collected.files == @["kept.ts"]

suite "command behavior":
  test "fixture repositories lock clean dirty formats and scan modes":
    let binary = fixtureBinary()
    let clean = getTempDir() / "scour-fixture-clean"
    initFixtureRepo("clean", clean)
    checkSnapshot(run(binary.quoteShell & " --all --color never", clean),
        "clean-text.txt", 0)

    let dirty = getTempDir() / "scour-fixture-dirty"
    initFixtureRepo("dirty", dirty)
    checkSnapshot(run(binary.quoteShell & " --all --color never", dirty),
        "dirty-text.txt", 1)
    checkSnapshot(run(binary.quoteShell & " --all --format json", dirty),
        "dirty-json.txt", 1)
    checkSnapshot(run(binary.quoteShell & " --all --format github", dirty),
        "dirty-github.txt", 1)
    check run(binary.quoteShell & " --all --fail-on warning", dirty).exitCode == 1
    check run(binary.quoteShell & " --all --exit-zero", dirty).exitCode == 0
    checkSnapshot(run(binary.quoteShell & " triage --all", dirty),
        "dirty-triage.txt", 1)
    check run(binary.quoteShell & " triage --format json", dirty).exitCode == 2

    writeFile(dirty / "overlay.ts", "console.log('overlay');\n")
    check run("git add overlay.ts", dirty).exitCode == 0
    check "console-log overlay.ts:1:1" in run(binary.quoteShell & " --staged",
        dirty).output
    check run("git commit -m overlay", dirty).exitCode == 0
    check "console-log overlay.ts:1:1" in run(binary.quoteShell &
        " --since HEAD~1", dirty).output
    check "debugger app.ts:2:1" in run(binary.quoteShell & " app.ts",
        dirty).output
    writeFile(dirty / "scour.toml",
        "[rules]\nconsole-log = \"off\"\n")
    check "console-log overlay.ts" notin run(binary.quoteShell &
        " --config scour.toml overlay.ts", dirty).output
    writeFile(dirty / "-dash.ts", "debugger;\n")
    check "debugger -dash.ts:1:1" in run(binary.quoteShell & " -- -dash.ts",
        dirty).output

  test "help version invalid and basic scan commands":
    let binary = getTempDir() / "scour-test-bin"
    let cache = getTempDir() / "scour-test-nimcache"
    if fileExists(binary):
      removeFile(binary)
    cleanDir(cache)
    let build = run("nim c --nimcache:" & cache.quoteShell & " -o:" &
        binary.quoteShell & " src/scour.nim")
    check build.exitCode == 0

    check run(binary.quoteShell & " --help").exitCode == 0
    check run(binary.quoteShell & " --version").exitCode == 0
    check run(binary.quoteShell & " --not-a-flag").exitCode == 2
    check run(binary.quoteShell & " --color sometimes").exitCode == 2
    check run(binary.quoteShell & " rules").output.contains(
        "console-log  warning  review")
    check run(binary.quoteShell & " explain console-log").output.contains(
        "Rule: console-log\n")
    check run(binary.quoteShell & " explain missing-rule").exitCode == 2

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
    writeFile(root / "scour.toml",
        "[rules]\nconsole-log = \"off\"\n[triage]\nconsole-log = \"cleanup\"\n")
    let configuredRules = run(binary.quoteShell & " --config scour.toml rules",
        root)
    check "console-log  off  cleanup" in configuredRules.output
    let configuredExplain = run(binary.quoteShell &
        " --config scour.toml explain console-log", root)
    check "Severity: off" in configuredExplain.output
    check "Triage: cleanup" in configuredExplain.output

  test "scan commands render hygiene issues across modes":
    let binary = getTempDir() / "scour-test-bin-rules"
    let cache = getTempDir() / "scour-test-nimcache-rules"
    if fileExists(binary):
      removeFile(binary)
    cleanDir(cache)
    let build = run("nim c --nimcache:" & cache.quoteShell & " -o:" &
        binary.quoteShell & " src/scour.nim")
    check build.exitCode == 0

    let root = getTempDir() / "scour-command-rules"
    cleanDir(root)
    initGitRepo(root)

    writeFile(root / "all.ts", "console.log('all');\n")
    let allResult = run(binary.quoteShell & " --all", root)
    check allResult.exitCode == 0
    check "warning console-log all.ts:1:1 - console.log call found." in
        allResult.output

    writeFile(root / "explicit.ts", "debugger;\n")
    let explicitResult = run(binary.quoteShell & " explicit.ts", root)
    check explicitResult.exitCode == 1
    check "error debugger explicit.ts:1:1 - Debugger statement found." in
        explicitResult.output

    writeFile(root / "staged.ts", "it.only('focused', () => {});\n")
    check run("git add staged.ts", root).exitCode == 0
    let stagedResult = run(binary.quoteShell & " --staged", root)
    check stagedResult.exitCode == 1
    check "error focused-test staged.ts:1:1 - Focused test left in source." in
        stagedResult.output

    check run("git add all.ts explicit.ts", root).exitCode == 0
    check run("git commit -m hygiene-fixtures", root).exitCode == 0
    writeFile(root / "since.ts", "test.skip('skipped', () => {});\n")
    check run("git add since.ts", root).exitCode == 0
    check run("git commit -m since-fixture", root).exitCode == 0
    let sinceResult = run(binary.quoteShell & " --since HEAD~1", root)
    check sinceResult.exitCode == 1
    check "error skipped-test since.ts:1:1 - Skipped test left in source." in
        sinceResult.output

    writeFile(root / "scour.toml", "[rules]\nconsole-log = false\n")
    let disabledResult = run(binary.quoteShell & " --config scour.toml all.ts", root)
    check disabledResult.exitCode == 0
    check disabledResult.output == "Scour passed. No failing issues found.\n"

    writeFile(root / "color.toml", "[output]\ncolor = \"always\"\n")
    let coloredResult = run(binary.quoteShell & " --config color.toml all.ts", root)
    check coloredResult.exitCode == 0
    check "\e[" in coloredResult.output

    let overrideColorResult = run(binary.quoteShell &
        " --config color.toml --color never all.ts", root)
    check overrideColorResult.exitCode == 0
    check "\e[" notin overrideColorResult.output

    check run(binary.quoteShell & " --exit-zero all.ts", root).exitCode == 0
    check run(binary.quoteShell & " --exit-zero --format xml all.ts",
        root).exitCode == 2

    writeFile(root / "ci.toml", "fail_on = \"warning\"\n[output]\nformat = \"json\"\n")
    let configResult = run(binary.quoteShell & " --config ci.toml all.ts", root)
    check configResult.exitCode == 1
    check configResult.output.startsWith("{")
    let cliOverride = run(binary.quoteShell &
        " --config ci.toml --format github all.ts", root)
    check cliOverride.output.startsWith("::warning ")

  test "scan commands render repository hygiene issue ids":
    let binary = getTempDir() / "scour-test-bin-repo-rules"
    let cache = getTempDir() / "scour-test-nimcache-repo-rules"
    if fileExists(binary):
      removeFile(binary)
    cleanDir(cache)
    let build = run("nim c --nimcache:" & cache.quoteShell & " -o:" &
        binary.quoteShell & " src/scour.nim")
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
    check run("git add app/package.json app/package-lock.json app/pnpm-lock.yaml Dockerfile dist/index.js",
        root).exitCode == 0

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
    let build = run("nim c --nimcache:" & cache.quoteShell & " -o:" &
        binary.quoteShell & " src/scour.nim")
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
    check run("git add app/package.json app/package-lock.json README.md .github/workflows/ci.yml app.ts",
        root).exitCode == 0
    check run("git commit -m cross-reference-fixtures", root).exitCode == 0
    writeFile(root / "app" / "package.json", """{"scripts":{"test":"true"}}""" & "\n")

    let result = run(binary.quoteShell &
        " app.ts README.md .github/workflows/ci.yml app/package.json", root)
    check result.exitCode == 1
    check "error env-drift app.ts:1:15 - Environment variable API_TOKEN is used but absent from env example files." in result.output
    check "warning readme-command-drift README.md:2:1 - Command `npm run missing` references a missing script or task target." in result.output
    check "error ci-command-drift .github/workflows/ci.yml:4:14 - Command `npm run missing` references a missing script or task target." in result.output
    check "warning package-lock-drift app/package.json - package.json changed without its existing Node lockfile." in result.output
