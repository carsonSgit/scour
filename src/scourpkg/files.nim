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

proc isInsideIgnoredDir(path: string): bool =
  for part in path.split({DirSep, AltSep}):
    if part in DefaultIgnoredDirectories:
      return true
  false

proc insideRoot(root, absolute: string): bool =
  let canonical =
    try:
      absolutePath(absolute)
    except ValueError:
      return false
  let rootCanonical = absolutePath(root)
  canonical == rootCanonical or canonical.startsWith(rootCanonical & DirSep)

proc stagedBlobSize(root: string; file: string): int =
  let git = runGit(root, "cat-file -s :\"" & file & "\"")
  if git.exitCode != 0:
    return -1
  try:
    parseInt(git.output.strip())
  except ValueError:
    -1

proc snapshotFileExists*(root: string; file: string; mode: ScanMode): bool =
  if mode != scanStaged:
    fileExists(root / file) or dirExists(root / file)
  else:
    stagedBlobSize(root, file) >= 0

proc snapshotPresence*(root: string; file: string; mode: ScanMode): bool =
  snapshotFileExists(root, file, mode)

proc readSnapshotContent*(root: string; file: string; mode: ScanMode;
    stats: ScanStats = nil): string =
  if mode != scanStaged:
    let path = root / file
    if not fileExists(path):
      return ""
    try:
      result = readFile(path)
    except IOError, OSError:
      if stats != nil:
        inc(stats.unreadable)
      result = ""
  else:
    let git = runGit(root, "show :\"" & file & "\"")
    if git.exitCode == 0:
      result = git.output

proc normalizeCandidate(root: string; path: string; stats: ScanStats;
    mode = scanAll): string =
  if path.len == 0:
    return ""
  let absolute =
    if path.isAbsolute: path
    else: normalizedPath(root / path)
  if mode == scanStaged:
    if path.isAbsolute:
      if stats != nil:
        inc(stats.missing)
      return ""
    if stagedBlobSize(root, path) < 0:
      if stats != nil:
        inc(stats.missing)
      return ""
  elif not (fileExists(absolute) or dirExists(absolute)):
    if stats != nil:
      inc(stats.missing)
    return ""
  if not insideRoot(root, absolute):
    if stats != nil:
      inc(stats.missing)
    return ""
  result =
    try:
      relativePath(absolute, root)
    except ValueError:
      absolute

proc classifyFile(absolute: string): ScanFileKind =
  var file: File
  if not open(file, absolute):
    return fileUnreadable
  defer: file.close()

  var data = newString(4096)
  let readCount = file.readBuffer(addr data[0], data.len)
  data.setLen(readCount)
  if data.find('\0') >= 0:
    fileBinary
  else:
    fileReadable

proc addCandidate(result: var seq[string]; root: string; path: string;
    stats: ScanStats = nil; mode = scanAll) =
  let relative = normalizeCandidate(root, path, stats, mode)
  if relative.len == 0 or isInsideIgnoredDir(relative):
    return
  if mode == scanStaged:
    if not snapshotPresence(root, relative, mode):
      if stats != nil:
        inc(stats.missing)
      return
    let content = readSnapshotContent(root, relative, mode)
    if content.find('\0') >= 0:
      if stats != nil:
        inc(stats.binarySkipped)
      return
    result.add(relative)
  else:
    let absolute = root / relative
    case classifyFile(absolute)
    of fileBinary:
      if stats != nil:
        inc(stats.binarySkipped)
      return
    of fileUnreadable:
      if stats != nil:
        inc(stats.unreadable)
      return
    of fileReadable:
      result.add(relative)

proc uniqueSorted(paths: seq[string]): seq[string] =
  result = paths.deduplicate()
  result.sort()

proc passesConfiguredFilters*(root, relative: string; runtimeConfig: RuntimeConfig;
    mode = scanAll): bool =
  if relative.pathIgnored(runtimeConfig.ignorePaths):
    return false
  if runtimeConfig.maxFileSize > 0:
    var size = 0
    if mode == scanStaged:
      let blob = stagedBlobSize(root, relative)
      if blob < 0:
        return false
      size = blob
    else:
      try:
        size = getFileSize(root / relative).int
      except OSError:
        return false
    if size > runtimeConfig.maxFileSize:
      return false
  true

proc applyConfiguredFilters(files: seq[string]; root: string;
    runtimeConfig: RuntimeConfig; stats: ScanStats; mode = scanAll): seq[string] =
  for file in files:
    if passesConfiguredFilters(root, file, runtimeConfig, mode):
      result.add(file)
    else:
      if stats != nil:
        inc(stats.oversizedSkipped)

