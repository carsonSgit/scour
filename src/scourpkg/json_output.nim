import std/json

import issues

proc renderJsonIssues*(issues: openArray[Issue]): string =
  let summary = summarizeIssues(issues)
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
    "issues": issueNodes
  }) & "\n"
