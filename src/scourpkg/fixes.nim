import os, std/sha1, strutils, tables

import config, errors, issues, scan_plan

type
  EditKind* = enum editDeleteLine

  FileEdit* = object
    line*: int
    kind*: EditKind

  FixPlanEntry* = object
    file*: string
    contentSha*: string
    edits*: seq[FileEdit]
    originalLines*: seq[string]

  FixApplication* = object
    applied*: seq[string]
    stale*: seq[string]
    failed*: seq[string]

proc sha1Text(content: string): string =
  $secureHash(content)

proc hashContent(content: string): string =
  sha1Text(content)

proc standaloneFixableLine(content: string; line: int; ruleId: string): bool =
  let lines = content.splitLines()
  if line < 1 or line > lines.len:
    return false
  let raw = lines[line - 1]
  let trimmed = raw.strip()
  case ruleId
  of "console-log":
    trimmed.startsWith("console.")
  of "debugger":
    trimmed == "debugger;"
  else:
    false

proc planFixes*(issues: seq[Issue]; contentRoot: string;
    stats: ScanStats = nil): seq[FixPlanEntry] =
  var contents: Table[string, string]
  var taken: Table[string, seq[int]]
  for issue in issues:
    if issue.ruleId notin ["console-log", "debugger"] or issue.line < 1:
      continue
    let absolute = contentRoot / issue.file
    if not fileExists(absolute):
      continue
    if not contents.hasKey(issue.file):
      contents[issue.file] =
        try:
          readFile(absolute)
        except IOError, OSError:
          if stats != nil:
            inc(stats.unreadable)
          ""
    let content = contents[issue.file]
    if content.len == 0:
      continue
    if not standaloneFixableLine(content, issue.line, issue.ruleId):
      continue
    if issue.line in taken.getOrDefault(issue.file, @[]):
      continue
    taken.mgetOrPut(issue.file, @[]).add(issue.line)
    var position = -1
    for index, entry in result:
      if entry.file == issue.file:
        position = index
        break
    if position < 0:
      result.add(FixPlanEntry(file: issue.file, contentSha: hashContent(content),
          originalLines: content.splitLines(), edits: @[]))
      position = result.high
    result[position].edits.add(FileEdit(line: issue.line, kind: editDeleteLine))

proc patchForEntry(entry: FixPlanEntry): string =
  result = "diff --git a/" & entry.file & " b/" & entry.file & "\n"
  result.add("--- a/" & entry.file & "\n")
  result.add("+++ b/" & entry.file & "\n")
  type SimpleHunk = object
    first: int
    last: int
    removed: int
  var hunks: seq[SimpleHunk]
  for edit in entry.edits:
    var absorbed = false
    for index, current in hunks:
      if edit.line <= current.last + 3:
        hunks[index].last = max(current.last, edit.line + 3)
        hunks[index].removed = current.removed + 1
        absorbed = true
        break
    if not absorbed:
      hunks.add(SimpleHunk(first: max(1, edit.line - 3),
          last: min(entry.originalLines.len, edit.line + 3), removed: 1))
  for hunk in hunks:
    let kept = entry.originalLines.len - hunk.removed
    result.add("@@ -" & $hunk.first & "," & $(hunk.last - hunk.first + 1) &
        " +" & $hunk.first & "," & $max(0, kept) & " @@\n")
    for index in hunk.first .. min(hunk.last, entry.originalLines.len):
      let line = entry.originalLines[index - 1]
      var removed = false
      for edit in entry.edits:
        if edit.line == index:
          removed = true
          break
      if removed:
        result.add("-" & line & "\n")
      else:
        result.add(" " & line & "\n")

proc writePatchFile*(plan: seq[FixPlanEntry]; path: string) =
  var text = ""
  for entry in plan:
    text.add(patchForEntry(entry))
  try:
    writeFile(path, text)
  except IOError, OSError:
    fatal("cannot write fix patch to " & path & ": " & getCurrentExceptionMsg())

proc applyFixPlan*(plan: seq[FixPlanEntry]; root: string): FixApplication =
  for entry in plan:
    let absolute = root / entry.file
    if not fileExists(absolute):
      result.failed.add(entry.file)
      continue
    var current = ""
    try:
      current = readFile(absolute)
    except IOError, OSError:
      result.failed.add(entry.file)
      continue
    if hashContent(current) != entry.contentSha:
      result.stale.add(entry.file)
      continue
    var lines = entry.originalLines
    let final = lines.len - entry.edits.len
    if final < 0:
      result.failed.add(entry.file)
      continue
    var keep = newSeq[string]()
    for index in 1 .. entry.originalLines.len:
      var removed = false
      for edit in entry.edits:
        if edit.line == index:
          removed = true
          break
      if not removed:
        keep.add(entry.originalLines[index - 1])
    let content = join(keep, "\n")
    let tempPath = absolute & ".scour-fix"
    let permissions =
      try:
        getFilePermissions(absolute)
      except IOError, OSError:
        {}
    try:
      writeFile(tempPath, content)
      if permissions.card > 0:
        setFilePermissions(tempPath, permissions)
      moveFile(tempPath, absolute)
      result.applied.add(entry.file)
    except IOError, OSError:
      result.failed.add(entry.file)
      try:
        if fileExists(tempPath):
          removeFile(tempPath)
      except:
        discard
