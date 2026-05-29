type
  Severity* = enum
    severityError = "error",
    severityWarning = "warning",
    severityInfo = "info"

  TriageLevel* = enum
    triageBlocker = "blocker",
    triageFixNow = "fixNow",
    triageReview = "review",
    triageCleanup = "cleanup",
    triageIgnored = "ignored"

  Issue* = object
    ruleId*: string
    severity*: Severity
    category*: string
    triage*: TriageLevel
    file*: string
    line*: int
    column*: int
    message*: string
    suggestion*: string

  SeverityCounts* = object
    errors*: int
    warnings*: int
    infos*: int

  IssueSummary* = object
    total*: int
    bySeverity*: SeverityCounts
    affectedFiles*: int

proc countBySeverity*(issues: openArray[Issue]): SeverityCounts =
  for issue in issues:
    case issue.severity
    of severityError:
      inc result.errors
    of severityWarning:
      inc result.warnings
    of severityInfo:
      inc result.infos

proc affectedFileCount*(issues: openArray[Issue]): int =
  var seen: seq[string]
  for issue in issues:
    if issue.file notin seen:
      seen.add(issue.file)
  seen.len

proc summarizeIssues*(issues: openArray[Issue]): IssueSummary =
  IssueSummary(
    total: issues.len,
    bySeverity: countBySeverity(issues),
    affectedFiles: affectedFileCount(issues)
  )

