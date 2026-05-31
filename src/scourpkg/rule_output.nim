import strutils

import config, issues, rule_catalog

proc triageLabel(triage: TriageLevel): string =
  case triage
  of triageFixNow: "fix-now"
  else: $triage

proc renderRules*(config: RuntimeConfig): string =
  for definition in sortedRules():
    result.add(definition.id & "  " & $config.effectiveSeverity(
        definition.id) & "  " & config.effectiveTriage(
        definition.id).triageLabel() & "\n")

proc renderExplanation*(definition: RuleDefinition;
    config: RuntimeConfig): string =
  [
    "Rule: " & definition.id,
    "Category: " & definition.category,
    "Severity: " & $config.effectiveSeverity(definition.id),
    "Triage: " & config.effectiveTriage(definition.id).triageLabel(),
    "Purpose: " & definition.purpose,
    "Example: " & definition.example,
    "Fix: " & definition.fix
  ].join("\n") & "\n"
