import json, os, osproc, sequtils, strutils, tables, times, unittest
when defined(posix):
  import posix

import ../src/scourpkg/cli
import ../src/scourpkg/fixes
import ../src/scourpkg/baseline
import ../src/scourpkg/codequality_output
import ../src/scourpkg/sarif_output
import ../src/scourpkg/config
import ../src/scourpkg/doctor_output
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
import ../src/scourpkg/rules/security
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

var fixtureBinaryBuilt = false

proc fixtureBinary(): string =
  result = getTempDir() / "scour-fixture-bin"
  if fixtureBinaryBuilt:
    return
  fixtureBinaryBuilt = true
  if fileExists(result):
    removeFile(result)
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
    candidates: candidates,
    selectedFiles: candidates
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
      "--format", "doctor", "--fail-on", "warning", "--exit-zero", "--score"
    ])
    check options.outputFormat == formatDoctor
    check options.formatExplicit
    check options.failOn == failOnWarning
    check options.failOnExplicit
    check options.exitZero
    check options.scoreOnly

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
    expectFatal(proc() = discard parseCliArgs(@["triage", "--score"]))
    expectFatal(proc() = discard parseCliArgs(@["rules", "extra"]))
    expectFatal(proc() = discard parseCliArgs(@["--all", "rules"]))
    expectFatal(proc() = discard parseCliArgs(@["--fail-on", "warning",
        "rules"]))

suite "rule catalog":
  test "contains canonical rules in stable alphabetical order":
    let rules = sortedRules()
    check rules.len == 17
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

  test "computes a bounded weighted score":
    let score = scoreIssues(@[
      Issue(severity: severityError, triage: triageBlocker),
      Issue(severity: severityWarning, triage: triageFixNow),
      Issue(severity: severityInfo, triage: triageReview)
    ])
    check score.current == 82
    check score.max == 100
    check score.model == "weighted-v2-frequency-capped"
    check score.deductions.errors == 10
    check score.deductions.warnings == 4
    check score.deductions.infos == 1
    check score.deductions.blockers == 3
    check score.deductions.total == 18
    let repeatedRuleScore = scoreIssues(@[
      Issue(ruleId: "same-rule", severity: severityWarning),
      Issue(ruleId: "same-rule", severity: severityWarning),
      Issue(ruleId: "same-rule", severity: severityWarning),
      Issue(ruleId: "same-rule", severity: severityWarning),
      Issue(ruleId: "same-rule", severity: severityWarning)
    ])
    let distinctRuleScore = scoreIssues(@[
      Issue(ruleId: "rule-1", severity: severityWarning),
      Issue(ruleId: "rule-2", severity: severityWarning),
      Issue(ruleId: "rule-3", severity: severityWarning),
      Issue(ruleId: "rule-4", severity: severityWarning),
      Issue(ruleId: "rule-5", severity: severityWarning)
    ])
    check repeatedRuleScore.deductions.warnings == 14
    check distinctRuleScore.deductions.warnings == 20
    check scoreIssues(@[
      Issue(severity: severityError, triage: triageBlocker),
      Issue(severity: severityError, triage: triageBlocker),
      Issue(severity: severityError, triage: triageBlocker),
      Issue(severity: severityError, triage: triageBlocker),
      Issue(severity: severityError, triage: triageBlocker),
      Issue(severity: severityError, triage: triageBlocker),
      Issue(severity: severityError, triage: triageBlocker),
      Issue(severity: severityError, triage: triageBlocker),
      Issue(severity: severityError, triage: triageBlocker),
      Issue(severity: severityError, triage: triageBlocker)
    ]).current == 54

