import os, strutils

import errors, issues, scan_plan

type
  RuleSeverity* = enum
    ruleSeverityError = "error",
    ruleSeverityWarning = "warning",
    ruleSeverityInfo = "info",
    ruleSeverityOff = "off"

  RuleOverride* = object
    ruleId*: string
    severity*: RuleSeverity
    hasSeverity*: bool
    triage*: TriageLevel
    hasTriage*: bool

  RuntimeConfig* = object
    rules*: seq[RuleOverride]
    ignorePaths*: seq[string]
    maxFileSize*: int
    envExampleFiles*: seq[string]
    ignoredEnvVars*: seq[string]
    outputColor*: ColorMode
    outputFormat*: string

proc defaultConfig*(): RuntimeConfig =
  RuntimeConfig(
    rules: @[],
    ignorePaths: @[],
    maxFileSize: 0,
    envExampleFiles: @[".env.example", ".env.sample", ".env.template", ".env.defaults"],
    ignoredEnvVars: @["NODE_ENV", "CI", "PATH", "HOME", "USER", "SHELL", "PWD", "OLDPWD"],
    outputColor: colorAuto,
    outputFormat: "text"
  )

proc canonicalRuleId*(key: string): string =
  key.replace('_', '-')

proc validRuleId(ruleId: string): bool =
  ruleId in [
    "merge-conflict",
    "debugger",
    "focused-test",
    "skipped-test",
    "console-log",
    "ts-ignore",
    "duplicate-lockfiles",
    "dockerignore-missing",
    "generated-files",
    "env-drift",
    "readme-command-drift",
    "ci-command-drift",
    "package-lock-drift"
  ]

proc unquote(value: string): string =
  if value.len >= 2 and ((value[0] == '"' and value[^1] == '"') or (value[0] == '\'' and value[^1] == '\'')):
    value[1 .. ^2]
  else:
    value

proc parseBool(value: string; path: string; line: int): bool =
  case value
  of "true":
    true
  of "false":
    false
  else:
    fatal("invalid config value in " & path & ":" & $line & ": expected true or false")

proc parseSeverity(value: string; path: string; line: int; key: string): RuleSeverity =
  case value.unquote()
  of "error": ruleSeverityError
  of "warning": ruleSeverityWarning
  of "info": ruleSeverityInfo
  of "off": ruleSeverityOff
  else:
    fatal("invalid config value in " & path & ":" & $line & " for " & key & ": unknown severity `" & value.unquote() & "`. Expected one of: error, warning, info, off")

proc toSeverity*(value: RuleSeverity): Severity =
  case value
  of ruleSeverityError: severityError
  of ruleSeverityWarning: severityWarning
  of ruleSeverityInfo: severityInfo
  of ruleSeverityOff: severityInfo

proc parseTriage(value: string; path: string; line: int; key: string): TriageLevel =
  case value.unquote()
  of "blocker": triageBlocker
  of "fix-now": triageFixNow
  of "review": triageReview
  of "cleanup": triageCleanup
  of "ignored": triageIgnored
  else:
    fatal("invalid config value in " & path & ":" & $line & " for " & key & ": unknown triage `" & value.unquote() & "`. Expected one of: blocker, fix-now, review, cleanup, ignored")

proc parseStringArray(value: string; path: string; line: int; key: string): seq[string] =
  let text = value.strip()
  if not (text.startsWith("[") and text.endsWith("]")):
    fatal("invalid config value in " & path & ":" & $line & " for " & key & ": expected string array")
  let inner = text[1 ..< text.high].strip()
  if inner.len == 0:
    return @[]
  for part in inner.split(','):
    let item = part.strip()
    if item.len == 0:
      continue
    if item.len < 2 or item[0] != '"' or item[^1] != '"':
      fatal("invalid config value in " & path & ":" & $line & " for " & key & ": expected quoted strings")
    result.add(item.unquote())

proc parseSize(value: string; path: string; line: int; key: string): int =
  let text = value.unquote().strip().toLowerAscii()
  var number = ""
  var suffix = ""
  for ch in text:
    if ch.isDigit():
      number.add(ch)
    else:
      suffix.add(ch)
  if number.len == 0:
    fatal("invalid config value in " & path & ":" & $line & " for " & key & ": expected byte size")
  result = parseInt(number)
  case suffix.strip()
  of "", "b": discard
  of "kb", "k": result *= 1024
  of "mb", "m": result *= 1024 * 1024
  else:
    fatal("invalid config value in " & path & ":" & $line & " for " & key & ": expected bytes, KB, or MB")

proc ruleIndex(config: RuntimeConfig; ruleId: string): int =
  for i in 0 ..< config.rules.len:
    if config.rules[i].ruleId == ruleId:
      return i
  -1

proc ensureRule(config: var RuntimeConfig; ruleId: string): int =
  result = config.ruleIndex(ruleId)
  if result >= 0:
    return
  config.rules.add(RuleOverride(ruleId: ruleId))
  result = config.rules.high

proc setRuleSeverity(config: var RuntimeConfig; ruleId: string; severity: RuleSeverity) =
  let index = config.ensureRule(ruleId)
  config.rules[index].severity = severity
  config.rules[index].hasSeverity = true

proc clearRuleSeverity(config: var RuntimeConfig; ruleId: string) =
  let index = config.ensureRule(ruleId)
  config.rules[index].hasSeverity = false

proc setRuleTriage(config: var RuntimeConfig; ruleId: string; triage: TriageLevel) =
  let index = config.ensureRule(ruleId)
  config.rules[index].triage = triage
  config.rules[index].hasTriage = true

proc ruleOverride*(config: RuntimeConfig; ruleId: string): RuleOverride =
  let index = config.ruleIndex(ruleId)
  if index >= 0:
    return config.rules[index]
  RuleOverride(ruleId: ruleId)

