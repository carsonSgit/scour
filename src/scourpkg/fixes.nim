import os, std/sha1, strutils, tables

import config, errors, issues, rule_catalog, scan_plan

type
  EditKind* = enum editDeleteLine, editCreateFile, editReplaceLine

  FileEdit* = object
    line*: int
    kind*: EditKind
    replacement*: string

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

proc validPinSha*(sha: string): bool =
  sha.len == 40 and sha.allCharsInSet({'0'..'9', 'a'..'f', 'A'..'F'})

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

proc workspaceDirectory(file: string): string =
  let normalized = file.replace('\\', '/')
  let withoutName =
    if "/" in normalized:
      normalized[0 ..< normalized.rfind("/")]
    else:
      ""
  if withoutName == ".":
    ""
  else:
    withoutName

proc appendEdit(result: var seq[FixPlanEntry]; file: string; edit: FileEdit;
    content: string) =
  var position = -1
  for index, entry in result:
    if entry.file == file:
      position = index
      break
  if position < 0:
    result.add(FixPlanEntry(file: file, contentSha: hashContent(content),
        originalLines: content.splitLines(), edits: @[]))
    position = result.high
  result[position].edits.add(edit)

proc planFixes*(issues: seq[Issue]; contentRoot: string;
    runtimeConfig = defaultConfig(); stats: ScanStats = nil): seq[FixPlanEntry] =
  var contents: Table[string, string]
  var taken: Table[string, seq[int]]
  var placements: Table[string, bool]
  for issue in issues:
    let rule = findRule(issue.ruleId)
    if not rule.fixable:
      continue
    case issue.ruleId
    of "dockerignore-missing":
      if issue.file.endsWith(".dockerignore"):
        continue
      let directory = workspaceDirectory(issue.file)
      let target = (if directory.len == 0: "" else: directory & "/") &
          ".dockerignore"
      if fileExists(contentRoot / target):
        continue
      if placements.hasKey(target):
        continue
      var lines: seq[string] = @[]
      for item in runtimeConfig.dockerignoreEntries:
        lines.add(item)
      let content = join(lines, "\n") & "\n"
      result.add(FixPlanEntry(file: target, contentSha: "",
          originalLines: @[], edits: @[
            FileEdit(line: 0, kind: editCreateFile, replacement: content)]))
      placements[target] = true
    of "unpinned-github-action":
      if issue.line < 1 or issue.file.len == 0:
        continue
      if not contents.hasKey(issue.file):
        contents[issue.file] =
          try:
            readFile(contentRoot / issue.file)
          except IOError, OSError:
            if stats != nil:
              inc(stats.unreadable)
            ""
      let content = contents[issue.file]
      if content.len == 0:
        continue
      let lines = content.splitLines()
      if issue.line > lines.len:
          continue
      let raw = lines[issue.line - 1]
      let usesIndex = raw.find("uses:")
      if usesIndex < 0:
          continue
      var reference = raw[usesIndex + 5 .. ^1].strip()
      if reference.len > 1 and reference[0] in {'\'', '"'} and
          reference[^1] == reference[0]:
        reference = reference[1 ..< reference.high]
      reference = reference.splitWhitespace()[0]
      let at = reference.find("@")
      if at <= 0 or at + 1 >= reference.len:
        continue
      let name = reference[0 ..< at]
      let tag = reference[at + 1 .. ^1]
      if validPinSha(tag):
        continue
      var sha = ""
      if runtimeConfig.pinActions.hasKey(reference):
        sha = runtimeConfig.pinActions[reference]
      elif runtimeConfig.pinActions.hasKey(name):
        sha = runtimeConfig.pinActions[name]
      else:
        continue
      if not validPinSha(sha):
        continue
      let start = raw.find(reference)
      if start < 0:
        continue
      let newLine = raw[0 ..< start] & name & "@" & sha & " # " & tag &
          raw[start + reference.len .. ^1]
      if newLine == raw:
        continue
      appendEdit(result, issue.file,
          FileEdit(line: issue.line, kind: editReplaceLine,
              replacement: newLine), content)
    else:
      if issue.line < 1 or issue.file.len == 0:
        continue
      if not contents.hasKey(issue.file):
        contents[issue.file] =
          try:
            readFile(contentRoot / issue.file)
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
      appendEdit(result, issue.file,
          FileEdit(line: issue.line, kind: editDeleteLine), content)

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
    if edit.kind == editCreateFile:
      result.setLen(0)
      break
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
  if result.len == 0:
    result = "diff --git a/" & entry.file & " b/" & entry.file & "\n"
    result.add("new file mode 100644\n")
    result.add("--- /dev/null\n")
    result.add("+++ b/" & entry.file & "\n")
    for line in entry.edits[0].replacement.splitLines():
      result.add("+" & line & "\n")
    return
  for hunk in hunks:
    let kept = entry.originalLines.len - hunk.removed
    result.add("@@ -" & $hunk.first & "," & $(hunk.last - hunk.first + 1) &
        " +" & $hunk.first & "," & $max(0, kept) & " @@\n")
    for index in hunk.first .. min(hunk.last, entry.originalLines.len):
      let line = entry.originalLines[index - 1]
      var changed = ""
      for edit in entry.edits:
        if edit.line == index:
          changed = if edit.kind == editDeleteLine: "-" else: "+" &
              edit.replacement
          break
      if changed.len == 0:
        result.add(" " & line & "\n")
      elif changed.startsWith("+"):
        result.add(changed & "\n")
      else:
        result.add("-" & line & "\n")
        for edit in entry.edits:
          if edit.line == index and edit.kind == editReplaceLine:
            result.add("+" & edit.replacement & "\n")
            break

proc writePatchFile*(plan: seq[FixPlanEntry]; path: string) =
  var text = ""
  for entry in plan:
    text.add(patchForEntry(entry))
  try:
    writeFile(path, text)
  except IOError, OSError:
    fatal("cannot write fix patch to " & path & ": " &
        getCurrentExceptionMsg())

proc applyFixPlan*(plan: seq[FixPlanEntry]; root: string): FixApplication =
  for entry in plan:
    let absolute = root / entry.file
    var current = ""
    if entry.edits.len > 0 and entry.edits[0].kind == editCreateFile:
      if fileExists(absolute):
        result.failed.add(entry.file)
        continue
      try:
        writeFile(absolute, entry.edits[0].replacement)
        result.applied.add(entry.file)
      except IOError, OSError:
        result.failed.add(entry.file)
      continue
    if not fileExists(absolute):
      result.failed.add(entry.file)
      continue
    try:
      current = readFile(absolute)
    except IOError, OSError:
      result.failed.add(entry.file)
      continue
    if hashContent(current) != entry.contentSha:
      result.stale.add(entry.file)
      continue
    var keep = newSeq[string]()
    for index in 1 .. entry.originalLines.len:
      var changed = ""
      for edit in entry.edits:
        if edit.line == index:
          changed = if edit.kind == editDeleteLine: "-" else: "+" &
              edit.replacement
          break
      if changed.len == 0:
        keep.add(entry.originalLines[index - 1])
      elif changed.startsWith("+"):
        keep.add(changed[1 .. ^1])
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
