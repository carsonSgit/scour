import algorithm, os, osproc, sequtils, strutils, tables

import ../config, ../issues, ../rule_issue, ../scan_plan

const Lockfiles = [
  "package-lock.json",
  "npm-shrinkwrap.json",
  "pnpm-lock.yaml",
  "yarn.lock",
  "bun.lock",
  "bun.lockb"
]

const GeneratedDirs = [
  "dist",
  "build",
  "coverage",
  ".next",
  ".nuxt",
  "out",
  "target",
  ".cache",
  ".parcel-cache",
  ".turbo"
]

proc normalizeRepoPath(path: string): string =
  path.replace('\\', '/')

proc parentDir(path: string): string =
  path.normalizeRepoPath().splitFile.dir.normalizeRepoPath()

proc joinRepoPath(dir, name: string): string =
  if dir.len == 0:
    name
  else:
    dir & "/" & name

proc runGit(root: string; args: string): tuple[output: string; exitCode: int] =
  execCmdEx("git -C " & quoteShell(root) & " " & args)

proc repositoryFiles(plan: ScanPlan): seq[string] =
  if plan.repo.isGit:
    let git = runGit(plan.repo.root, "ls-files")
    if git.exitCode == 0:
      for line in git.output.splitLines():
        if line.len > 0:
          result.add(line.normalizeRepoPath())
      result = result.deduplicate()
      result.sort()
      return

  for candidate in plan.candidates:
    result.add(candidate.normalizeRepoPath())
  result = result.deduplicate()
  result.sort()

proc scanDuplicateLockfiles(result: var seq[Issue]; files: openArray[string]) =
  var fileSet = initTable[string, bool]()
  for file in files:
    fileSet[file] = true

  for file in files:
    if file.splitFile.name & file.splitFile.ext != "package.json":
      continue

    let dir = file.parentDir()
    var found: seq[string]
    for lockfile in Lockfiles:
      let candidate = joinRepoPath(dir, lockfile)
      if fileSet.hasKey(candidate):
        found.add(lockfile)

    if found.len > 1:
      result.add(newRuleIssue(
        "duplicate-lockfiles",
        file,
        "Multiple package manager lockfiles found in the same package root."
      ))

proc isDockerfile(file: string): bool =
  let name = file.normalizeRepoPath().splitFile.name & file.normalizeRepoPath().splitFile.ext
  name == "Dockerfile" or name.startsWith("Dockerfile.")

proc scanDockerignoreMissing(result: var seq[Issue]; files: openArray[string]) =
  var fileSet = initTable[string, bool]()
  for file in files:
    fileSet[file] = true

  for file in files:
    if not file.isDockerfile():
      continue

    let expected = joinRepoPath(file.parentDir(), ".dockerignore")
    if not fileSet.hasKey(expected):
      result.add(newRuleIssue(
        "dockerignore-missing",
        file,
        "Dockerfile has no same-directory .dockerignore."
      ))

proc isGeneratedFile(file: string): bool =
  for part in file.normalizeRepoPath().split('/'):
    if part in GeneratedDirs:
      return true
  false

proc scanGeneratedFiles(result: var seq[Issue]; files: openArray[string]) =
  for file in files:
    if file.isGeneratedFile():
      result.add(newRuleIssue(
        "generated-files",
        file,
        "Generated output is tracked in the repository."
      ))

proc isTrackedEnvFile(file: string): bool =
  let name = file.normalizeRepoPath().splitFile.name &
      file.normalizeRepoPath().splitFile.ext
  if name != ".env" and not name.startsWith(".env."):
    return false
  for safeSuffix in [".example", ".sample", ".template", ".defaults",
      ".dist", ".enc", ".encrypted"]:
    if name.endsWith(safeSuffix):
      return false
  true

proc scanTrackedEnvFiles(result: var seq[Issue]; files: openArray[string];
    runtimeConfig: RuntimeConfig) =
  for file in files:
    let name = file.normalizeRepoPath().splitFile.name &
        file.normalizeRepoPath().splitFile.ext
    if file.isTrackedEnvFile() and name notin runtimeConfig.envExampleFiles:
      result.add(newRuleIssue(
        "tracked-env-file",
        file,
        "Environment file is tracked and may expose credentials."
      ))

proc scanRepoHygiene*(plan: ScanPlan; runtimeConfig = defaultConfig()): seq[Issue] =
  let files = repositoryFiles(plan)
  result.scanDuplicateLockfiles(files)
  result.scanDockerignoreMissing(files)
  result.scanGeneratedFiles(files)
  result.scanTrackedEnvFiles(files, runtimeConfig)
  result = result.applyRuleOverrides(runtimeConfig)
