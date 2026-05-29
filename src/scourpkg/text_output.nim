import std/[strformat, strutils, terminal]

import issues, scan_plan

const
  Reset = "\e[0m"
  Red = "\e[31m"
  Yellow = "\e[33m"
  Blue = "\e[34m"
  Bold = "\e[1m"

proc parseColorMode*(value: string): bool =
  value in ["auto", "always", "never"]

proc colorModeFromString*(value: string): ColorMode =
  case value
  of "auto": colorAuto
  of "always": colorAlways
  of "never": colorNever
  else: colorAuto

proc useColor*(mode: ColorMode; output: File = stdout): bool =
  case mode
  of colorAlways:
    true
  of colorNever:
    false
  of colorAuto:
    isatty(output)

proc colorize(text: string; code: string; enabled: bool): string =
  if enabled:
    code & text & Reset
  else:
    text

proc severityLabel*(severity: Severity): string =
  case severity
  of severityError: "error"
  of severityWarning: "warning"
  of severityInfo: "info"

proc location*(issue: Issue): string =
  result = issue.file
  if issue.line > 0:
    result.add(":" & $issue.line)
    if issue.column > 0:
      result.add(":" & $issue.column)

proc renderIssues*(issues: openArray[Issue]; mode = colorNever): string =
  let colors = useColor(mode)
  if issues.len == 0:
    return "Scour passed. No failing issues found.\n"

  var lines: seq[string]
  let summary = summarizeIssues(issues)
  lines.add(colorize(fmt"Scour found {summary.total} issue(s).", Bold, colors))
  lines.add("")

  for issue in issues:
    let label = severityLabel(issue.severity)
    let color =
      case issue.severity
      of severityError: Red
      of severityWarning: Yellow
      of severityInfo: Blue
    lines.add(fmt"{colorize(label, color, colors)} {issue.ruleId} {location(issue)} - {issue.message}")
    if issue.suggestion.len > 0:
      lines.add("  Suggestion: " & issue.suggestion)
    lines.add("")

  lines.add(fmt"Summary: {summary.total} issue(s), {summary.bySeverity.errors} error(s), {summary.bySeverity.warnings} warning(s), {summary.bySeverity.infos} info(s), {summary.affectedFiles} file(s)")
  lines.join("\n") & "\n"

proc renderIssues*(issues: openArray[Issue]; options: CliOptions): string =
  renderIssues(issues, options.colorMode)
