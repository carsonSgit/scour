import std/json, std/strutils, std/tables

import help, issues, rule_catalog, scan_plan

proc renderJsonIssues*(issues: openArray[Issue]; plan: ScanPlan): string =
  let summary = summarizeIssues(issues)
  let score = scoreIssues(issues)
  var issueNodes = newJArray()
  var seenIds = initTable[string, int]()
  for issue in issues:
    var item = issue
    item.findingId = stableFindingId(item, seenIds)
    let fixable = findRule(item.ruleId).fixable
    issueNodes.add(%*{
      "id": item.findingId,
      "rule": item.ruleId,
      "severity": $item.severity,
      "triage_level": $item.triage,
      "category": item.category,
      "file": item.file,
      "line": item.line,
      "column": item.column,
      "message": item.message,
      "suggestion": item.suggestion,
      "fixable": fixable
    })
  let baseRef =
    case plan.mode
    of scanChanged: plan.sinceRef
    of scanStaged: "staged"
    else: ""
  var skipped = new ScanStats
  if not plan.stats.isNil:
    skipped = plan.stats
  let complete = skipped.unreadable == 0 and skipped.missing == 0
  $(%*{
    "report_version": 1,
    "tool": {
      "name": "scour",
      "version": version.replace("scour ", ""),
      "schema": "/report-schema-v1.json"
    },
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
      "complete": complete,
      "scanned_files": plan.candidates.len,
      "skipped": {
        "binary": skipped.binarySkipped,
        "oversized": skipped.oversizedSkipped,
        "unreadable": skipped.unreadable,
        "missing": skipped.missing
      }
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
