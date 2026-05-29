import os, osproc, strutils, unittest

import ../src/scourpkg/cli
import ../src/scourpkg/errors
import ../src/scourpkg/files
import ../src/scourpkg/issues
import ../src/scourpkg/repo
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
