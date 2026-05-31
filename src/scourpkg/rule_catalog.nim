import algorithm

import issues

type
  RuleSeverity* = enum
    ruleSeverityError = "error",
    ruleSeverityWarning = "warning",
    ruleSeverityInfo = "info",
    ruleSeverityOff = "off"

  RuleDefinition* = object
    id*: string
    category*: string
    defaultSeverity*: RuleSeverity
    defaultTriage*: TriageLevel
    purpose*: string
    example*: string
    fix*: string

const Rules* = [
  RuleDefinition(id: "ci-command-drift", category: "ci-drift",
    defaultSeverity: ruleSeverityError, defaultTriage: triageBlocker,
    purpose: "Find CI commands that reference missing scripts or task targets.",
    example: "run: npm run missing-script",
    fix: "Restore the referenced target or update the CI command."),
  RuleDefinition(id: "console-log", category: "hygiene",
    defaultSeverity: ruleSeverityWarning, defaultTriage: triageReview,
    purpose: "Find console.log calls left in JavaScript and TypeScript source.",
    example: "console.log('debug');",
    fix: "Remove the debug output or use the project's logging facility."),
  RuleDefinition(id: "debugger", category: "hygiene",
    defaultSeverity: ruleSeverityError, defaultTriage: triageFixNow,
    purpose: "Find debugger statements left in JavaScript and TypeScript source.",
    example: "debugger;",
    fix: "Remove the debugger statement."),
  RuleDefinition(id: "dockerignore-missing", category: "docker-drift",
    defaultSeverity: ruleSeverityWarning, defaultTriage: triageFixNow,
    purpose: "Find Dockerfiles without a same-directory .dockerignore.",
    example: "Dockerfile without .dockerignore",
    fix: "Add a .dockerignore beside the Dockerfile."),
  RuleDefinition(id: "duplicate-lockfiles", category: "package-drift",
    defaultSeverity: ruleSeverityWarning, defaultTriage: triageFixNow,
    purpose: "Find package roots with multiple package manager lockfiles.",
    example: "package-lock.json and yarn.lock beside package.json",
    fix: "Keep the lockfile for the package manager used by the project."),
  RuleDefinition(id: "env-drift", category: "env-drift",
    defaultSeverity: ruleSeverityError, defaultTriage: triageBlocker,
    purpose: "Find used environment variables absent from env example files.",
    example: "process.env.API_TOKEN",
    fix: "Document the variable in an env example file or remove the use."),
  RuleDefinition(id: "focused-test", category: "hygiene",
    defaultSeverity: ruleSeverityError, defaultTriage: triageFixNow,
    purpose: "Find focused tests left in JavaScript and TypeScript source.",
    example: "it.only('works', () => {});",
    fix: "Remove the focus marker."),
  RuleDefinition(id: "generated-files", category: "repo-hygiene",
    defaultSeverity: ruleSeverityWarning, defaultTriage: triageFixNow,
    purpose: "Find tracked files under common generated-output directories.",
    example: "dist/app.js",
    fix: "Remove generated output from version control and ignore it."),
  RuleDefinition(id: "merge-conflict", category: "hygiene",
    defaultSeverity: ruleSeverityError, defaultTriage: triageFixNow,
    purpose: "Find unresolved merge conflict markers.",
    example: "<<<<<<< HEAD",
    fix: "Resolve the conflict and remove the markers."),
  RuleDefinition(id: "package-lock-drift", category: "package-drift",
    defaultSeverity: ruleSeverityWarning, defaultTriage: triageFixNow,
    purpose: "Find changed package manifests without their existing lockfile.",
    example: "package.json changed without package-lock.json",
    fix: "Regenerate and commit the existing lockfile."),
  RuleDefinition(id: "readme-command-drift", category: "docs-drift",
    defaultSeverity: ruleSeverityWarning, defaultTriage: triageFixNow,
    purpose: "Find README commands that reference missing scripts or targets.",
    example: "npm run missing-script",
    fix: "Restore the referenced target or update the README command."),
  RuleDefinition(id: "skipped-test", category: "hygiene",
    defaultSeverity: ruleSeverityError, defaultTriage: triageFixNow,
    purpose: "Find skipped tests left in JavaScript and TypeScript source.",
    example: "test.skip('works', () => {});",
    fix: "Enable the test or document why it remains skipped."),
  RuleDefinition(id: "ts-ignore", category: "hygiene",
    defaultSeverity: ruleSeverityWarning, defaultTriage: triageReview,
    purpose: "Find TypeScript @ts-ignore suppressions.",
    example: "// @ts-ignore",
    fix: "Fix the type error or replace the suppression with a narrower approach.")
]

proc findRule*(ruleId: string): RuleDefinition =
  for definition in Rules:
    if definition.id == ruleId:
      return definition

proc validRuleId*(ruleId: string): bool =
  findRule(ruleId).id.len > 0

proc sortedRules*(): seq[RuleDefinition] =
  result = @Rules
  result.sort(proc(a, b: RuleDefinition): int = cmp(a.id, b.id))

proc toSeverity*(value: RuleSeverity): Severity =
  case value
  of ruleSeverityError: severityError
  of ruleSeverityWarning: severityWarning
  of ruleSeverityInfo, ruleSeverityOff: severityInfo

