import sequtils, strutils, os, std/times, baseline, cli, config, errors, files,
    fixes, help, issues, output, repo, rule_catalog, rule_output, scan_plan,
    triage_output
import rules/branch_hygiene
import rules/cross_reference
import rules/repo_hygiene
import rules/security

type ScanOutcome = object
  issues: seq[Issue]
  plan: ScanPlan
  effectiveOptions: CliOptions

proc scanOnce(options: CliOptions; mode: ScanMode; repoContext: RepoContext;
    configDiscovery: ConfigDiscovery;
    runtimeConfig: RuntimeConfig): ScanOutcome =
  var effectiveOptions = options
  if not effectiveOptions.colorExplicit:
    effectiveOptions.colorMode = runtimeConfig.outputColor
  if options.command == commandTriage:
    effectiveOptions.outputFormat = formatText
  elif not effectiveOptions.formatExplicit:
    effectiveOptions.outputFormat = runtimeConfig.outputFormat
  if not effectiveOptions.failOnExplicit:
    effectiveOptions.failOn = runtimeConfig.failOn
  let stats = new ScanStats
  let collected = collectCandidates(repoContext, mode, effectiveOptions,
      runtimeConfig, stats)
  let plan = ScanPlan(
    mode: mode,
    repo: repoContext,
    config: configDiscovery,
    sinceRef: options.sinceRef,
    baseRef: collected.baseRef,
    candidates: collected.files,
    selectedFiles: collected.selectedFiles,
    stats: stats
  )
  let foundIssues = scanBranchHygiene(plan, runtimeConfig) & scanRepoHygiene(
      plan, runtimeConfig) & scanCrossReference(plan, runtimeConfig) &
      scanSecurity(plan, runtimeConfig)
  ScanOutcome(issues: foundIssues, plan: plan,
      effectiveOptions: effectiveOptions)

proc isFixedIssue(issue: Issue; post: seq[Issue]): bool =
  for candidate in post:
    if candidate.ruleId == issue.ruleId and candidate.file == issue.file and
        candidate.line == issue.line:
      return false
  true

proc fixableIssue(issue: Issue): bool =
  findRule(issue.ruleId).fixable

