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
  of triageBlocker: "Blockers"
  of triageFixNow: "Fix now"
  of triageReview: "Needs review"
  of triageCleanup: "Cleanup"
  of triageIgnored: "Ignored"

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
  let counts = countByTriage(issues)
  for level in levels:
    var found = false
    for issue in issues:
      if issue.triage != level:
        continue
      if not found:
        lines.add(fmt"{level.heading()} ({counts.count(level)})")
        lines.add("")
        found = true
      lines.addIssueBlock(issue)
      lines.add("")

  lines.add("Summary")
  for level in levels:
    lines.add(fmt"  {level.countLabel()}: {counts.count(level)}")
  lines.join("\n") & "\n"
