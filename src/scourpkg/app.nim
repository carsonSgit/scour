import std/[strformat]

import cli, errors, files, help, repo, scan_plan

proc printPlan(plan: ScanPlan) =
  echo "repo root: " & plan.repo.root
  echo "git detected: " & $plan.repo.isGit
  if plan.config.path.len > 0:
    echo "config: " & plan.config.path
  else:
    echo "config: none"
  echo "scan mode: " & modeName(plan.mode)
  if plan.baseRef.len > 0:
    echo "base ref: " & plan.baseRef
  echo fmt"candidate files: {plan.candidates.len}"
  for path in plan.candidates:
    echo "  " & path

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

    printPlan(plan)
    0
  except FatalUserError as error:
    stderr.writeLine("Fatal: " & error.msg)
    error.exitCode