suite "structured output":
  test "renders stable JSON for clean scans and full issues":
    let clean = parseJson(renderJsonIssues(@[], testPlan("", @[])))
    check clean["report_version"].getInt() == 1
    check clean["tool"]["name"].getStr() == "scour"
    check clean["tool"]["version"].getStr() == "0.4.5"
    check clean["summary"]["total"].getInt() == 0
    check clean["summary"]["triage"]["ignored"].getInt() == 0
    check clean["score"]["current"].getInt() == 100
    check clean["score"]["deductions"]["total"].getInt() == 0
    check clean["issues"].len == 0
    let rendered = parseJson(renderJsonIssues(@[Issue(
      ruleId: "config/missing", severity: severityWarning,
      triage: triageReview, category: "config", file: "a.nim",
      line: 2, column: 3, message: "Missing.", suggestion: "Add it."
    )], testPlan("", @[])))
    check rendered["scan"]["complete"].getBool() == true
    check rendered["issues"][0]["id"].getStr().len == 40
    check rendered["issues"][0]["fixable"].getBool() == false
    check rendered["score"]["current"].getInt() == 96
    check rendered["score"]["deductions"]["warnings"].getInt() == 4
    check rendered["issues"][0]["rule"].getStr() == "config/missing"
    check rendered["issues"][0]["severity"].getStr() == "warning"
    check rendered["issues"][0]["triage_level"].getStr() == "review"
    check rendered["issues"][0]["suggestion"].getStr() == "Add it."

  test "finding fingerprints survive line shifts and split duplicates":
    var seenBase = initTable[string, int]()
    let first = Issue(
      ruleId: "console-log", severity: severityWarning,
      triage: triageReview, category: "hygiene", file: "a.ts",
      line: 5, message: "console.log call found.", suggestion: "Remove.")
    let firstId = stableFindingId(first, seenBase)
    check firstId.len == 40
    var shifted = first
    shifted.line = 25
    let shiftedId = stableFindingId(shifted, seenBase)
    check shiftedId.split("-")[0] == firstId
    let duplicateId = stableFindingId(first, seenBase)
    check duplicateId != firstId
    check duplicateId.startsWith(firstId & "-")

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
    check "ERROR config/missing\n  src/scour.nim:10:4\n  Missing required config." in output
    check "Suggestion: Add scour.toml." in output
    check "WARNING docs/stale\n  README.md\n  README is stale." in output
    check "Summary\n  Issues: 2\n  Errors: 1\n  Warnings: 1\n  Info: 0\n  Files: 2" in output

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
    check output.startsWith("scour triage found 2 issue(s)\n\nBlockers (1)\n")
    check output.find("Blockers") < output.find("Needs Review")
    check "  Blockers: 1\n" in output
    check "  Needs review: 1\n" in output

  test "renders doctor-style report with score summary and next steps":
    let output = renderDoctorIssues(@[
      Issue(ruleId: "config/missing", severity: severityError,
        triage: triageBlocker, file: "src/scour.nim", line: 10, column: 4,
        message: "Missing required config."),
      Issue(ruleId: "docs/stale", severity: severityWarning,
        triage: triageReview, file: "README.md",
        message: "README is stale.")
    ], colorNever)
    check "Scour Doctor" in output
    check "83 / 100   Mixed" in output
    check "2 issue(s) · 2 file(s) · 1 error(s) · 1 warning(s) · 1 blocker(s)" in output
    check "Top issues\n  ✖ config/missing  ·  blocker  ·  src/scour.nim:10:4" in output
    check "    Missing required config." in output
    check "then re-run `scour --format doctor`." in output
    check "Scour Doctor is clear when the score reaches 100 / 100." in output

  test "renders doctor-style report celebrating a clean scan":
    let output = renderDoctorIssues(@[], colorNever)
    check "Scour Doctor" in output
    check "100 / 100   Perfect" in output
    check "spotless — nice work!" in output
    check "No issues found" in output
    check "you're good to go" in output

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
      "max_file_size = 1024",
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
      "const message = \"console.log('string') debugger; test.only\";",
      "const ok = 1; // debugger; console.log('inline comment');",
      "const directive = '@ts-ignore';",
      "console.error('real but allowed');",
      "const profit = 1;",
      "// @ts-expect-error",
      "const value: string = 1;"
    ].join("\n"))
    let issues = scanBranchHygiene(testPlan(root, @["app.ts"]))
    check issues.len == 0

  test "matches debugger and skipped-test conventions across languages":
    let root = getTempDir() / "scour-multilanguage-rules"
    cleanDir(root)
    createDir(root)
    writeFile(root / "debug.py", "breakpoint()\n")
    writeFile(root / "sample_spec.rb", "fdescribe 'sample' do\n  xit 'later' do\n  end\nend\n")
    writeFile(root / "api_test.py", "@pytest.mark.skip(reason='later')\ndef test_api(): pass\n")
    writeFile(root / "thing_test.go", "func TestThing(t *testing.T) { t.Skip(\"later\") }\n")
    writeFile(root / "service_test.rs", "#[test]\n#[ignore]\nfn service() {}\n")
    writeFile(root / "WidgetTest.java", "@Disabled\nclass WidgetTest {}\n")

    let issues = scanBranchHygiene(testPlan(root, @[
      "debug.py", "sample_spec.rb", "api_test.py", "thing_test.go",
      "service_test.rs", "WidgetTest.java"
    ]))
    check issues.hasIssue("debugger")
    check issues.hasIssue("focused-test")
    check issues.hasIssue("skipped-test")
    check issues.firstIssue("debugger").suggestion.len > 0

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

  test "reports tracked env files but allows redacted and encrypted forms":
    let root = getTempDir() / "scour-tracked-env"
    cleanDir(root)
    createDir(root)
    for file in [".env", ".env.production", ".env.example",
        ".env.local.sample", ".env.encrypted"]:
      writeFile(root / file, "TOKEN=value\n")
    let issues = scanRepoHygiene(testPlan(root, @[
      ".env", ".env.production", ".env.example", ".env.local.sample",
      ".env.encrypted"
    ]))
    check issues.len == 2
    check issues.hasIssue("tracked-env-file")
    check issues.firstIssue("tracked-env-file").suggestion.len > 0

    let cfg = RuntimeConfig(envExampleFiles: @[".env.production"])
    check scanRepoHygiene(testPlan(root, @[".env.production"]), cfg).len == 0

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

  test "ignores environment syntax inside source strings and comments":
    let root = getTempDir() / "scour-env-source-masking"
    cleanDir(root)
    createDir(root)
    writeFile(root / "app.ts", [
      "const example = 'process.env.NOT_A_REAL_VAR';",
      "// process.env.NOT_A_REAL_VAR",
      "const token = process.env.REAL_TOKEN;",
      "const config = process.env['CONFIG_TOKEN'];"
    ].join("\n"))
    let issues = scanCrossReference(testPlan(root, @["app.ts"]))
    check issues.len == 2
    check "REAL_TOKEN" in issues[0].message or "REAL_TOKEN" in issues[1].message
    check "CONFIG_TOKEN" in issues[0].message or "CONFIG_TOKEN" in issues[1].message

  test "finds quoted environment access across supported languages":
    let root = getTempDir() / "scour-env-language-coverage"
    cleanDir(root)
    createDir(root)
    writeFile(root / "app.py", "token = os.getenv('PY_TOKEN')\n")
    writeFile(root / "app.go", "token := os.LookupEnv(\"GO_TOKEN\")\n")
    writeFile(root / "app.rs", "let token = std::env::var(\"RUST_TOKEN\");\n")
    writeFile(root / "App.java", "var token = System.getenv(\"JAVA_TOKEN\");\n")
    writeFile(root / "app.cs", "var token = Environment.GetEnvironmentVariable(\"CS_TOKEN\");\n")
    writeFile(root / "app.rb", "token = ENV['RUBY_TOKEN']\n")
    let issues = scanCrossReference(testPlan(root, @[
      "app.py", "app.go", "app.rs", "App.java", "app.cs", "app.rb"
    ]))
    check issues.len == 6
    for name in ["PY_TOKEN", "GO_TOKEN", "RUST_TOKEN", "JAVA_TOKEN",
        "CS_TOKEN", "RUBY_TOKEN"]:
      check issues.anyIt(name in it.message)

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

  test "does not treat package-manager subcommands as missing scripts":
    let root = getTempDir() / "scour-package-manager-subcommands"
    cleanDir(root)
    createDir(root)
    writeFile(root / "README.md", "```sh\npnpm install --frozen-lockfile\nyarn install\n```\n")
    check scanCrossReference(testPlan(root, @["README.md"])).len == 0

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
      candidates: @["app/package.json"],
      selectedFiles: @["app/package.json"]
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
      candidates: @["with-lock/package.json", "with-lock/package-lock.json"],
      selectedFiles: @["with-lock/package.json", "with-lock/package-lock.json"]
    ))
    check withLockIssues.hasIssue("package-lock-drift") == false

    let noLockIssues = scanCrossReference(ScanPlan(
      mode: scanChanged,
      repo: RepoContext(root: root, isGit: true),
      candidates: @["no-lock/package.json"],
      selectedFiles: @["no-lock/package.json"]
    ))
    check noLockIssues.hasIssue("package-lock-drift") == false

  test "reports lock drift for non-Node dependency ecosystems":
    let root = getTempDir() / "scour-dependency-lock-drift"
    cleanDir(root)
    initGitRepo(root)
    createDir(root / "rust")
    createDir(root / "python")
    writeFile(root / "rust" / "Cargo.toml", "[package]\nname = \"app\"\n")
    writeFile(root / "rust" / "Cargo.lock", "# lock\n")
    writeFile(root / "python" / "pyproject.toml", "[project]\nname = \"app\"\n")
    writeFile(root / "python" / "uv.lock", "version = 1\n")
    check run("git add rust python", root).exitCode == 0
    check run("git commit -m dependencies", root).exitCode == 0
    let issues = scanCrossReference(ScanPlan(
      mode: scanChanged,
      repo: RepoContext(root: root, isGit: true),
      candidates: @["rust/Cargo.toml", "python/pyproject.toml"],
      selectedFiles: @["rust/Cargo.toml", "python/pyproject.toml"]
    ))
    check issues.len == 2
    check issues.hasIssue("dependency-lock-drift")
    check issues.firstIssue("dependency-lock-drift").suggestion.len > 0

  test "reports unpinned third-party actions and allows SHA and local actions":
    let root = getTempDir() / "scour-action-pinning"
    cleanDir(root)
    createDir(root / ".github" / "workflows")
    let workflow = ".github/workflows/ci.yml"
    writeFile(root / workflow, [
      "steps:",
      "  - uses: actions/checkout@v4",
      "  - uses: actions/setup-node@0123456789abcdef0123456789abcdef01234567",
      "  - uses: ./local-action"
    ].join("\n"))
    let issues = scanCrossReference(testPlan(root, @[workflow]))
    check issues.len == 1
    check issues.hasIssue("unpinned-github-action")
    check issues.firstIssue("unpinned-github-action").line == 2

suite "security rules":
  test "finds provider credentials and private keys without echoing values":
    let root = getTempDir() / "scour-hardcoded-secrets"
    cleanDir(root)
    createDir(root)
    let githubToken = "ghp_" & repeat('a', 36)
    let privateKeyStart = "-----BEGIN "
    let privateKeyEnd = "PRIVATE KEY-----"
    let privateKey = privateKeyStart & privateKeyEnd
    writeFile(root / "secrets.txt", githubToken & "\n" & privateKey & "\n")
    let issues = scanSecurity(testPlan(root, @["secrets.txt"]))
    check issues.len == 2
    check issues.hasIssue("hardcoded-secret")
    check githubToken notin issues[0].message
    check issues[0].suggestion.len > 0

  test "ignores placeholders and short token-like strings":
    let root = getTempDir() / "scour-secret-placeholders"
    cleanDir(root)
    createDir(root)
    writeFile(root / "docs.md", "ghp_<credential>\nAKIAEXAMPLE\nsk_live_test\n")
    check scanSecurity(testPlan(root, @["docs.md"])).len == 0

suite "scan planning and files":
  test "selects default modes":
    check resolveScanMode(CliOptions(), RepoContext(root: ".", isGit: true), "staged") == scanStaged
    check resolveScanMode(CliOptions(), RepoContext(root: ".", isGit: true), "full") == scanAll
    check resolveScanMode(CliOptions(), RepoContext(root: ".", isGit: true)) == scanAll
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

  test "skips installed dependency and cache directories by default":
    let root = getTempDir() / "scour-default-ignored-dirs"
    cleanDir(root)
    createDir(root / "src")
    createDir(root / "node_modules" / "package")
    createDir(root / ".venv" / "lib")
    createDir(root / "vendor" / "library")
    writeFile(root / "src" / "app.ts", "console.log('scan me');\n")
    writeFile(root / "node_modules" / "package" / "index.ts", "debugger;\n")
    writeFile(root / ".venv" / "lib" / "app.py", "breakpoint()\n")
    writeFile(root / "vendor" / "library" / "app.go", "panic(\"ignore\")\n")
    let collected = collectCandidates(
      RepoContext(root: root, isGit: false),
      scanAll,
      CliOptions()
    )
    check collected.files == @["src/app.ts"]

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

