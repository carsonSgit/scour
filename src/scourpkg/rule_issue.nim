import issues, rule_catalog

proc newRuleIssue*(ruleId, file, message: string; line = 0;
    column = 0): Issue =
  let definition = findRule(ruleId)
  Issue(
    ruleId: ruleId,
    severity: definition.defaultSeverity.toSeverity(),
    category: definition.category,
    triage: definition.defaultTriage,
    file: file,
    line: line,
    column: column,
    message: message,
    suggestion: definition.fix
  )
