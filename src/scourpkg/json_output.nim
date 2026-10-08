import std/json

import issues, scan_plan

proc renderJsonIssues*(issues: openArray[Issue]; plan: ScanPlan): string =
  let summary = summarizeIssues(issues)
  let score = scoreIssues(issues)
  var issueNodes = newJArray()
  for issue in issues:
    issueNodes.add(%*{
      "rule": issue.ruleId,
      "severity": $issue.severity,
      "triage_level": $issue.triage,
      "category": issue.category,
      "file": issue.file,
      "line": issue.line,
      "column": issue.column,
      "message": issue.message,
      "suggestion": issue.suggestion
    })
  let baseRef =
    case plan.mode
    of scanChanged: plan.sinceRef
    of scanStaged: "staged"
    else: ""
  $(%*{
    "summary": {
      "errors": summary.bySeverity.errors,
      "warnings": summary.bySeverity.warnings,
      "info": summary.bySeverity.infos,
      "total": summary.total,
      "files": summary.affectedFiles,
      "triage": {
        "blockers": summary.byTriage.blockers,
        "fix_now": summary.byTriage.fixNow,
        "review": summary.byTriage.review,
        "cleanup": summary.byTriage.cleanup,
        "ignored": summary.byTriage.ignored
    }
  },
    "scan": {
      "mode": modeName(plan.mode),
      "base": baseRef,
      "head": "HEAD",
      "scanned_files": plan.candidates.len
    },
    "score": {
      "current": score.current,
      "max": score.max,
      "model": score.model,
      "deductions": {
        "errors": score.deductions.errors,
        "warnings": score.deductions.warnings,
        "info": score.deductions.infos,
        "blockers": score.deductions.blockers,
        "total": score.deductions.total
      }
    },
    "issues": issueNodes
  }) & "\n"