proc lastJsonLine(output: string): JsonNode =
  let lines = output.splitLines()
  var candidate = ""
  for line in lines:
    if line.startsWith("{"):
      candidate = line
  try:
    result = parseJson(candidate)
  except JsonParsingError:
    result = newJObject()

suite "command behavior":
  test "nonignored manifests preserve ignored and oversized selected lockfile context":
    let binary = fixtureBinary()
    let root = getTempDir() / "scour-filter-lock-context"
    cleanDir(root)
    initGitRepo(root)
    writeFile(root / "package.json", "{}\n")
    writeFile(root / "package-lock.json", "{}\n" & repeat(' ', 100))
    writeFile(root / "Cargo.toml", "[package]\nname = \"app\"\n")
    writeFile(root / "Cargo.lock", "# lock\n" & repeat(' ', 100))
    check run("git add .", root).exitCode == 0
    for gitRepo in [true, false]:
      if not gitRepo:
        removeDir(root / ".git")
      writeFile(root / "scour.toml", "")
      check parseJson(run(binary.quoteShell & " --all --format json", root).output)["issues"].len == 0
      for policy in ["[ignore]\npaths = [\"package-lock.json\", \"Cargo.lock\"]\n",
          "[scan]\nmax_file_size = 50\n"]:
        writeFile(root / "scour.toml", policy)
        var modes = @["--all", "package.json Cargo.toml package-lock.json Cargo.lock"]
        if gitRepo:
          modes.add("--staged")
        for mode in modes:
          let report = run(binary.quoteShell & " --format json " & mode, root)
          check report.exitCode == 0
          check parseJson(report.output)["issues"].len == 0
        let report = run(binary.quoteShell & " --format json package.json Cargo.toml", root)
        check report.exitCode == 0
        let issues = lastJsonLine(report.output)["issues"]
        check issues.len == 2
        check issues[0]["rule"].getStr() == "package-lock-drift"
        check issues[1]["rule"].getStr() == "dependency-lock-drift"
      if gitRepo:
        check run("git commit -m manifests-and-lockfiles", root).exitCode == 0
        let report = run(binary.quoteShell & " --format json --since HEAD~1", root)
        check report.exitCode == 0
        check parseJson(report.output)["issues"].len == 0

  test "nonignored files validate against ignored and oversized context":
    let binary = fixtureBinary()
    let root = getTempDir() / "scour-filter-context"
    initFixtureRepo("clean", root)
    writeFile(root / "package.json",
        "{\"scripts\":{\"test\":\"true\"}}" & repeat(' ', 200))
    writeFile(root / "scour.toml",
        "[scan]\nmax_file_size = 100\n[ignore]\npaths = [\"package.json\", \"package-lock.json\", \".env.example\", \".dockerignore\"]\n")
    for gitRepo in [true, false]:
      if not gitRepo:
        removeDir(root / ".git")
      for mode in ["--all", "app.ts README.md Dockerfile"]:
        let report = run(binary.quoteShell & " --format json " & mode, root)
        check report.exitCode == 0
        check parseJson(report.output)["issues"].len == 0
    writeFile(root / "app.ts", "const token = process.env.UNDOCUMENTED;\n")
    let missing = run(binary.quoteShell & " --format json app.ts", root)
    check missing.exitCode == 1
    let issues = parseJson(missing.output)["issues"]
    check issues.len == 1
    check issues[0]["rule"].getStr() == "env-drift"

  test "repository rules suppress ignored and oversized anchors across scan modes":
    let binary = fixtureBinary()
    let root = getTempDir() / "scour-filter-repository-rules"
    initFixtureRepo("dirty", root)
    writeFile(root / ".env", "TOKEN=value\n")
    writeFile(root / ".github/workflows/ci.yml",
        "jobs:\n  test:\n    steps:\n      - run: npm run missing\n      - uses: actions/checkout@v4\n")
    createDir(root / "rust")
    writeFile(root / "rust/Cargo.toml", "[package]\nname = \"app\"\n")
    writeFile(root / "rust/Cargo.lock", "# lock\n")
    createDir(root / "node")
    writeFile(root / "node/package.json", "{}\n")
    writeFile(root / "node/package-lock.json", "{}\n")
    check run("git add .", root).exitCode == 0
    check run("git commit -m repository-rules", root).exitCode == 0
    writeFile(root / "kept.ts", "debugger;\n")
    let baseline = parseJson(run(binary.quoteShell &
        " --format json app.ts node/package.json rust/Cargo.toml", root).output)["issues"]
    for rule in ["duplicate-lockfiles", "dockerignore-missing", "generated-files",
        "tracked-env-file", "env-drift", "readme-command-drift", "ci-command-drift",
        "unpinned-github-action", "package-lock-drift", "dependency-lock-drift"]:
      check baseline.anyIt(it["rule"].getStr() == rule)
    for policy in ["[ignore]\npaths = [\"app.ts\", \"package.json\", \"node/**\", \"rust/**\", \"Dockerfile\", \"dist/**\", \".env\", \"README.md\", \".github/**\"]\n",
        "[scan]\nmax_file_size = 1\n"]:
      writeFile(root / "scour.toml", policy)
      if "max_file_size" in policy:
        writeFile(root / "kept.ts", "")
      check run("git add kept.ts", root).exitCode == 0
      check run("git commit -m kept", root).exitCode == 0
      writeFile(root / "kept.ts", (if "max_file_size" in policy: " " else: "debugger;\n\n"))
      check run("git add kept.ts", root).exitCode == 0
      for mode in ["--all", "--staged", "--since HEAD~1", "kept.ts"]:
        let report = run(binary.quoteShell & " --format json " & mode, root)
        check report.exitCode == (if "max_file_size" in policy: 0 else: 1)
        let issues = lastJsonLine(report.output)["issues"]
        check issues.len == (if "max_file_size" in policy: 0 else: 1)
        if issues.len == 1:
          check issues[0]["file"].getStr() == "kept.ts"

  test "automatic base scans and explicit staged changed full scans share filters":
    let binary = fixtureBinary()
    for base in ["origin/main", "main", "master"]:
      let root = getTempDir() / ("scour-filter-modes-" & base.replace('/', '-'))
      cleanDir(root)
      initGitRepo(root)
      check run("git branch -m issue-31", root).exitCode == 0
      if base == "origin/main":
        check run("git update-ref refs/remotes/origin/main HEAD", root).exitCode == 0
      else:
        check run("git branch " & base, root).exitCode == 0
      writeFile(root / "ignored.ts", "debugger;\n")
      writeFile(root / "large.ts", "debugger;\n" & repeat(' ', 80))
      writeFile(root / "kept.ts", "debugger;\n")
      writeFile(root / "scour.toml",
          "[scan]\nmax_file_size = 40\n[ignore]\npaths = [\"ignored.ts\"]\n")
      check run("git add .", root).exitCode == 0
      for mode in ["--staged", "--all", "ignored.ts large.ts kept.ts"]:
        let report = run(binary.quoteShell & " --format json " & mode, root)
        check report.exitCode == 1
        let issues = lastJsonLine(report.output)["issues"]
        check issues.len == 1
        check issues[0]["file"].getStr() == "kept.ts"
      check run("git commit -m candidates", root).exitCode == 0
      for mode in ["", "--since " & base]:
        let report = run(binary.quoteShell & " --format json " & mode, root)
        check report.exitCode == 1
        let issues = lastJsonLine(report.output)["issues"]
        check issues.len == 1
        check issues[0]["file"].getStr() == "kept.ts"

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
    checkSnapshot(run(binary.quoteShell & " --all --format doctor --color never",
        dirty), "dirty-doctor.txt", 1)
    check run(binary.quoteShell & " --all --score", dirty).output == "10\n"
    checkSnapshot(run(binary.quoteShell & " --all --format github", dirty),
        "dirty-github.txt", 1)
    check run(binary.quoteShell & " --all --fail-on warning", dirty).exitCode == 1
    check run(binary.quoteShell & " --all --exit-zero", dirty).exitCode == 0
    checkSnapshot(run(binary.quoteShell & " triage --all", dirty),
        "dirty-triage.txt", 1)
    check run(binary.quoteShell & " triage --format json", dirty).exitCode == 2

    writeFile(dirty / "overlay.ts", "console.log('overlay');\n")
    check run("git add overlay.ts", dirty).exitCode == 0
    check "WARNING console-log\n  overlay.ts:1:1" in run(binary.quoteShell &
        " --staged", dirty).output
    check run("git commit -m overlay", dirty).exitCode == 0
    check "WARNING console-log\n  overlay.ts:1:1" in run(binary.quoteShell &
        " --since HEAD~1", dirty).output
    check "ERROR debugger\n  app.ts:2:1" in run(binary.quoteShell & " app.ts",
        dirty).output
    writeFile(dirty / "scour.toml",
        "[rules]\nconsole-log = \"off\"\n")
    check "console-log overlay.ts" notin run(binary.quoteShell &
        " --config scour.toml overlay.ts", dirty).output
    writeFile(dirty / "-dash.ts", "debugger;\n")
    check "ERROR debugger\n  -dash.ts:1:1" in run(binary.quoteShell &
        " -- -dash.ts", dirty).output

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
    check run(binary.quoteShell & " triage --score").exitCode == 2
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
    check run(binary.quoteShell & " --format doctor --all", root).output.contains(
        "Scour Doctor")
    check run(binary.quoteShell & " --all --score", root).output == "100\n"
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
    check "WARNING console-log\n  all.ts:1:1\n  console.log call found." in
        allResult.output

    writeFile(root / "explicit.ts", "debugger;\n")
    let explicitResult = run(binary.quoteShell & " explicit.ts", root)
    check explicitResult.exitCode == 1
    check "ERROR debugger\n  explicit.ts:1:1\n  Debugger statement found." in
        explicitResult.output

    writeFile(root / "staged.ts", "it.only('focused', () => {});\n")
    check run("git add staged.ts", root).exitCode == 0
    let stagedResult = run(binary.quoteShell & " --staged", root)
    check stagedResult.exitCode == 1
    check "ERROR focused-test\n  staged.ts:1:1\n  Focused test left in source." in
        stagedResult.output

    check run("git add all.ts explicit.ts", root).exitCode == 0
    check run("git commit -m hygiene-fixtures", root).exitCode == 0
    writeFile(root / "since.ts", "test.skip('skipped', () => {});\n")
    check run("git add since.ts", root).exitCode == 0
    check run("git commit -m since-fixture", root).exitCode == 0
    let sinceResult = run(binary.quoteShell & " --since HEAD~1", root)
    check sinceResult.exitCode == 1
    check "ERROR skipped-test\n  since.ts:1:1\n  Skipped test left in source." in
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
    check "WARNING duplicate-lockfiles\n  app/package.json\n  Multiple package manager lockfiles found in the same package root." in result.output
    check "WARNING dockerignore-missing\n  Dockerfile\n  Dockerfile has no same-directory .dockerignore." in result.output
    check "WARNING generated-files\n  dist/index.js\n  Generated output is tracked in the repository." in result.output

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
    check "ERROR env-drift\n  app.ts:1:15\n  Environment variable API_TOKEN is used but absent from env example files." in result.output
    check "WARNING readme-command-drift\n  README.md:2:1\n  Command `npm run missing` references a missing script or task target." in result.output
    check "ERROR ci-command-drift\n  .github/workflows/ci.yml:4:14\n  Command `npm run missing` references a missing script or task target." in result.output
    check "WARNING package-lock-drift\n  app/package.json\n  package.json changed without its existing Node lockfile." in result.output

  test "git enumeration preserves separated filenames across scan paths":
    let names =
      when defined(windows):
        @["space name.ts", "uni\u{e9}code.ts", "tab\tname.ts"]
      else:
        @["space name.ts", "back\\slash.ts", "quote'file.ts", "uni\u{e9}code.ts",
            "tab\tname.ts", "new\nline.ts"]
    let root = getTempDir() / "scour-filenames-fixture"
    cleanDir(root)
    initGitRepo(root)
    for name in names:
      writeFile(root / name, "const value = process.env.RENAMED;\n")
    check run("git add -A", root).exitCode == 0
    check run("git commit -m names", root).exitCode == 0

    let context = RepoContext(root: root, isGit: true)
    let options = CliOptions(sinceRef: "HEAD~1")
    for mode in [scanChanged, scanAll]:
      let collected = collectCandidates(context, mode, options)
      for name in names:
        check collected.files.count(name) == 1

    for name in names:
      writeFile(root / name, "const value = process.env.UNDOCUMENTED;\n")
    check run("git add -A", root).exitCode == 0
    let staged = collectCandidates(context, scanStaged, options)
    for name in names:
      check staged.files.count(name) == 1

    let binary = fixtureBinary()
    let report = run(binary.quoteShell & " --all --format json", root)
    check report.exitCode == 1
    let issues = lastJsonLine(report.output)["issues"]
    for name in names:
      check issues.toSeq().countIt(it["file"].getStr() == name) == 1

  test "default scan is the full tracked checkout for default-branch pushes":
    let binary = fixtureBinary()
    let root = getTempDir() / "scour-default-full"
    cleanDir(root)
    initGitRepo(root)
    writeFile(root / "app.ts", "const value = process.env.UNDOCUMENTED;\n")
    let report = run(binary.quoteShell & " --format json", root)
    check report.exitCode == 1
    let rendered = parseJson(report.output)
    check rendered["scan"]["mode"].getStr() == "all"
    check rendered["scan"]["base"].getStr() == ""
    check rendered["scan"]["scanned_files"].getInt() == 2
    check rendered["issues"].toSeq().countIt(it["rule"].getStr() == "env-drift") == 1

  test "explicit comparisons use merge-base semantics across alternate branches":
    let binary = fixtureBinary()
    let root = getTempDir() / "scour-merge-base"
    cleanDir(root)
    initGitRepo(root)
    writeFile(root / "kept.txt", "stable\n")
    check run("git add kept.txt", root).exitCode == 0
    check run("git commit -m base", root).exitCode == 0
    check run("git branch release", root).exitCode == 0
    writeFile(root / "main-side.ts", "const value = process.env.UNDOCUMENTED;\n")
    writeFile(root / "kept.txt", "changed on main\n")
    check run("git add -A", root).exitCode == 0
    check run("git commit -m main-side", root).exitCode == 0
    let report = run(binary.quoteShell & " --format json --since release", root)
    check report.exitCode == 1
    let rendered = parseJson(report.output)
    check rendered["scan"]["mode"].getStr() == "changed"
    check rendered["scan"]["base"].getStr() == "release"
    check rendered["scan"]["head"].getStr() == "HEAD"
    let scanned = rendered["scan"]["scanned_files"].getInt()
    check scanned == 2
    check rendered["issues"].toSeq().countIt(
        it["file"].getStr() == "main-side.ts") == 1

  test "missing comparison refs fail with actionable errors instead of scope changes":
    let root = getTempDir() / "scour-missing-ref"
    cleanDir(root)
    initGitRepo(root)
    writeFile(root / "app.ts", "const value = process.env.UNDOCUMENTED;\n")
    let context = RepoContext(root: root, isGit: true)
    expectFatal:
      discard collectCandidates(context, scanChanged, CliOptions())

    let binary = fixtureBinary()
    let report = run(binary.quoteShell & " --since does-not-exist", root)
    check report.exitCode == 2
    check "merge-base semantics" in report.output

  test "empty diffs scan zero files and succeed":
    let binary = fixtureBinary()
    let root = getTempDir() / "scour-empty-diff"
    cleanDir(root)
    initGitRepo(root)
    let report = run(binary.quoteShell & " --format json --since HEAD", root)
    check report.exitCode == 0
    let rendered = parseJson(report.output)
    check rendered["scan"]["scanned_files"].getInt() == 0
    check rendered["issues"].len == 0

  test "renames scan targets once and deletions scan nothing":
    let root = getTempDir() / "scour-rename-filter"
    cleanDir(root)
    initGitRepo(root)
    writeFile(root / "old.ts", "const value = 1;\n")
    check run("git add old.ts", root).exitCode == 0
    check run("git commit -m original", root).exitCode == 0
    check run("git mv old.ts \"moved target.ts\"", root).exitCode == 0
    check run("git rm --cached tracked.txt", root).exitCode == 0
    let context = RepoContext(root: root, isGit: true)
    let staged = collectCandidates(context, scanStaged, CliOptions())
    check staged.files == @["moved target.ts"]
    check staged.baseRef == ""
    check "old.ts" notin staged.files
    check "tracked.txt" notin staged.files

  test "detached heads and shallow clones keep deterministic scope":
    let binary = fixtureBinary()
    let root = getTempDir() / "scour-detached-shallow"
    cleanDir(root)
    initGitRepo(root)
    check run("git checkout --detach", root).exitCode == 0
    writeFile(root / "app.ts", "const value = process.env.UNDOCUMENTED;\n")
    let report = run(binary.quoteShell & " --format json", root)
    check report.exitCode == 1
    let rendered = parseJson(report.output)
    check rendered["scan"]["mode"].getStr() == "all"
    check rendered["issues"].toSeq().countIt(
        it["file"].getStr() == "app.ts") == 1

    let shallow = getTempDir() / "scour-shallow"
    cleanDir(shallow)
    check run("git clone -q --depth 1 --no-local " & root.quoteShell & " " &
        shallow.quoteShell).exitCode == 0
    let shallowReport = run(binary.quoteShell & " --format json --since HEAD", shallow)
    check shallowReport.exitCode == 0
    check parseJson(shallowReport.output)["scan"]["scanned_files"].getInt() == 0
    let missing = run(binary.quoteShell & " --since c3fa8041", shallow)
    check missing.exitCode == 2
    check "merge-base semantics" in missing.output

  test "configuration parse preserves quoted comments and escapes":
    let fileLines = @[
      "[ignore]",
      "paths = [",
      "  \"hash#tag/**\",  # covered sections",
      "  \"comma,dir/**\",",
      "  'literal\\backslash',",
      "  \"decode\\\"quote\",",
      "  \"move\\\\together\",",
      "]",
    ]
    let path = getTempDir() / "scour-config-quote.toml"
    writeFile(path, fileLines.join("\n"))
    let config = loadConfig(ConfigDiscovery(path: path, isExplicit: true))
    check config.ignorePaths == @[
      "hash#tag/**", "comma,dir/**",
      "literal" & "\\" & "backslash",
      "decode" & "\"" & "quote",
      "move" & "\\" & "together"
    ]

  test "invalid configuration values fail on duplicate keys and wrong types":
    for text in [
      "[scan]\nmax_file_size = 100\nmax_file_size = 200\n",
      "[scan]\nmax_file_size = \"150\"\n",
      "[scan]\nmode = \"changed\"\n",
      "[scan]\nmax_file_size = 99999999999999999999\n",
      "[ignore]\npaths = [\"x\", 5]\n",
      "[scan]\nrespect_gitignore = \"yes\"\n"
    ]:
      let path = getTempDir() / "scour-config-invalid.toml"
      writeFile(path, text)
      expectFatal:
        discard loadConfig(ConfigDiscovery(path: path, isExplicit: true))

  test "invalid configuration files exit 2 from the CLI":
    let binary = fixtureBinary()
    let root = getTempDir() / "scour-config-exit"
    cleanDir(root)
    initGitRepo(root)
    writeFile(root / "scour.toml", "[scan]\nmode = \"changed\"\n")
    let report = run(binary.quoteShell & " --format json", root)
    check report.exitCode == 2
    check "expected full or staged" in report.output

  test "respect_gitignore excludes ignored untracked files while kept body rules see tracked files":
    let binary = fixtureBinary()
    let root = getTempDir() / "scour-gitignore-mode"
    cleanDir(root)
    initGitRepo(root)
    createDir(root / "dist")
    writeFile(root / "dist" / "generated.js", "build()\n")
    check run("git add dist", root).exitCode == 0
    check run("git commit -m tracked", root).exitCode == 0
    writeFile(root / "ignored.log", "noise\n")
    writeFile(root / ".gitignore", "ignored.log\n")

    let context = RepoContext(root: root, isGit: true)
    let unfiltered = collectCandidates(context, scanAll, CliOptions())
    check unfiltered.files.count("ignored.log") == 1
    let config = RuntimeConfig(ignorePaths: @[], respectGitignore: true)
    let filtered = collectCandidates(context, scanAll, CliOptions(), config)
    check filtered.files.count("ignored.log") == 0
    check filtered.files.count("dist/generated.js") == 1

    writeFile(root / "scour.toml", "[scan]\nrespect_gitignore = true\n")
    let report = run(binary.quoteShell & " --format json", root)
    check report.exitCode == 0
    check "generated-files" in report.output
    check parseJson(report.output)["scan"]["mode"].getStr() == "all"

  test "config mode staged and follow_symlinks change behavior with CLI precedence":
    let binary = fixtureBinary()
    let root = getTempDir() / "scour-config-precedence"
    cleanDir(root)
    initGitRepo(root)
    writeFile(root / "one.ts", "const one = 1;\n")
    writeFile(root / "two.ts", "const two = 2;\n")
    check run("git add one.ts", root).exitCode == 0
    check run("git add two.ts", root).exitCode == 0
    createDir(root / "outside")
    writeFile(root / "outside" / "lead.ts", "const lead = 3;\n")
    writeFile(root / "one.ts", "const one = 1;\n")
    writeFile(root / "two.ts", "const two = 2;\n")
    check run("git add .", root).exitCode == 0
    check run("git commit -m added", root).exitCode == 0
    writeFile(root / "staged.ts", "const staged = 1;\n")
    check run("git add staged.ts", root).exitCode == 0
    check run("ln -s outside/lead.ts followed.ts", root).exitCode == 0
    writeFile(root / "scour.toml", "[scan]\nmode = \"staged\"\n")

    let staged = run(binary.quoteShell & " --format json", root)
    check parseJson(staged.output)["scan"]["scanned_files"].getInt() == 1
    let cliWins = run(binary.quoteShell & " --all --format json", root)
    let cliCount = parseJson(cliWins.output)["scan"]["scanned_files"].getInt()
    check parseJson(cliWins.output)["scan"]["mode"].getStr() == "all"

    let context = RepoContext(root: root, isGit: true)
    let withoutFollow = collectCandidates(context, scanAll, CliOptions())
    check withoutFollow.files.count("followed.ts") == 0
    let config = RuntimeConfig(ignorePaths: @[], followSymlinks: true)
    let withFollow = collectCandidates(context, scanAll, CliOptions(), config)
    check withFollow.files.count("followed.ts") == 1
    check withFollow.files.len == withoutFollow.files.len + 1

  test "staged scans read the selected index snapshot":
    let binary = fixtureBinary()
    let root = getTempDir() / "scour-staged-snapshot"
    cleanDir(root)
    initGitRepo(root)
    writeFile(root / "app.ts", "const clean = 1;\n")
    check run("git add app.ts", root).exitCode == 0
    check run("git commit -m clean", root).exitCode == 0

    check run("git mv app.ts moved.ts", root).exitCode == 0
    writeFile(root / "moved.ts", "const value = process.env.STAGED_ENV;\n")
    check run("git add moved.ts", root).exitCode == 0

    let candidates = collectCandidates(RepoContext(root: root, isGit: true),
        scanStaged, CliOptions())
    check candidates.files == @["moved.ts"]

    let dirty = run(binary.quoteShell & " --staged --format json", root)
    check parseJson(dirty.output)["issues"].toSeq().countIt(
        it["rule"].getStr() == "env-drift") == 1

  test "staged scans ignore unstaged worktree edits for the same finding":
    let binary = fixtureBinary()
    let root = getTempDir() / "scour-staged-worktree-split"
    cleanDir(root)
    initGitRepo(root)
    writeFile(root / "app.ts", "const first = 1;\n")
    check run("git add app.ts", root).exitCode == 0
    check run("git commit -m clean", root).exitCode == 0

    writeFile(root / "app.ts", "const second = 2;\n")
    check run("git add app.ts", root).exitCode == 0
    writeFile(root / "app.ts",
        "const second = 2;\nconst value = process.env.UNDOCUMENTED;\n")
    let report = run(binary.quoteShell & " --staged --format json", root)
    check report.exitCode == 0
    check parseJson(report.output)["issues"].len == 0

  test "index-only files and deletions preserve the selected snapshot":
    let binary = fixtureBinary()
    let root = getTempDir() / "scour-staged-deletion"
    cleanDir(root)
    initGitRepo(root)
    writeFile(root / "package.json", "{}\n")
    writeFile(root / "README.md", "```sh\nnpm run missing\n```\n")
    check run("git add .", root).exitCode == 0
    check run("git commit -m manifest", root).exitCode == 0

    writeFile(root / "index-only.ts", "const only = 1;\n")
    check run("git add index-only.ts", root).exitCode == 0
    check run("rm -rf index-only.ts", root).exitCode == 0
    let report = run(binary.quoteShell & " --staged --format json", root)
    check report.exitCode == 0
    check parseJson(report.output)["scan"]["scanned_files"].getInt() == 1

  test "boundary failures are tracked and cannot scan clean":
    let binary = fixtureBinary()
    let root = getTempDir() / "scour-boundary"
    cleanDir(root)
    initGitRepo(root)
    writeFile(root / "outside-target.ts", "const outside = 1;\n")
    check run("git add .", root).exitCode == 0
    check run("git commit -m base", root).exitCode == 0
    writeFile(root / "plain.ts", "const plain = 1;\n")
    check run("rm -f dangling.ts && ln -s missing.ts dangling.ts", root).exitCode == 0
    check run("ln -s loop.ts loop.ts", root).exitCode == 0
    writeFile(root / "sealed.ts", "const sealed = 1;\n")
    check run("chmod 000 sealed.ts", root).exitCode == 0

    let context = RepoContext(root: root, isGit: true)
    let stats = new ScanStats
    let collected = collectCandidates(context, scanAll, CliOptions(), defaultConfig(), stats)
    check collected.files.count("plain.ts") == 1
    check collected.files.count("sealed.ts") == 0
    check collected.files.count("dangling.ts") == 0
    check collected.files.count("loop.ts") == 0
    check stats.unreadable == 1

    let outside = getTempDir() / "outside-scour-boundary.ts"
    let explicitStats = new ScanStats
    let outsideCollected = collectCandidates(context, scanExplicitPaths,
        CliOptions(explicitPaths: @[outside]), defaultConfig(), explicitStats)
    check outsideCollected.files.len == 0
    check explicitStats.missing == 1

    let report = run(binary.quoteShell & " --all --format json", root)
    check report.exitCode == 1
    check lastJsonLine(report.output)["summary"]["total"].getInt() == 0
    check parseJson(report.output)["scan"]["skipped"]["unreadable"].getInt() == 1
    check parseJson(report.output)["scan"]["complete"].getBool() == false

  test "machine report validates against the published schema":
    let schema = parseJson(readFile("report-schema-v1.json"))
    check schema["properties"]["report_version"]["const"].getInt() == 1
    check schema["type"].getStr() == "object"
    for key in schema["required"]:
      check key.getStr() in ["report_version", "tool", "summary", "scan",
          "score", "issues"]

    let plan = testPlan("", @[])
    let cleanReport = parseJson(renderJsonIssues(@[], plan))
    proc schemaValidate(node: JsonNode; schema: JsonNode): bool =
      case schema{"type"}.getStr()
      of "object":
        if schema.hasKey("required"):
          for key in schema["required"]:
            if not node.hasKey(key.getStr()):
              return false
        if schema.hasKey("properties"):
          for key, spec in schema["properties"]:
            if node.hasKey(key):
              if not schemaValidate(node[key], spec):
                return false
        true
      of "array":
        for item in node:
          if not schemaValidate(item, schema["items"]):
            return false
        true
      of "string": node.kind == JString
      of "integer": node.kind == JInt
      of "boolean": node.kind == JBool
      else: true

    check schemaValidate(cleanReport, schema)
    let issueReport = parseJson(renderJsonIssues(@[Issue(
      ruleId: "config/missing", severity: severityWarning,
      triage: triageReview, category: "config", file: "a.nim",
      line: 2, column: 3, message: "Missing.", suggestion: "Add it."
    )], plan))
    check schemaValidate(issueReport, schema)
    let fixtures = @["tests/snapshots/dirty-json.txt"]
    for fixture in fixtures:
      check schemaValidate(parseJson(readFile(fixture)), schema)

  test "large trees stay inside recorded runtime and memory limits":
    let root = getTempDir() / "scour-large-tree"
    cleanDir(root)
    for directoryIndex in 0 ..< 20:
      let directory = root / ("dir" & $directoryIndex)
      createDir(directory)
      for fileIndex in 0 ..< 100:
        writeFile(directory / ("file" & $fileIndex & ".ts"),
            "const value = " & $fileIndex & ";\n")

    let started = epochTime()
    let stats = new ScanStats
    let collected = collectCandidates(RepoContext(root: root, isGit: false),
        scanAll, CliOptions(), defaultConfig(), stats)
    let elapsed = epochTime() - started
    check collected.files.len == 2000
    check elapsed < 30.0
    when defined(posix):
      var usage: Rusage
      discard getrusage(RUSAGE_SELF, addr usage)
      when defined(macosx):
        check usage.ruMaxrss < 1_000_000_000
      else:
        check usage.ruMaxrss < 1_000_000

  test "workspaces keep command scripts and env contracts isolated":
    let binary = fixtureBinary()
    let root = getTempDir() / "scour-workspaces"
    cleanDir(root)
    initGitRepo(root)
    createDir(root / "app")
    createDir(root / "lib")
    writeFile(root / "app" / "package.json", "{\"scripts\":{\"apprun\":\"true\"}}\n")
    writeFile(root / "lib" / "package.json", "{\"scripts\":{\"librun\":\"true\"}}\n")
    writeFile(root / "README.md", "```sh\nnpm run librun\n```\n")
    writeFile(root / "app" / ".env.example", "APP_ONLY=1\n")
    writeFile(root / "app" / "app.ts", "const value = process.env.APP_ONLY;\n")
    writeFile(root / "lib" / "lib.ts", "const value = process.env.LIB_ONLY;\n")
    check run("git add -A", root).exitCode == 0
    check run("git commit -m workspaces", root).exitCode == 0

    let report = run(binary.quoteShell & " --all --format json", root)
    let issues = lastJsonLine(report.output)["issues"]
    check issues.toSeq().countIt(it["rule"].getStr() == "readme-command-drift") == 1
    check issues.toSeq().countIt(it["rule"].getStr() == "env-drift") == 1

    writeFile(root / "scour.toml", "[scan]\nshared_root = true\n")
    let shared = run(binary.quoteShell & " --all --format json", root)
    check parseJson(shared.output)["issues"].toSeq().countIt(
        it["rule"].getStr() == "readme-command-drift") == 0
    check parseJson(shared.output)["issues"].toSeq().countIt(
        it["rule"].getStr() == "env-drift") == 1

  test "workflow working-directory resolves against the owning package":
    let binary = fixtureBinary()
    let root = getTempDir() / "scour-workspace-wd"
    cleanDir(root)
    initGitRepo(root)
    createDir(root / "app")
    createDir(root / ".github" / "workflows")
    writeFile(root / "app" / "package.json", "{\"scripts\":{\"apprun\":\"true\"}}\n")
    writeFile(root / ".github" / "workflows" / "ci.yml", """jobs:
  build:
    steps:
      - run: |
          npm run apprun
          npm run missingrun
        working-directory: app
      - run: 'npm run missingroot'
""")
    check run("git add .", root).exitCode == 0
    check run("git commit -m workflows", root).exitCode == 0
    let report = run(binary.quoteShell & " --all --format json", root)
    let issues = lastJsonLine(report.output)["issues"]
    let drifts = issues.toSeq().filterIt(it["rule"].getStr() == "ci-command-drift")
    check drifts.len == 1
    check drifts[0]["file"].getStr() == ".github/workflows/ci.yml"

  test "gitlab script blocks parse quoting and cd context":
    let binary = fixtureBinary()
    let root = getTempDir() / "scour-gitlab-script"
    cleanDir(root)
    initGitRepo(root)
    createDir(root / "app")
    writeFile(root / "app" / "package.json", "{\"scripts\":{\"apprun\":\"true\"}}\n")
    writeFile(root / ".gitlab-ci.yml", """build job:
  before_script:
    - "cd app && npm run apprun"
  script:
    - npm run apprun
    - npm run missingrun
""")
    check run("git add .", root).exitCode == 0
    check run("git commit -m gitlab", root).exitCode == 0
    let report = run(binary.quoteShell & " --all --format json", root)
    let issues = lastJsonLine(report.output)["issues"]
    check issues.toSeq().countIt(
        it["rule"].getStr() == "ci-command-drift") == 2

  test "dynamic commands stay unsupported rather than confidently broken":
    let binary = fixtureBinary()
    let root = getTempDir() / "scour-dynamic-commands"
    cleanDir(root)
    initGitRepo(root)
    createDir(root / ".github" / "workflows")
    writeFile(root / "package.json", "{\"scripts\":{\"known\":\"true\"}}\n")
    writeFile(root / ".github" / "workflows" / "dynamic.yml", """jobs:
  build:
    steps:
      - run: |
          npm run $SCRIPT_NAME
          npm run $(echo known)
""")
    check run("git add .", root).exitCode == 0
    check run("git commit -m dynamic", root).exitCode == 0
    let report = run(binary.quoteShell & " --all --format json", root)
    check parseJson(report.output)["issues"].toSeq().countIt(
        it["rule"].getStr() == "ci-command-drift") == 0

  test "fix planning writes a patch without touching files":
    let binary = fixtureBinary()
    let root = getTempDir() / "scour-fix-preview"
    cleanDir(root)
    createDir(root)
    createDir(root)
    writeFile(root / "app.ts", "const start = 1;\nconsole.log(\"debug\");\nconst end = 2;\ndebugger;\n")
    let before = readFile(root / "app.ts")
    let report = run(binary.quoteShell & " --all --fix --format json", root)
    check report.exitCode == 0
    check "Planned 2 fix findings across 1 file" in report.output
    check readFile(root / "app.ts") == before
    check fileExists(root / "scour-fix.patch")
    let patch = readFile(root / "scour-fix.patch")
    check "-console.log(\"debug\");" in patch
    check "-debugger;" in patch
    check "+++ b/app.ts" in patch

  test "fix application is atomic, preserves modes, and is idempotent":
    let binary = fixtureBinary()
    let root = getTempDir() / "scour-fix-apply"
    cleanDir(root)
    createDir(root)
    writeFile(root / "app.ts", "const start = 1;\nconsole.log(\"debug\");\nconst end = 2;\n")
    writeFile(root / "other.ts", "debugger;\nlet x = 3;\n")
    check run("chmod 600 other.ts", root).exitCode == 0
    let first = run(binary.quoteShell & " --all --fix-apply --format json", root)
    check first.exitCode == 0
    check readFile(root / "app.ts") == "const start = 1;\nconst end = 2;\n"
    check readFile(root / "other.ts") == "let x = 3;\n"
    when defined(posix):
      let permissions = getFilePermissions(root / "other.ts")
      check permissions.contains(fpUserWrite)
      check not permissions.contains(fpGroupWrite)

    let second = run(binary.quoteShell & " --all --fix-apply --format json", root)
    check second.exitCode == 0
    check readFile(root / "app.ts") == "const start = 1;\nconst end = 2;\n"
    check readFile(root / "other.ts") == "let x = 3;\n"

  test "stale content stops apply with a controlled refusal":
    let root = getTempDir() / "scour-fix-stale"
    cleanDir(root)
    createDir(root)
    writeFile(root / "fixed.ts", "console.log(\"debug\");\n")
    let planned = planFixes(@[Issue(ruleId: "console-log", severity: severityWarning,
        triage: triageReview, category: "hygiene", file: "fixed.ts",
        line: 1, message: "console.log call found.", suggestion: "Remove.")],
        root)
    check planned.len == 1
    check planned[0].contentSha.len == 40
    writeFile(root / "fixed.ts", "console.log(\"debug\");\nconst moved = 1;\n")
    let applied = applyFixPlan(planned, root)
    check applied.stale.len == 1
    check applied.applied.len == 0
    check readFile(root / "fixed.ts").contains("console.log")

  test "post-fix exit follows remaining and unfixable findings":
    let binary = fixtureBinary()
    let root = getTempDir() / "scour-fix-post-exit"
    cleanDir(root)
    createDir(root)
    writeFile(root / "mixed.ts", "<<<<<<< HEAD\ndebugger;\n>>>>>>> branch\n")
    let report = run(binary.quoteShell & " --all --fix-apply --format json", root)
    check report.exitCode == 1
    check "remaining: " in report.output
    check "unfixable: " in report.output
    check not readFile(root / "mixed.ts").contains("debugger")
    check readFile(root / "mixed.ts").contains("<<<<<<< HEAD")

  test "unwritable targets stop apply with exit code 2":
    let binary = fixtureBinary()
    let root = getTempDir() / "scour-fix-unwritable"
    cleanDir(root)
    createDir(root)
    writeFile(root / "locked.ts", "console.log(\"debug\");\n")
    when defined(posix):
      check run("chmod 500 .", root).exitCode == 0
    let report = run(binary.quoteShell & " --all --fix-apply --format json", root)
    when defined(posix):
      check report.exitCode == 2
      check "Fatal" in report.output
      check run("chmod 700 .", root).exitCode == 0

  test "missing dockerignore is created once from configured entries":
    let binary = fixtureBinary()
    let root = getTempDir() / "scour-fix-dockerignore"
    cleanDir(root)
    createDir(root)
    writeFile(root / "Dockerfile", "FROM scratch\n")
    writeFile(root / "scour.toml", "[scan]\ndockerignore_entries = [\"custom/\", \"logs/\"]\n")
    let report = run(binary.quoteShell & " --all --fix-apply --format json", root)
    check report.exitCode == 0
    check fileExists(root / ".dockerignore")
    check readFile(root / ".dockerignore") == "custom/\nlogs/\n"
    check lastJsonLine(report.output)["summary"]["total"].getInt() == 0
    let again = run(binary.quoteShell & " --all --fix --format json", root)
    check again.exitCode == 0
    check "Planned 0" in again.output
    check readFile(root / ".dockerignore") == "custom/\nlogs/\n"

  test "existing dockerignore is preserved and clean fixtures produce no patch":
    let binary = fixtureBinary()
    let root = getTempDir() / "scour-fix-dockerignore-kept"
    cleanDir(root)
    createDir(root)
    writeFile(root / "Dockerfile", "FROM scratch\n")
    writeFile(root / ".dockerignore", "node_modules\n")
    let report = run(binary.quoteShell & " --all --fix-apply --format json", root)
    check report.exitCode == 0
    check readFile(root / ".dockerignore") == "node_modules\n"
    check lastJsonLine(report.output)["summary"]["total"].getInt() == 0
    check not fileExists(root / "scour-fix.patch")

  test "pinned action replaces tags with mapped shas and preserves YAML":
    let binary = fixtureBinary()
    let root = getTempDir() / "scour-fix-pin"
    cleanDir(root)
    createDir(root)
    createDir(root / ".github" / "workflows")
    writeFile(root / ".github" / "workflows" / "ci.yml", """name: CI
jobs:
  build:
    steps:
      - uses: actions/checkout@v4
""")
    writeFile(root / "scour.toml", "[fix.pin_action]\n\"actions/checkout\" = \"" &
        repeat('f', 40) & "\"\n")
    let report = run(binary.quoteShell & " --all --fix-apply --format json", root)
    check report.exitCode == 0
    let content = readFile(root / ".github" / "workflows" / "ci.yml")
    check content.contains("actions/checkout@" & repeat('f', 40) & " # v4")
    check lastJsonLine(report.output)["summary"]["total"].getInt() == 0
    let again = run(binary.quoteShell & " --all --fix --format json", root)
    check "Planned 0" in again.output

  test "unmapped selectors and unfixable findings stay manual":
    let binary = fixtureBinary()
    let root = getTempDir() / "scour-fix-unmapped"
    cleanDir(root)
    createDir(root)
    createDir(root / ".github" / "workflows")
    writeFile(root / ".github" / "workflows" / "ci.yml", """jobs:
  build:
    steps:
      - uses: actions/setup-node@v4
""")
    writeFile(root / "scour.toml", "[fix.pin_action]\n\"actions/checkout\" = \"" &
        repeat('f', 40) & "\"\n")
    let report = run(binary.quoteShell & " --all --fix-apply --format json", root)
    check report.exitCode == 1
    let issues = lastJsonLine(report.output)["issues"]
    check issues.toSeq().countIt(
        it["rule"].getStr() == "unpinned-github-action") == 1
    check issues[0]["fixable"].getBool() == true
  test "invalid pin sha exits two":
    let binary = fixtureBinary()
    let root = getTempDir() / "scour-fix-badpin"
    cleanDir(root)
    createDir(root)
    writeFile(root / "scour.toml", "[fix.pin_action]\n\"actions/checkout\" = \"0123\"\n")
    let report = run(binary.quoteShell & " --all --format json", root)
    check report.exitCode == 2
    check "40-character SHA-1" in report.output

