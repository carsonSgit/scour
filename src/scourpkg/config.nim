import os, strutils

import errors, scan_plan

type
  RuleSettings* = object
    consoleLog*: bool

  RuntimeConfig* = object
    rules*: RuleSettings

proc defaultConfig*(): RuntimeConfig =
  RuntimeConfig(rules: RuleSettings(consoleLog: true))

proc parseBool(value: string; path: string; line: int): bool =
  case value
  of "true":
    true
  of "false":
    false
  else:
    fatal("invalid config value in " & path & ":" & $line & ": expected true or false")

proc stripComment(line: string): string =
  let marker = line.find('#')
  if marker >= 0:
    line[0 ..< marker].strip()
  else:
    line.strip()

proc loadConfig*(discovery: ConfigDiscovery): RuntimeConfig =
  result = defaultConfig()
  if discovery.path.len == 0:
    return
  if not fileExists(discovery.path):
    if discovery.isExplicit:
      fatal("config file not found: " & discovery.path)
    return

  var section = ""
  let content = readFile(discovery.path)
  var lineNumber = 0
  for rawLine in content.splitLines():
    inc lineNumber
    let line = stripComment(rawLine)
    if line.len == 0:
      continue

    if line.startsWith("[") and line.endsWith("]"):
      section = line[1 ..< line.high].strip()
      if section != "rules":
        fatal("unknown config section in " & discovery.path & ":" & $lineNumber & ": " & section)
      continue

    let separator = line.find('=')
    if separator < 0:
      fatal("invalid config syntax in " & discovery.path & ":" & $lineNumber)

    let key = line[0 ..< separator].strip()
    let value = line[separator + 1 .. ^1].strip()
    if section == "rules" and key == "console-log":
      result.rules.consoleLog = parseBool(value, discovery.path, lineNumber)
    else:
      let qualified =
        if section.len > 0: section & "." & key
        else: key
      fatal("unknown config key in " & discovery.path & ":" & $lineNumber & ": " & qualified)
