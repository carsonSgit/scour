type
  Severity* = enum
    severityError = "error",
    severityWarning = "warning",
    severityInfo = "info"

  FailureThreshold* = enum
    failOnError = "error",
    failOnWarning = "warning",
    failOnInfo = "info"

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

  TriageCounts* = object
    blockers*: int
    fixNow*: int
    review*: int
    cleanup*: int
    ignored*: int

  IssueSummary* = object
    total*: int
    bySeverity*: SeverityCounts
    byTriage*: TriageCounts
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

proc countByTriage*(issues: openArray[Issue]): TriageCounts =
  for issue in issues:
    case issue.triage
    of triageBlocker: inc result.blockers
    of triageFixNow: inc result.fixNow
    of triageReview: inc result.review
    of triageCleanup: inc result.cleanup
    of triageIgnored: inc result.ignored

proc meetsFailureThreshold*(severity: Severity;
    threshold: FailureThreshold): bool =
  case threshold
  of failOnError: severity == severityError
  of failOnWarning: severity in {severityError, severityWarning}
  of failOnInfo: true

proc hasFailingIssues*(issues: openArray[Issue];
    threshold: FailureThreshold): bool =
  for issue in issues:
    if issue.severity.meetsFailureThreshold(threshold):
      return true

proc summarizeIssues*(issues: openArray[Issue]): IssueSummary =
  IssueSummary(
    total: issues.len,
    bySeverity: countBySeverity(issues),
    byTriage: countByTriage(issues),
    affectedFiles: affectedFileCount(issues)
  )
