import os, osproc, unittest

import ../src/scourpkg/cli
import ../src/scourpkg/errors
import ../src/scourpkg/files
import ../src/scourpkg/repo
import ../src/scourpkg/scan_plan

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
    check options.explicitPaths == @["src"]

  test "rejects invalid flags":
    expectFatal(proc() = discard parseCliArgs(@["--wat"]))

  test "rejects conflicting scan modes":
    expectFatal(proc() = discard parseCliArgs(@["--staged", "--all"]))
    expectFatal(proc() = discard parseCliArgs(@["--since", "main", "src"]))

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

    let root = getTempDir() / "scour-command"
    cleanDir(root)
    initGitRepo(root)
    writeFile(root / "new.txt", "new\n")
    check run(binary.quoteShell & " --all", root).exitCode == 0
    check run(binary.quoteShell & " new.txt", root).exitCode == 0
    check run("git add new.txt", root).exitCode == 0
    check run(binary.quoteShell & " --staged", root).exitCode == 0
    check run(binary.quoteShell & " --since HEAD", root).exitCode == 0
