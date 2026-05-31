import std/[strformat, strutils]

import issues
import text_output

proc heading(level: TriageLevel): string =
  case level
  of triageBlocker: "Blockers"
  of triageFixNow: "Fix Now"
  of triageReview: "Needs Review"
  of triageCleanup: "Cleanup"
  of triageIgnored: "Ignored"

proc countLabel(level: TriageLevel): string =
  case level
  of triageBlocker: "blocker(s)"
  of triageFixNow: "fix-now"
  of triageReview: "needs-review"
  of triageCleanup: "cleanup"
  of triageIgnored: "ignored"

proc count(counts: TriageCounts; level: TriageLevel): int =
  case level
  of triageBlocker: counts.blockers
  of triageFixNow: counts.fixNow
  of triageReview: counts.review
  of triageCleanup: counts.cleanup
  of triageIgnored: counts.ignored

proc renderTriage*(issues: openArray[Issue]): string =
  var lines = @[fmt"scour triage found {issues.len} issue(s)", ""]
  let levels = [triageBlocker, triageFixNow, triageReview, triageCleanup,
      triageIgnored]
  for level in levels:
    var found = false
    for issue in issues:
      if issue.triage != level:
        continue
      if not found:
        lines.add(level.heading())
        found = true
      lines.add(fmt"  {severityLabel(issue.severity).toUpperAscii()} {issue.ruleId} {location(issue)}")
      lines.add("    " & issue.message)
    if found:
      lines.add("")

  lines.add("Summary")
  let counts = countByTriage(issues)
  for level in levels:
    lines.add(fmt"  {counts.count(level)} {level.countLabel()}")
  lines.join("\n") & "\n"