suite "codequality and sarif serializers":
  test "codequality output maps severities and stable fingerprints":
    let plan = testPlan("", @[])
    let rendered = parseJson(renderCodequalityIssues(@[
      Issue(ruleId: "debugger", severity: severityError,
          triage: triageFixNow, category: "hygiene", file: "src/a.ts",
          line: 3, message: "Debugger statement found.", suggestion: "Remove."),
      Issue(ruleId: "console-log", severity: severityWarning,
          triage: triageReview, category: "hygiene", file: "src/a.ts",
          line: 9, message: "console.log call found.", suggestion: "Remove.")
    ], plan))
    check rendered.len == 2
    check rendered[0]["severity"].getStr() == "major"
    check rendered[1]["severity"].getStr() == "minor"
    check rendered[0]["check_name"].getStr() == "debugger"
    check rendered[0]["fingerprint"].getStr().len == 40
    check rendered[0]["location"]["path"].getStr() == "src/a.ts"
    check rendered[0]["location"]["lines"]["begin"].getInt() == 3
    let shifted = parseJson(renderCodequalityIssues(@[
      Issue(ruleId: "debugger", severity: severityError,
          triage: triageFixNow, category: "hygiene", file: "src/a.ts",
          line: 30, message: "Debugger statement found.", suggestion: "Remove."),
      Issue(ruleId: "console-log", severity: severityWarning,
          triage: triageReview, category: "hygiene", file: "src/a.ts",
          line: 90, message: "console.log call found.", suggestion: "Remove.")
    ], plan))
    check shifted[0]["fingerprint"].getStr() == rendered[0]["fingerprint"].getStr()

  test "sarif output groups rules and maps levels":
    let plan = testPlan("", @[])
    let rendered = parseJson(renderSarifIssues(@[
      Issue(ruleId: "debugger", severity: severityError,
          triage: triageFixNow, category: "hygiene", file: "src\\dir\\b.ts",
          line: 3, column: 2, message: "Debugger statement found.",
          suggestion: "Remove."),
      Issue(ruleId: "console-log", severity: severityWarning,
          triage: triageReview, category: "hygiene", file: "b.ts",
          message: "console.log call found.", suggestion: "Remove.")
    ], plan))
    check rendered["version"].getStr() == "2.1.0"
    check rendered["runs"].len == 1
    check rendered["runs"][0]["tool"]["driver"]["name"].getStr() == "scour"
    let rules = rendered["runs"][0]["tool"]["driver"]["rules"]
    check rules.len == 2
    check rules[0]["id"].getStr() == "debugger"
    check rules[0]["properties"]["category"].getStr() == "hygiene"
    let resultsa = rendered["runs"][0]["results"]
    check resultsa.len == 2
    check resultsa[0]["level"].getStr() == "error"
    check resultsa[1]["level"].getStr() == "warning"
    check resultsa[0]["locations"][0]["physicalLocation"]["artifactLocation"]["uri"].getStr() == "src/dir/b.ts"
    check resultsa[0]["locations"][0]["physicalLocation"]["region"]["startLine"].getInt() == 3
    check resultsa[1]["fingerprints"]["scour/finding-id/v1"].getStr().len == 40
    check resultsa[1]["locations"].len == 1

  test "clean scans render empty arrays in both formats":
    let plan = testPlan("", @[])
    check renderCodequalityIssues(@[], plan) == "[]\n"
    let sarif = parseJson(renderSarifIssues(@[], plan))
    check sarif["runs"][0]["results"].len == 0
    check sarif["runs"][0]["tool"]["driver"]["rules"].len == 0

