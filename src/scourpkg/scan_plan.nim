import issues

type
  OutputFormat* = enum
    formatText = "text",
    formatJson = "json",
    formatGitHub = "github"

  ColorMode* = enum
    colorAuto = "auto",
    colorAlways = "always",
    colorNever = "never"

  ScanMode* = enum
    scanChanged, scanStaged, scanAll, scanExplicitPaths

  CommandMode* = enum
    commandScan, commandRules, commandExplain

  CliOptions* = object
    showHelp*: bool
    showVersion*: bool
    colorMode*: ColorMode
    colorExplicit*: bool
    outputFormat*: OutputFormat
    formatExplicit*: bool
    failOn*: FailureThreshold
    failOnExplicit*: bool
    exitZero*: bool
    staged*: bool
    all*: bool
    sinceRef*: string
    configPath*: string
    explicitPaths*: seq[string]
    command*: CommandMode
    explainRuleId*: string

  RepoContext* = object
    root*: string
    isGit*: bool

  ConfigDiscovery* = object
    path*: string
    isExplicit*: bool

  ScanPlan* = object
    mode*: ScanMode
    repo*: RepoContext
    config*: ConfigDiscovery
    sinceRef*: string
    baseRef*: string
    candidates*: seq[string]

proc modeName*(mode: ScanMode): string =
  case mode
  of scanChanged: "changed"
  of scanStaged: "staged"
  of scanAll: "all"
  of scanExplicitPaths: "explicit-paths"

proc resolveScanMode*(options: CliOptions; repo: RepoContext): ScanMode =
  if options.explicitPaths.len > 0:
    return scanExplicitPaths
  if options.staged:
    return scanStaged
  if options.sinceRef.len > 0:
    return scanChanged
  if options.all:
    return scanAll
  if repo.isGit:
    return scanChanged
  scanAll
