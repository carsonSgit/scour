import cli, config, errors, files, help, repo, scan_plan, text_output
import rules/branch_hygiene

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
    let mode = resolveScanMode(options, repoContext)
    let collected = collectCandidates(repoContext, mode, options)
    let plan = ScanPlan(
      mode: mode,
      repo: repoContext,
      config: configDiscovery,
      sinceRef: options.sinceRef,
      baseRef: collected.baseRef,
      candidates: collected.files
    )

    let foundIssues = scanBranchHygiene(plan, runtimeConfig)
    stdout.write(renderIssues(foundIssues, options))
    0
  except FatalUserError as error:
    stderr.writeLine("Fatal: " & error.msg)
    error.exitCode
