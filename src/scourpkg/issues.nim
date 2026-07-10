import strutils, tables

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

  ScoreWeights* = object
    errorPenalty*: int
    warningPenalty*: int
    infoPenalty*: int
    blockerPenalty*: int

  ScoreBreakdown* = object
    errors*: int
    warnings*: int
    infos*: int
    blockers*: int
    total*: int

  IssueScore* = object
    current*: int
    max*: int
    model*: string
    deductions*: ScoreBreakdown

const DefaultScoreWeights* = ScoreWeights(
  errorPenalty: 10,
  warningPenalty: 4,
  infoPenalty: 1,
  blockerPenalty: 3
)

const DefaultScoreModel* = "weighted-v2-frequency-capped"

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

proc scoreIssues*(issues: openArray[Issue];
    weights = DefaultScoreWeights): IssueScore =
  var severityCounts = initCountTable[string]()
  var blockerCounts = initCountTable[string]()
  for issue in issues:
    severityCounts.inc(issue.ruleId & "\x1f" & $issue.severity)
    if issue.triage == triageBlocker:
      blockerCounts.inc(issue.ruleId)

  proc cappedPenalty(count, penalty: int): int =
    # Repeated instances still matter, but a single prolific rule cannot erase
    # the score. Quarter units yield multipliers of 1, 1, .75, .5, and .25.
    let units =
      if count <= 0: 0
      elif count == 1: 4
      elif count == 2: 8
      elif count == 3: 11
      elif count == 4: 13
      else: 14
    (units * penalty + 3) div 4

  var breakdown: ScoreBreakdown
  for key, count in severityCounts.pairs:
    if key.endsWith($severityError):
      breakdown.errors += cappedPenalty(count, weights.errorPenalty)
    elif key.endsWith($severityWarning):
      breakdown.warnings += cappedPenalty(count, weights.warningPenalty)
    else:
      breakdown.infos += cappedPenalty(count, weights.infoPenalty)
  for _, count in blockerCounts.pairs:
    breakdown.blockers += cappedPenalty(count, weights.blockerPenalty)
  let deductions = breakdown.errors + breakdown.warnings + breakdown.infos +
      breakdown.blockers
  IssueScore(
    current: max(0, 100 - deductions),
    max: 100,
    model: DefaultScoreModel,
    deductions: ScoreBreakdown(
      errors: breakdown.errors,
      warnings: breakdown.warnings,
      infos: breakdown.infos,
      blockers: breakdown.blockers,
      total: deductions
    )
  )