proc gitIgnoredFiles(root: string; files: seq[string]): seq[string] =
  if files.len == 0:
    return @[]
  let listPath = joinPath(getTempDir(), "scour-ignore-check")
  writeFile(listPath, files.join("\0") & "\0")
  let git = runGit(root, "check-ignore -z --stdin < " & quoteShell(listPath))
  try:
    removeFile(listPath)
  except OSError:
    discard
  if git.exitCode != 0 and git.output.strip().len == 0:
    return @[]
  for entry in git.output.split('\0'):
    if entry.len > 0:
      result.add(entry)
  result = result.deduplicate()

proc filesFromGitDiff(root: string; args: string;
    stats: ScanStats = nil; mode = scanAll): seq[string] =
  let git = runGit(root, args)
  if git.exitCode != 0:
    fatal("git diff failed for '" & args & "' using merge-base semantics; " &
        "supply a reachable --since ref or fetch the comparison history " &
        "(a shallow or forked clone may be missing it): " & git.output.strip())
  var lines = git.output.split('\0')
  while lines.len > 0 and (lines[^1].len == 0 or lines[^1] == "\n" or
      lines[^1].allCharsInSet({'\n', '\r'})):
    lines.setLen(lines.len - 1)
  for line in lines:
    if line.len > 0:
      result.addCandidate(root, line, stats, mode)
  result = uniqueSorted(result)

proc collectFilesRec(result: var seq[string]; root, directory: string;
    followSymlinks = false; stats: ScanStats = nil) =
  if isInsideIgnoredDir(directory):
    return
  for kind, path in walkDir(directory):
    case kind
    of pcDir:
      result.collectFilesRec(root, path, followSymlinks, stats)
    of pcFile:
      result.addCandidate(root, path, stats)
    of pcLinkToFile:
      if followSymlinks:
        if insideRoot(root, path):
          result.addCandidate(root, path, stats)
        elif stats != nil:
          inc(stats.missing)
    of pcLinkToDir:
      if followSymlinks:
        if insideRoot(root, path):
          result.collectFilesRec(root, path, followSymlinks, stats)
        elif stats != nil:
          inc(stats.missing)

proc allFiles(root: string; followSymlinks = false; stats: ScanStats = nil): seq[string] =
  result.collectFilesRec(root, root, followSymlinks, stats)
  result = uniqueSorted(result)

proc explicitFiles(root: string; paths: seq[string]; followSymlinks = false;
    stats: ScanStats = nil): seq[string] =
  for path in paths:
    let absolute =
      if path.isAbsolute: path
      else: normalizedPath(root / path)
    if fileExists(absolute) and not insideRoot(root, absolute):
      if stats != nil:
        inc(stats.missing)
      continue
    if fileExists(absolute):
      result.addCandidate(root, absolute, stats)
    elif dirExists(absolute):
      result.collectFilesRec(root, absolute, followSymlinks, stats)
    elif stats != nil:
      inc(stats.missing)
  result = uniqueSorted(result)

type CollectedCandidates* = tuple[baseRef: string, files: seq[string],
    selectedFiles: seq[string], stats: ScanStats]

proc collectCandidates*(repo: RepoContext; mode: ScanMode; options: CliOptions;
    runtimeConfig = defaultConfig(); stats: ScanStats = nil): CollectedCandidates =
  var stats = stats
  if stats.isNil:
    stats = new ScanStats
  case mode
  of scanStaged:
    result.files = filesFromGitDiff(repo.root, "diff --cached --name-only --diff-filter=ACMR -z", stats, mode)
  of scanChanged:
    if options.sinceRef.len == 0:
      fatal("changed scan requires --since <ref>; use --all for the full tracked checkout")
    result.baseRef = options.sinceRef
    result.files = filesFromGitDiff(repo.root, "diff --name-only --diff-filter=ACMR -z " & quoteShell(options.sinceRef & "...HEAD"), stats, mode)
  of scanAll:
    result.files = allFiles(repo.root, runtimeConfig.followSymlinks, stats)
  of scanExplicitPaths:
    result.files = explicitFiles(repo.root, options.explicitPaths, runtimeConfig.followSymlinks, stats)
  result.stats = stats
  result.selectedFiles = result.files
  result.files = result.files.applyConfiguredFilters(repo.root, runtimeConfig, stats, mode)
  if runtimeConfig.respectGitignore and repo.isGit and result.files.len > 0:
    let ignored = gitIgnoredFiles(repo.root, result.files)
    if ignored.len > 0:
      for ignoredFile in ignored:
        result.files = result.files.filterIt(it != ignoredFile)
