import algorithm, os, osproc, sequtils, strutils

import config, errors, scan_plan

const DefaultIgnoredDirectories = [
  ".git",
  "node_modules",
  "vendor",
  ".venv",
  "venv",
  ".tox",
  "__pycache__"
]

proc runGit(root: string; args: string): tuple[output: string, exitCode: int] =
  execCmdEx("git -C " & quoteShell(root) & " " & args)

proc normalizeCandidate(root: string; path: string): string =
  let absolute =
    if path.isAbsolute: path
    else: normalizedPath(root / path)
  if not fileExists(absolute):
    return ""
  try:
    relativePath(absolute, root)
  except ValueError:
    absolute

proc isInsideIgnoredDir(path: string): bool =
  for part in path.split({DirSep, AltSep}):
    if part in DefaultIgnoredDirectories:
      return true
  false

proc isBinaryFile(path: string): bool =
  var file: File
  if not open(file, path):
    return true
  defer: file.close()

  var data = newString(4096)
  let readCount = file.readBuffer(addr data[0], data.len)
  data.setLen(readCount)
  data.find('\0') >= 0

proc addCandidate(result: var seq[string]; root: string; path: string) =
  let relative = normalizeCandidate(root, path)
  if relative.len == 0 or isInsideIgnoredDir(relative):
    return
  let absolute = root / relative
  if isBinaryFile(absolute):
    return
  result.add(relative)

proc uniqueSorted(paths: seq[string]): seq[string] =
  result = paths.deduplicate()
  result.sort()

proc passesConfiguredFilters(root, relative: string; runtimeConfig: RuntimeConfig): bool =
  if relative.pathIgnored(runtimeConfig.ignorePaths):
    return false
  if runtimeConfig.maxFileSize > 0:
    try:
      if getFileSize(root / relative) > runtimeConfig.maxFileSize:
        return false
    except OSError:
      return false
  true

proc applyConfiguredFilters(files: seq[string]; root: string; runtimeConfig: RuntimeConfig): seq[string] =
  for file in files:
    if passesConfiguredFilters(root, file, runtimeConfig):
      result.add(file)

proc filesFromGitDiff(root: string; args: string): seq[string] =
  let git = runGit(root, args)
  if git.exitCode != 0:
    fatal("git diff failed: " & git.output.strip())
  for line in git.output.splitLines():
    if line.len > 0:
      result.addCandidate(root, line)
  result = uniqueSorted(result)

proc tryFilesFromGitDiff(root: string; args: string): tuple[ok: bool, files: seq[string]] =
  let git = runGit(root, args)
  if git.exitCode != 0:
    return (false, @[])
  for line in git.output.splitLines():
    if line.len > 0:
      result.files.addCandidate(root, line)
  result.ok = true
  result.files = uniqueSorted(result.files)

proc collectFilesRec(result: var seq[string]; root, directory: string) =
  if isInsideIgnoredDir(directory):
    return
  for kind, path in walkDir(directory):
    case kind
    of pcDir:
      result.collectFilesRec(root, path)
    of pcFile, pcLinkToFile:
      result.addCandidate(root, path)
    else:
      discard

proc allFiles(root: string): seq[string] =
  result.collectFilesRec(root, root)
  result = uniqueSorted(result)

proc explicitFiles(root: string; paths: seq[string]): seq[string] =
  for path in paths:
    let absolute =
      if path.isAbsolute: path
      else: normalizedPath(root / path)
    if fileExists(absolute):
      result.addCandidate(root, absolute)
    elif dirExists(absolute):
      result.collectFilesRec(root, absolute)
  result = uniqueSorted(result)

proc collectCandidates*(repo: RepoContext; mode: ScanMode; options: CliOptions; runtimeConfig = defaultConfig()): tuple[baseRef: string, files: seq[string]] =
  case mode
  of scanStaged:
    result.files = filesFromGitDiff(repo.root, "diff --cached --name-only --diff-filter=ACMR")
  of scanChanged:
    if options.sinceRef.len > 0:
      result.baseRef = options.sinceRef
      result.files = filesFromGitDiff(repo.root, "diff --name-only --diff-filter=ACMR " & quoteShell(options.sinceRef & "...HEAD"))
    else:
      for base in ["origin/main", "main", "master"]:
        let attempt = tryFilesFromGitDiff(repo.root, "diff --name-only --diff-filter=ACMR " & quoteShell(base & "...HEAD"))
        if attempt.ok:
          result.baseRef = base
          result.files = attempt.files
          return

      let staged = tryFilesFromGitDiff(repo.root, "diff --cached --name-only --diff-filter=ACMR")
      if staged.ok and staged.files.len > 0:
        result.baseRef = "staged"
        result.files = staged.files
      else:
        result.baseRef = "all"
        result.files = allFiles(repo.root)
  of scanAll:
    result.files = allFiles(repo.root)
  of scanExplicitPaths:
    result.files = explicitFiles(repo.root, options.explicitPaths)
  result.files = result.files.applyConfiguredFilters(repo.root, runtimeConfig)
