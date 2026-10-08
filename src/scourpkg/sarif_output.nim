import std/json, std/strutils, std/tables

import help, issues, rule_catalog, scan_plan

proc renderSarifIssues*(issues: openArray[Issue]; plan: ScanPlan): string =
  var rules = newJArray()
  var ruleIds: seq[string]
  var results = newJArray()
  var seenIds = initTable[string, int]()
  for issue in issues:
    var item = issue
    item.findingId = stableFindingId(item, seenIds)
    if findRule(item.ruleId).id == item.ruleId and item.ruleId notin ruleIds:
      ruleIds.add(item.ruleId)
      let definition = findRule(item.ruleId)
      rules.add(%*{
        "id": definition.id,
        "fullDescription": {"text": definition.purpose},
        "properties": {
          "category": definition.category,
          "triage": $definition.defaultTriage,
          "fixable": definition.fixable
        }
      })
    let level = case item.severity
      of severityError: "error"
      of severityWarning: "warning"
      of severityInfo: "note"
    var location = %*{
      "physicalLocation": {
        "artifactLocation": {"uri": item.file.replace(chr(92), chr(47))}
      }
    }
    if item.line > 0:
      location["physicalLocation"]["region"] = %*{
        "startLine": item.line,
        "startColumn": item.column
      }
    results.add(%*{
      "ruleId": item.ruleId,
      "level": level,
      "message": {"text": item.message},
      "locations": [location],
      "fingerprints": {"scour/finding-id/v1": item.findingId}
    })
  let document = %*{
    "$schema": "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json",
    "version": "2.1.0",
    "runs": [{
      "tool": {"driver": {
        "name": "scour",
        "version": version.replace("scour ", ""),
        "informationUri": "https://github.com/carsonSgit/scour",
        "rules": rules
      }},
      "results": results
    }]
  }
  $document & "\n"
