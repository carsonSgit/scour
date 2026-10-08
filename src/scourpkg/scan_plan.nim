import issues

type
  ScanStats* = ref object
    binarySkipped*: int
    oversizedSkipped*: int
    unreadable*: int
    missing*: int

  ScanFileKind* = enum fileReadable, fileBinary, fileUnreadable

  OutputFormat* = enum
    formatText = "text",
    formatJson = "json",
    formatGitHub = "github",
    formatDoctor = "doctor"

  ColorMode* = enum
    colorAuto = "auto",
    colorAlways = "always",
    colorNever = "never"

  ScanMode* = enum
    scanChanged, scanStaged, scanAll, scanExplicitPaths

  CommandMode* = enum
    commandScan, commandTriage, commandRules, commandExplain

  CliOptions* = object
    showHelp*: bool
    showVersion*: bool
    scoreOnly*: bool
    colorMode*: ColorMode
    colorExplicit*: bool
    outputFormat*: OutputFormat
    formatExplicit*: bool
    failOn*: FailureThreshold
    failOnExplicit*: bool
    exitZero*: bool
    fixPreview*: bool
    fixApply*: bool
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
    selectedFiles*: seq[string]
    stats*: ScanStats

proc modeName*(mode: ScanMode): string =
  case mode
  of scanChanged: "changed"
  of scanStaged: "staged"
  of scanAll: "all"
  of scanExplicitPaths: "explicit-paths"

proc resolveScanMode*(options: CliOptions; repo: RepoContext; configuredMode = ""): ScanMode =
  if options.explicitPaths.len > 0:
    return scanExplicitPaths
  if options.staged:
    return scanStaged
  if options.sinceRef.len > 0:
    return scanChanged
  if options.all:
    return scanAll
  if configuredMode == "staged":
    return scanStaged
  scanAll
