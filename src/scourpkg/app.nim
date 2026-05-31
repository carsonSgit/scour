import cli, config, errors, files, help, issues, output, repo, rule_catalog,
    rule_output, scan_plan
import rules/branch_hygiene
import rules/cross_reference
import rules/repo_hygiene

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
    of commandScan:
      discard
    let mode = resolveScanMode(options, repoContext)
    var effectiveOptions = options
    if not effectiveOptions.colorExplicit:
      effectiveOptions.colorMode = runtimeConfig.outputColor
    if not effectiveOptions.formatExplicit:
      effectiveOptions.outputFormat = runtimeConfig.outputFormat
    if not effectiveOptions.failOnExplicit:
      effectiveOptions.failOn = runtimeConfig.failOn
    let collected = collectCandidates(repoContext, mode, effectiveOptions, runtimeConfig)
    let plan = ScanPlan(
      mode: mode,
      repo: repoContext,
      config: configDiscovery,
      sinceRef: options.sinceRef,
      baseRef: collected.baseRef,
      candidates: collected.files
    )

    let foundIssues = scanBranchHygiene(plan, runtimeConfig) & scanRepoHygiene(
        plan, runtimeConfig) & scanCrossReference(plan, runtimeConfig)
    stdout.write(renderIssues(foundIssues, effectiveOptions))
    if not effectiveOptions.exitZero and foundIssues.hasFailingIssues(
        effectiveOptions.failOn):
      1
    else:
      0
  except FatalUserError as error:
    stderr.writeLine("Fatal: " & error.msg)
    error.exitCode
