import std/[algorithm, strformat, strutils]

import issues, scan_plan, text_output

const
  Reset = "\e[0m"
  Green = "\e[32m"
  Yellow = "\e[33m"
  Red = "\e[31m"
  Bold = "\e[1m"
  Dim = "\e[2m"

proc colorize(text: string; code: string; enabled: bool): string =
  if enabled:
    code & text & Reset
  else:
    text

proc scoreColor(score: IssueScore): string =
  if score.current >= 85:
    Green
  elif score.current >= 60:
    Yellow
  else:
    Red

proc sentiment(score: IssueScore; total: int): string =
  if total == 0:
    "Perfect"
  elif score.current >= 85:
    "Healthy"
  elif score.current >= 60:
    "Mixed"
  else:
    "Needs attention"

# The Scour Doctor mascot — a little face whose expression tracks the score.
# Each face is two 9-wide rows (eyes, mouth) framed by a rounded box so the
# four box lines always line up regardless of the chosen expression.
proc mascotFace(score: IssueScore; total: int): tuple[eyes, mouth, quip: string] =
  if total == 0:
    (" ◠     ◠ ", "  \\___/  ", "spotless — nice work!")
  elif score.current >= 85:
    (" ●     ● ", "   \\_/   ", "looking healthy.")
  elif score.current >= 60:
    (" ●     ● ", "   ───   ", "a few things to tidy.")
  else:
    (" ◑     ◐ ", "   ╱‾╲   ", "let's patch this up.")

proc mascotBox(score: IssueScore; total: int; colors: bool): seq[string] =
  let face = mascotFace(score, total)
  let color = score.scoreColor()
  result = @[
    colorize("╭─────────╮", color, colors),
    colorize("│", color, colors) & colorize(face.eyes, color, colors) &
      colorize("│", color, colors),
    colorize("│", color, colors) & colorize(face.mouth, color, colors) &
      colorize("│", color, colors),
    colorize("╰─────────╯", color, colors)
  ]

proc gauge(score: IssueScore; colors: bool): string =
  let width = 50
  let filled = (score.current * width) div score.max
  let empty = max(0, width - filled)
  let bar = repeat("█", filled) & colorize(repeat("░", empty), Dim, colors)
  colorize(bar, score.scoreColor(), colors)

proc triageTag(level: TriageLevel): string =
  case level
  of triageBlocker: "blocker"
  of triageFixNow: "fix now"
  of triageReview: "review"
  of triageCleanup: "cleanup"
  of triageIgnored: "ignored"

proc priorityOrder(issue: Issue): int =
  case issue.triage
  of triageBlocker: 0
  of triageFixNow: 1
  of triageReview: 2
  of triageCleanup: 3
  of triageIgnored: 4

proc severityOrder(issue: Issue): int =
  case issue.severity
  of severityError: 0
  of severityWarning: 1
  of severityInfo: 2

proc sortedIssues(issues: openArray[Issue]): seq[Issue] =
  result = @issues
  result.sort(proc(a, b: Issue): int =
    result = cmp(a.priorityOrder(), b.priorityOrder())
    if result != 0:
      return result
    result = cmp(a.severityOrder(), b.severityOrder())
    if result != 0:
      return result
    result = cmp(a.file, b.file)
    if result != 0:
      return result
    result = cmp(a.line, b.line)
    if result != 0:
      return result
    result = cmp(a.ruleId, b.ruleId)
  )

proc uniqueIssuesByRule(issues: openArray[Issue]): seq[Issue] =
  var seen: seq[string]
  for issue in issues:
    if issue.ruleId in seen:
      continue
    seen.add(issue.ruleId)
    result.add(issue)

proc statLine(summary: IssueSummary): string =
  var parts = @[
    fmt"{summary.total} issue(s)",
    fmt"{summary.affectedFiles} file(s)",
    fmt"{summary.bySeverity.errors} error(s)",
    fmt"{summary.bySeverity.warnings} warning(s)"
  ]
  if summary.bySeverity.infos > 0:
    parts.add(fmt"{summary.bySeverity.infos} info finding(s)")
  if summary.byTriage.blockers > 0:
    parts.add(fmt"{summary.byTriage.blockers} blocker(s)")
  parts.join(" · ")

proc renderDoctorIssues*(issues: openArray[Issue]; mode = colorNever): string =
  let colors = useColor(mode)
  let summary = summarizeIssues(issues)
  let score = scoreIssues(issues)
  let maxHeadlineIssues = 5
  let mood = score.sentiment(summary.total)
  let face = mascotFace(score, summary.total)
  var lines: seq[string]

  # Mascot box on the left, headline / score / status stacked on the right.
  let box = mascotBox(score, summary.total, colors)
  let title = colorize("Scour Doctor", Bold, colors)
  let scoreLine = colorize(fmt"{score.current} / {score.max}   {mood}",
    score.scoreColor(), colors)
  let status =
    if summary.total == 0: "No issues found — you're good to go."
    else: summary.statLine()

  lines.add("  " & box[0])
  lines.add("  " & box[1] & "   " & title)
  lines.add("  " & box[2] & "   " & scoreLine)
  lines.add("  " & box[3] & "   " & colorize(face.quip, Dim, colors))
  lines.add("")
  lines.add("  " & score.gauge(colors))
  lines.add("")

  if summary.total == 0:
    lines.add("  " & status)
    return lines.join("\n") & "\n"

  lines.add("  " & status)
  lines.add("")

  let headlineIssues = issues.sortedIssues().uniqueIssuesByRule()
  lines.add("Top issues")
  for index, issue in headlineIssues:
    if index >= maxHeadlineIssues:
      break
    let severity =
      case issue.severity
      of severityError: "✖"
      of severityWarning: "⚠"
      of severityInfo: "•"
    lines.add(fmt"  {severity} {issue.ruleId}  ·  {issue.triage.triageTag()}  ·  {issue.location()}")
    lines.add("    " & issue.message)
    if issue.suggestion.len > 0:
      lines.add("    Fix: " & issue.suggestion)
  if headlineIssues.len > maxHeadlineIssues:
    lines.add(fmt"  … and {headlineIssues.len - maxHeadlineIssues} more. Run `scour --all --format json` for the full list.")
  lines.add("")

  lines.add("Paste this report to your agent or fix the issues yourself, then re-run `scour --format doctor`.")
  lines.add("Scour Doctor is clear when the score reaches 100 / 100.")
  lines.join("\n") & "\n"