suite "rule precision across languages":
  test "python test file names match the test_ prefix":
    check "test_api.py".isTestPath()
    check "api_test.py".isTestPath()
    check "tests/test_ok.py".isTestPath()
    check "contest.rb".isTestPath() == false
    check "tests".isTestPath()
    check "sample_spec.rb".isTestPath()
  test "token boundaries stop prefix false positives":
    let root = getTempDir() / "scour-precision-boundaries"
    cleanDir(root)
    createDir(root)
    writeFile(root / "vigil.ts", "let latest = 1; mydebugger = 2;\n")
    writeFile(root / "cudgel.py", "x = breakpoint_impl(a)\n")
    let plan = ScanPlan(
      mode: scanExplicitPaths,
      repo: RepoContext(root: root, isGit: false),
      candidates: @["vigil.ts", "cudgel.py"],
      selectedFiles: @["vigil.ts", "cudgel.py"],
      stats: new ScanStats
    )
    let issues = scanBranchHygiene(plan)
    check issues.hasIssue("debugger") == false

  test "comment masking keeps documented examples out of results":
    let root = getTempDir() / "scour-precision-masked"
    cleanDir(root)
    createDir(root)
    writeFile(root / "seen.ts", "const note = \"use debugger inside a string\";\n")
    let masked = scanBranchHygiene(ScanPlan(
      mode: scanExplicitPaths,
      repo: RepoContext(root: root, isGit: false),
      candidates: @["seen.ts"],
      selectedFiles: @["seen.ts"],
      stats: new ScanStats
    ))
    check masked.hasIssue("debugger") == false

