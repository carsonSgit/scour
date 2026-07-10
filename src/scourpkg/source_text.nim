import os, strutils

const
  JsTsExtensions* = [".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs", ".mts", ".cts"]
  TsExtensions* = [".ts", ".tsx", ".mts", ".cts"]
  CLikeExtensions = [".java", ".kt", ".kts", ".cs", ".go", ".rs", ".php", ".dart", ".c", ".cc", ".cpp", ".cxx", ".h", ".hpp"]
  HashCommentExtensions = [".py", ".rb"]

type
  SourceLexKind* = enum
    sourceLexNone,
    sourceLexCLike,
    sourceLexHashComment

  SourceLexState* = object
    blockComment: bool
    delimiter: string

proc extension*(path: string): string =
  path.splitFile.ext.toLowerAscii()

proc hasExtension*(path: string; extensions: openArray[string]): bool =
  path.extension() in extensions

proc sourceLexKind*(path: string): SourceLexKind =
  if path.hasExtension(JsTsExtensions) or path.hasExtension(CLikeExtensions):
    sourceLexCLike
  elif path.hasExtension(HashCommentExtensions):
    sourceLexHashComment
  else:
    sourceLexNone

proc startsAt(text, pattern: string; index: int): bool =
  index >= 0 and index + pattern.len <= text.len and
      text[index ..< index + pattern.len] == pattern

proc maskSourceLine*(line: string; kind: SourceLexKind;
    state: var SourceLexState): string =
  result = repeat(' ', line.len)
  if kind == sourceLexNone:
    return result

  var index = 0
  while index < line.len:
    if state.blockComment:
      if line.startsAt("*/", index):
        state.blockComment = false
        index += 2
      else:
        inc index
      continue

    if state.delimiter.len > 0:
      if line.startsAt(state.delimiter, index):
        index += state.delimiter.len
        state.delimiter = ""
      elif line[index] == '\\':
        index += 2
      else:
        inc index
      continue

    if kind == sourceLexCLike and line.startsAt("//", index):
      break
    if kind == sourceLexHashComment and line[index] == '#':
      break
    if kind == sourceLexCLike and line.startsAt("/*", index):
      state.blockComment = true
      index += 2
      continue

    if kind == sourceLexHashComment and (line.startsAt("\"\"\"", index) or
        line.startsAt("'''", index)):
      state.delimiter = line[index ..< index + 3]
      index += 3
      continue
    if line[index] in {'\'', '"'} or (kind == sourceLexCLike and line[index] == '`'):
      let delimiter = $line[index]
      inc index
      var closed = false
      while index < line.len:
        if line[index] == '\\':
          index += 2
        elif line[index] == delimiter[0]:
          inc index
          closed = true
          break
        else:
          inc index
      if not closed and delimiter == "`":
        state.delimiter = delimiter
      continue

    result[index] = line[index]
    inc index

proc maskedSourceText*(text, path: string): string =
  let kind = path.sourceLexKind()
  if kind == sourceLexNone:
    return repeat(' ', text.len)

  var state: SourceLexState
  for rawLine in text.splitLines(keepEol = true):
    var line = rawLine
    var lineEnding = ""
    if line.endsWith("\r\n"):
      line.setLen(line.len - 2)
      lineEnding = "\r\n"
    elif line.endsWith("\n"):
      line.setLen(line.len - 1)
      lineEnding = "\n"
    result.add(line.maskSourceLine(kind, state))
    result.add(lineEnding)