proc runScour*(): int =
  try:
    let options = parseCommandLine()
    if options.showHelp:
      echo helpText
      return 0
    if options.showVersion:
      echo version
      return 0

    let repoContext = discoverRepo()
    let configDiscovery = discoverConfig(repoContext, options.configPath)
    let runtimeConfig = loadConfig(configDiscovery)
    case options.command
    of commandRules:
      stdout.write(renderRules(runtimeConfig))
      return 0
    of commandExplain:
      stdout.write(renderExplanation(findRule(options.explainRuleId),
          runtimeConfig))
      return 0
    of commandScan, commandTriage:
      discard
    if options.baselineWrite.len > 0:
      let modeProbe = resolveScanMode(options, repoContext,
          runtimeConfig.scanMode)
      let probe = scanOnce(options, modeProbe, repoContext, configDiscovery,
          runtimeConfig)
      if probe.plan.stats.unreadable > 0 or probe.plan.stats.missing > 0:
        stderr.writeLine("Fatal: refusing an incomplete baseline; resolve unreadable or missing inputs first")
        return 2
      writeBaselineFile(options.baselineWrite, probe.issues)
      stdout.writeLine("Baseline written to " & options.baselineWrite & " (" &
          $probe.issues.len & " findings)")
      return 0
    let mode = resolveScanMode(options, repoContext, runtimeConfig.scanMode)
    let outcome = scanOnce(options, mode, repoContext, configDiscovery,
        runtimeConfig)
    var plan = outcome.plan
    var effectiveIssues = outcome.issues
    var baselineIds: seq[string] = @[]
    if options.baselinePath.len > 0:
      baselineIds = loadBaselineIds(options.baselinePath)
      plan.baselinePath = options.baselinePath
      let separated = applyBaseline(effectiveIssues, baselineIds)
      effectiveIssues = separated.active
      plan.suppressedCount = separated.suppressed
    var activeIssues: seq[Issue]
    var suppressedCount = plan.suppressedCount
    let today = now().format("yyyy-MM-dd")
    for issueBlock in effectiveIssues:
      let issue = issueBlock
      var suppressed = false
      for suppression in runtimeConfig.suppressions:
        if suppressionApplies(suppression, issue):
          if isExpiredYmd(suppression.expires, today):
            break
          suppressed = true
          break
      if suppressed:
        inc suppressedCount
      else:
        activeIssues.add(issue)
    plan.suppressedCount = suppressedCount
    effectiveIssues = activeIssues
    if options.fixPreview:
      let fixPlan = planFixes(effectiveIssues, repoContext.root, runtimeConfig,
          outcome.plan.stats)
      let patchPath = repoContext.root & DirSep & "scour-fix.patch"
      writePatchFile(fixPlan, patchPath)
      var plannedFindings = 0
      for entry in fixPlan:
        plannedFindings += entry.edits.len
      stdout.writeLine("Planned " & $plannedFindings & " fix finding" &
          (if plannedFindings == 1: "" else: "s") & " across " & $fixPlan.len &
          " file" & (if fixPlan.len == 1: "" else: "s") &
          "; patch written to scour-fix.patch. No checkout files changed.")
      return 0
    if options.fixApply:
      let fixPlan = planFixes(effectiveIssues, repoContext.root, runtimeConfig,
          outcome.plan.stats)
      var plannedFindings = 0
      for entry in fixPlan:
        plannedFindings += entry.edits.len
      if plannedFindings == 0:
        var unfixableOnly = 0
        var remainingNoop = 0
        for original in outcome.issues:
          if not fixableIssue(original):
            inc unfixableOnly
          else:
            inc remainingNoop
        stdout.writeLine("No fixable findings; nothing to change.")
        stdout.write(renderIssues(outcome.issues, outcome.effectiveOptions,
            plan))
        if not outcome.effectiveOptions.exitZero and
            (unfixableOnly > 0 or remainingNoop > 0):
          return 1
        return 0
      let applied = applyFixPlan(fixPlan, repoContext.root)
      if applied.stale.len > 0 or applied.failed.len > 0:
        if applied.stale.len > 0:
          stderr.writeLine("Fatal: content changed since fix planning for: " &
              applied.stale.join(", "))
        if applied.failed.len > 0:
          stderr.writeLine("Fatal: fix application failed for: " &
              applied.failed.join(", "))
        return 2
      let post = scanOnce(options, mode, repoContext, configDiscovery,
          runtimeConfig)
      var remaining = 0
      var unfixable = 0
      for original in outcome.issues:
        let resolved = isFixedIssue(original, post.issues)
        let fixable = fixableIssue(original)
        if fixable and resolved:
          continue
        if fixable:
          inc remaining
        else:
          inc unfixable
      stdout.writeLine("Applied fixes to " & $applied.applied.len & " file" &
          (if applied.applied.len == 1: "" else: "s") & ".")
      stdout.writeLine("Fixed findings: " & $plannedFindings & ", remaining: " &
          $remaining & ", unfixable: " & $unfixable)
      stdout.write(renderIssues(post.issues, outcome.effectiveOptions, post.plan))
      if not outcome.effectiveOptions.exitZero and
          (remaining > 0 or unfixable > 0 or
          post.issues.hasFailingIssues(outcome.effectiveOptions.failOn)):
        return 1
      return 0
    if options.command == commandTriage:
      stdout.write(renderTriage(effectiveIssues))
    else:
      stdout.write(renderIssues(effectiveIssues, outcome.effectiveOptions,
          plan))
    if not outcome.effectiveOptions.exitZero and (
        effectiveIssues.hasFailingIssues(outcome.effectiveOptions.failOn) or
        plan.stats.unreadable > 0 or plan.stats.missing > 0):
      1
    else:
      0
  except FatalUserError as error:
    stderr.writeLine("Fatal: " & error.msg)
    error.exitCode