suite "baseline and suppressions":
  test "baseline writes fingerprints and gates only new findings":
    let binary = fixtureBinary()
    let root = getTempDir() / "scour-baseline"
    cleanDir(root)
    createDir(root)
    writeFile(root / "app.ts", "debugger;\nconsole.log('dbg');\n")
    let writeRun = run(binary.quoteShell & " --all --write-baseline baseline.json --format json", root)
    check writeRun.exitCode == 0
    check "Baseline written to baseline.json" in writeRun.output
    check fileExists(root / "baseline.json")
    let parsed = parseJson(readFile(root / "baseline.json"))
    check parsed["version"].getInt() == 1
    check parsed["findings"].kind == JArray

    let gated = run(binary.quoteShell &
        " --all --baseline baseline.json --format json", root)
    check gated.exitCode == 0
    check lastJsonLine(gated.output)["summary"]["total"].getInt() == 0

    writeFile(root / "new.ts", "debugger;\n")
    let stillEclusive = run(binary.quoteShell &
        " --all --baseline baseline.json --format json", root)
    check stillEclusive.exitCode == 1
    check lastJsonLine(stillEclusive.output)["summary"]["total"].getInt() == 1

  test "malformed baseline or incomplete scans fail with exit two":
    let binary = fixtureBinary()
    let root = getTempDir() / "scour-baseline-errors"
    cleanDir(root)
    createDir(root)
    writeFile(root / "app.ts", "debugger;\n")
    writeFile(root / "baseline.json", "not json")
    let broken = run(binary.quoteShell &
        " --all --baseline baseline.json --format json", root)
    check broken.exitCode == 2
    check "not valid JSON" in broken.output

    when defined(posix):
      writeFile(root / "sealed.ts", "debugger;\n")
      check run("chmod 000 sealed.ts", root).exitCode == 0
      let refuse = run(binary.quoteShell &
          " --all --write-baseline baseline.json --format json", root)
      check refuse.exitCode == 2
      check "incomplete baseline" in refuse.output

  test "suppressions with expiry gate findings until they expire":
    let binary = fixtureBinary()
    let root = getTempDir() / "scour-suppress"
    cleanDir(root)
    createDir(root)
    writeFile(root / "app.ts", "debugger;\n")
    writeFile(root / "scour.toml", """
[suppress.1]
rule = "debugger"
file = "app.ts"
line = 1
reason = "intentional demo"
expires = "2099-01-01"
""")
    let suppressed = run(binary.quoteShell & " --all --format json", root)
    check suppressed.exitCode == 0
    check lastJsonLine(suppressed.output)["summary"]["total"].getInt() == 0

    writeFile(root / "scour.toml", """
[suppress.1]
rule = "debugger"
file = "app.ts"
line = 1
reason = "intentional demo"
expires = "2020-01-01"
""")
    let expired = run(binary.quoteShell & " --all --format json", root)
    check expired.exitCode == 1
    check lastJsonLine(expired.output)["summary"]["total"].getInt() == 1
