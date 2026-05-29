import cli, errors, files, help, issues, repo, scan_plan, text_output

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
    let config = discoverConfig(repoContext, options.configPath)
    let mode = resolveScanMode(options, repoContext)
    let collected = collectCandidates(repoContext, mode, options)
    let plan = ScanPlan(
      mode: mode,
      repo: repoContext,
      config: config,
      sinceRef: options.sinceRef,
      baseRef: collected.baseRef,
      candidates: collected.files
    )

    let foundIssues: seq[Issue] = @[]
    stdout.write(renderIssues(foundIssues, options))
    0
  except FatalUserError as error:
    stderr.writeLine("Fatal: " & error.msg)
    error.exitCode