proc ruleIsOff*(config: RuntimeConfig; ruleId: string): bool =
  let setting = config.ruleOverride(ruleId)
  setting.hasSeverity and setting.severity == ruleSeverityOff

proc applyRuleOverrides*(issues: seq[Issue]; config: RuntimeConfig): seq[Issue] =
  for issue in issues:
    let setting = config.ruleOverride(issue.ruleId)
    if setting.hasSeverity and setting.severity == ruleSeverityOff:
      continue
    var updated = issue
    if setting.hasSeverity:
      updated.severity = setting.severity.toSeverity()
    if setting.hasTriage:
      updated.triage = setting.triage
    result.add(updated)

proc pathIgnored*(path: string; patterns: openArray[string]): bool =
  let normalized = path.replace('\\', '/')
  for raw in patterns:
    let pattern = raw.replace('\\', '/')
    if pattern.endsWith("/**"):
      let prefix = pattern[0 ..< pattern.len - 3]
      if normalized == prefix or normalized.startsWith(prefix & "/"):
        return true
    elif pattern.endsWith("/"):
      if normalized.startsWith(pattern):
        return true
    elif normalized == pattern or normalized.startsWith(pattern & "/"):
      return true
  false

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
  var pendingKey = ""
  var pendingValue = ""
  var pendingLine = 0
  let content = readFile(discovery.path)
  var lineNumber = 0
  for rawLine in content.splitLines():
    inc lineNumber
    var line = stripComment(rawLine)
    if line.len == 0:
      continue

    if pendingKey.len > 0:
      pendingValue.add(" " & line)
      if line.endsWith("]"):
        case pendingKey
        of "ignore.paths":
          result.ignorePaths = parseStringArray(pendingValue, discovery.path, pendingLine, pendingKey)
        of "env.example_files":
          result.envExampleFiles = parseStringArray(pendingValue, discovery.path, pendingLine, pendingKey)
        of "env.ignored_vars":
          result.ignoredEnvVars = parseStringArray(pendingValue, discovery.path, pendingLine, pendingKey)
        else:
          discard
        pendingKey = ""
        pendingValue = ""
      continue

    if line.startsWith("[") and line.endsWith("]"):
      section = line[1 ..< line.high].strip()
      if section notin ["rules", "triage", "ignore", "scan", "env", "output"]:
        fatal("unknown config section in " & discovery.path & ":" & $lineNumber & ": " & section)
      continue

    let separator = line.find('=')
    if separator < 0:
      fatal("invalid config syntax in " & discovery.path & ":" & $lineNumber)

    let key = line[0 ..< separator].strip()
    let value = line[separator + 1 .. ^1].strip()
    let qualified =
      if section.len > 0: section & "." & key
      else: key

    case section
    of "rules":
      let ruleId = canonicalRuleId(key)
      if not validRuleId(ruleId):
        fatal("unknown config key in " & discovery.path & ":" & $lineNumber & ": " & qualified)
      if value in ["true", "false"]:
        if parseBool(value, discovery.path, lineNumber):
          result.clearRuleSeverity(ruleId)
        else:
          result.setRuleSeverity(ruleId, ruleSeverityOff)
      else:
        result.setRuleSeverity(ruleId, parseSeverity(value, discovery.path, lineNumber, qualified))
    of "triage":
      let ruleId = canonicalRuleId(key)
      if not validRuleId(ruleId):
        fatal("unknown config key in " & discovery.path & ":" & $lineNumber & ": " & qualified)
      result.setRuleTriage(ruleId, parseTriage(value, discovery.path, lineNumber, qualified))
    of "ignore":
      if key != "paths":
        fatal("unknown config key in " & discovery.path & ":" & $lineNumber & ": " & qualified)
      if not value.endsWith("]"):
        pendingKey = qualified
        pendingValue = value
        pendingLine = lineNumber
      else:
        result.ignorePaths = parseStringArray(value, discovery.path, lineNumber, qualified)
    of "scan":
      if key == "max_file_size":
        result.maxFileSize = parseSize(value, discovery.path, lineNumber, qualified)
      elif key in ["mode", "respect_gitignore", "follow_symlinks"]:
        discard
      else:
        fatal("unknown config key in " & discovery.path & ":" & $lineNumber & ": " & qualified)
    of "env":
      if key notin ["example_files", "ignored_vars"]:
        fatal("unknown config key in " & discovery.path & ":" & $lineNumber & ": " & qualified)
      if not value.endsWith("]"):
        pendingKey = qualified
        pendingValue = value
        pendingLine = lineNumber
      elif key == "example_files":
        result.envExampleFiles = parseStringArray(value, discovery.path, lineNumber, qualified)
      else:
        result.ignoredEnvVars = parseStringArray(value, discovery.path, lineNumber, qualified)
    of "output":
      case key
      of "color":
        case value.unquote()
        of "auto": result.outputColor = colorAuto
        of "always": result.outputColor = colorAlways
        of "never": result.outputColor = colorNever
        else: fatal("invalid config value in " & discovery.path & ":" & $lineNumber & " for " & qualified & ": expected auto, always, or never")
      of "format":
        result.outputFormat = value.unquote()
        if result.outputFormat != "text":
          fatal("unsupported output format in " & discovery.path & ":" & $lineNumber & ": " & result.outputFormat & " (only text is supported)")
      else:
        fatal("unknown config key in " & discovery.path & ":" & $lineNumber & ": " & qualified)
    else:
      fatal("unknown config key in " & discovery.path & ":" & $lineNumber & ": " & qualified)

  if pendingKey.len > 0:
    fatal("invalid config syntax in " & discovery.path & ":" & $pendingLine)
