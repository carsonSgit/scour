import algorithm, os, osproc, sequtils, strutils, tables

import ../issues, ../scan_plan

const Lockfiles = [
  "package-lock.json",
  "npm-shrinkwrap.json",
  "pnpm-lock.yaml",
  "yarn.lock",
  "bun.lock",
  "bun.lockb"
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

proc runGit(root: string; args: string): tuple[output: string, exitCode: int] =
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

proc warning(ruleId, category, file, message: string): Issue =
  Issue(
    ruleId: ruleId,
    severity: severityWarning,
    category: category,
    triage: triageFixNow,
    file: file,
    message: message
  )

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
      result.add(warning(
        "duplicate-lockfiles",
        "package-drift",
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
      result.add(warning(
        "dockerignore-missing",
        "docker-drift",
        file,
        "Dockerfile has no same-directory .dockerignore."
      ))

proc scanRepoHygiene*(plan: ScanPlan): seq[Issue] =
  let files = repositoryFiles(plan)
  result.scanDuplicateLockfiles(files)
  result.scanDockerignoreMissing(files)
