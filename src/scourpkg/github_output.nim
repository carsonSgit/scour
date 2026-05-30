import std/strutils

import issues

proc escapeData(value: string): string =
  value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")

proc escapeProperty(value: string): string =
  value.escapeData().replace(":", "%3A").replace(",", "%2C")

proc command(severity: Severity): string =
  case severity
  of severityError: "error"
  of severityWarning: "warning"
  of severityInfo: "notice"

proc renderGitHubIssues*(issues: openArray[Issue]): string =
  var lines: seq[string]
  for issue in issues:
    var properties = @[
      "file=" & issue.file.escapeProperty(),
      "title=" & issue.ruleId.escapeProperty()
    ]
    if issue.line > 0:
      properties.add("line=" & $issue.line)
    if issue.column > 0:
      properties.add("col=" & $issue.column)
    var message = issue.message
    if issue.suggestion.len > 0:
      message.add(" Suggestion: " & issue.suggestion)
    lines.add("::" & command(issue.severity) & " " & properties.join(",") &
      "::" & message.escapeData())
  if lines.len > 0:
    lines.join("\n") & "\n"
  else:
    ""
