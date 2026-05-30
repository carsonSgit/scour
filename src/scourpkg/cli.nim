import os, strutils

import errors, scan_plan

proc parseCliArgs*(args: seq[string]): CliOptions =
  var options: CliOptions
  options.colorMode = colorAuto
  var index = 0

  while index < args.len:
    let arg = args[index]
    case arg
    of "--help":
      options.showHelp = true
    of "--version":
      options.showVersion = true
    of "--staged":
      options.staged = true
    of "--all":
      options.all = true
    of "--since":
      inc index
      if index >= args.len:
        fatal("--since requires a ref")
      options.sinceRef = args[index]
    of "--config":
      inc index
      if index >= args.len:
        fatal("--config requires a path")
      options.configPath = args[index]
    of "--color":
      inc index
      if index >= args.len:
        fatal("--color requires auto, always, or never")
      options.colorExplicit = true
      case args[index]
      of "auto":
        options.colorMode = colorAuto
      of "always":
        options.colorMode = colorAlways
      of "never":
        options.colorMode = colorNever
      else:
        fatal("invalid --color value: " & args[index])
    of "--":
      discard
    else:
      if arg.startsWith("-"):
        fatal("unknown argument: " & arg)
      options.explicitPaths.add(arg)
    inc index

  let modeCount =
    (if options.staged: 1 else: 0) +
    (if options.sinceRef.len > 0: 1 else: 0) +
    (if options.all: 1 else: 0) +
    (if options.explicitPaths.len > 0: 1 else: 0)

  if modeCount > 1:
    fatal("--staged, --since, --all, and explicit paths cannot be combined")

  options

proc parseCommandLine*(): CliOptions =
  parseCliArgs(commandLineParams())
