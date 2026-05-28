import algorithm, os, osproc, sequtils, strutils

import errors, scan_plan

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

proc isInsideGitDir(path: string): bool =
  for part in path.split({DirSep, AltSep}):
    if part == ".git":
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
  if relative.len == 0 or isInsideGitDir(relative):
    return
  let absolute = root / relative
  if isBinaryFile(absolute):
    return
  result.add(relative)

proc uniqueSorted(paths: seq[string]): seq[string] =
  result = paths.deduplicate()
  result.sort()

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

proc allFiles(root: string): seq[string] =
  for path in walkDirRec(root, relative = false):
    if isInsideGitDir(path):
      continue
    if fileExists(path):
      result.addCandidate(root, path)
  result = uniqueSorted(result)

proc explicitFiles(root: string; paths: seq[string]): seq[string] =
  for path in paths:
    let absolute =
      if path.isAbsolute: path
      else: normalizedPath(root / path)
    if fileExists(absolute):
      result.addCandidate(root, absolute)
    elif dirExists(absolute):
      for child in walkDirRec(absolute, relative = false):
        result.addCandidate(root, child)
  result = uniqueSorted(result)

proc collectCandidates*(repo: RepoContext; mode: ScanMode; options: CliOptions): tuple[baseRef: string, files: seq[string]] =
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
