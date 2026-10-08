import std/json, std/tables

import issues, rule_catalog, scan_plan

proc renderCodequalityIssues*(issues: openArray[Issue]; plan: ScanPlan): string =
  var nodes = newJArray()
  var seenIds = initTable[string, int]()
  for issue in issues:
    var item = issue
    item.findingId = stableFindingId(item, seenIds)
    let severity = case item.severity
      of severityError: "major"
      of severityWarning: "minor"
      of severityInfo: "info"
    nodes.add(%*{
      "description": item.message,
      "check_name": item.ruleId,
      "fingerprint": item.findingId,
      "severity": severity,
      "location": {
        "path": item.file,
        "lines": {"begin": item.line, "end": item.line}
      }
    })
  $nodes & "\n"
