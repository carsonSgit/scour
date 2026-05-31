import algorithm, json, os, osproc, sequtils, strutils, tables

import ../config, ../issues, ../rule_catalog, ../scan_plan

const
  NodeLockfiles = [
    "package-lock.json",
    "npm-shrinkwrap.json",
    "pnpm-lock.yaml",
    "yarn.lock",
    "bun.lock",
    "bun.lockb"
  ]

type
  CommandInventory = object
    packageScripts: Table[string, bool]
    makeTargets: Table[string, bool]
    justTargets: Table[string, bool]
    taskTargets: Table[string, bool]

proc normalizeRepoPath(path: string): string =
  path.replace('\\', '/')

proc parentDir(path: string): string =
  path.normalizeRepoPath().splitFile.dir.normalizeRepoPath()

proc fileName(path: string): string =
  let split = path.normalizeRepoPath().splitFile
  split.name & split.ext

proc joinRepoPath(dir, name: string): string =
  if dir.len == 0:
    name
  else:
    dir & "/" & name

proc runGit(root: string; args: string): tuple[output: string; exitCode: int] =
  execCmdEx("git -C " & quoteShell(root) & " " & args)

proc repositoryFiles(plan: ScanPlan): seq[string] =
  if plan.repo.isGit:
    let git = runGit(plan.repo.root, "ls-files")
    if git.exitCode == 0:
      for line in git.output.splitLines():
        if line.len > 0:
          result.add(line.normalizeRepoPath())
      result = result.deduplicate()
      result.sort()
      return

  for candidate in plan.candidates:
    result.add(candidate.normalizeRepoPath())
  result = result.deduplicate()
  result.sort()

proc safeRead(root, file: string): string =
  let path = root / file
  if fileExists(path):
    readFile(path)
  else:
    ""

proc lineColumn(text: string; index: int): tuple[line: int; column: int] =
  result = (line: 1, column: 1)
  for i in 0 ..< min(index, text.len):
    if text[i] == '\n':
      inc result.line
      result.column = 1
    else:
      inc result.column

proc issue(
    ruleId, category: string;
    severity: Severity;
    triage: TriageLevel;
    file: string;
    line, column: int;
    message: string
): Issue =
  let definition = findRule(ruleId)
  Issue(
    ruleId: ruleId,
    severity: definition.defaultSeverity.toSeverity(),
    category: definition.category,
    triage: definition.defaultTriage,
    file: file,
    line: line,
    column: column,
    message: message
  )

proc envError(file: string; line, column: int; name: string): Issue =
  issue(
    "env-drift",
    "env-drift",
    severityError,
    triageBlocker,
    file,
    line,
    column,
    "Environment variable " & name & " is used but absent from env example files."
  )

proc commandWarning(ruleId, category, file: string; line, column: int;
    command: string): Issue =
  issue(
    ruleId,
    category,
    severityWarning,
    triageFixNow,
    file,
    line,
    column,
    "Command `" & command & "` references a missing script or task target."
  )

proc commandError(ruleId, category, file: string; line, column: int;
    command: string): Issue =
  issue(
    ruleId,
    category,
    severityError,
    triageBlocker,
    file,
    line,
    column,
    "Command `" & command & "` references a missing script or task target."
  )

proc packageWarning(file: string): Issue =
  issue(
    "package-lock-drift",
    "package-drift",
    severityWarning,
    triageFixNow,
    file,
    0,
    0,
    "package.json changed without its existing Node lockfile."
  )

proc loadEnvNames(root: string; files: openArray[string];
    exampleNames: openArray[string]): Table[string, bool] =
  for file in files:
    if file.fileName() notin exampleNames:
      continue
    for line in safeRead(root, file).splitLines():
      let trimmed = line.strip()
      if trimmed.len == 0 or trimmed.startsWith("#"):
        continue
      let equals = trimmed.find('=')
      if equals > 0:
        result[trimmed[0 ..< equals].strip()] = true

proc isEnvStart(ch: char): bool =
  ch == '_' or (ch >= 'A' and ch <= 'Z')

proc isEnvPart(ch: char): bool =
  ch.isEnvStart() or (ch >= '0' and ch <= '9')

proc addEnvIssue(
    result: var seq[Issue];
    file, text, name: string;
    index: int;
    documented: Table[string, bool];
    ignoredNames: openArray[string]
) =
  if name.len == 0 or name in ignoredNames or documented.hasKey(name):
    return
  let location = text.lineColumn(index)
  result.add(envError(file, location.line, location.column, name))

proc scanPropertyEnv(
    result: var seq[Issue];
    file, text, prefix: string;
    documented: Table[string, bool];
    ignoredNames: openArray[string]
) =
  var searchFrom = 0
  while true:
    let index = text.find(prefix, searchFrom)
    if index < 0:
      break
    let nameStart = index + prefix.len
    var nameEnd = nameStart
    if nameStart < text.len and text[nameStart].isEnvStart():
      while nameEnd < text.len and text[nameEnd].isEnvPart():
        inc nameEnd
      result.addEnvIssue(file, text, text[nameStart ..< nameEnd], index,
          documented, ignoredNames)
    searchFrom = max(index + 1, nameEnd)

proc scanQuotedEnv(
    result: var seq[Issue];
    file, text, prefix: string;
    documented: Table[string, bool];
    ignoredNames: openArray[string]
) =
  var searchFrom = 0
  while true:
    let index = text.find(prefix, searchFrom)
    if index < 0:
      break
    let quoteIndex = index + prefix.len
    if quoteIndex >= text.len or text[quoteIndex] notin ['"', '\'']:
      searchFrom = index + 1
      continue
    let quote = text[quoteIndex]
    let nameStart = quoteIndex + 1
    var nameEnd = nameStart
    if nameStart < text.len and text[nameStart].isEnvStart():
      while nameEnd < text.len and text[nameEnd].isEnvPart():
        inc nameEnd
      if nameEnd < text.len and text[nameEnd] == quote:
        result.addEnvIssue(file, text, text[nameStart ..< nameEnd], index,
            documented, ignoredNames)
    searchFrom = max(index + 1, nameEnd)

proc scanEnvDrift(result: var seq[Issue]; plan: ScanPlan; files: openArray[
    string]; runtimeConfig: RuntimeConfig) =
  let documented = loadEnvNames(plan.repo.root, files,
      runtimeConfig.envExampleFiles)
  for candidate in plan.candidates:
    let text = safeRead(plan.repo.root, candidate)
    if text.len == 0:
      continue
    result.scanPropertyEnv(candidate, text, "process.env.", documented,
        runtimeConfig.ignoredEnvVars)
    result.scanPropertyEnv(candidate, text, "import.meta.env.", documented,
        runtimeConfig.ignoredEnvVars)
    result.scanQuotedEnv(candidate, text, "Deno.env.get(", documented,
        runtimeConfig.ignoredEnvVars)
    result.scanQuotedEnv(candidate, text, "os.Getenv(", documented,
        runtimeConfig.ignoredEnvVars)
    result.scanQuotedEnv(candidate, text, "std::env::var(", documented,
        runtimeConfig.ignoredEnvVars)
    result.scanQuotedEnv(candidate, text, "System.getenv(", documented,
        runtimeConfig.ignoredEnvVars)
    result.scanQuotedEnv(candidate, text, "ENV[", documented,
        runtimeConfig.ignoredEnvVars)
    result.scanQuotedEnv(candidate, text, "getenv(", documented,
        runtimeConfig.ignoredEnvVars)

proc addPackageScripts(inventory: var CommandInventory; root, file: string) =
  try:
    let parsed = parseJson(safeRead(root, file))
    if parsed.kind == JObject and parsed.hasKey("scripts") and parsed[
        "scripts"].kind == JObject:
      for key in parsed["scripts"].keys:
        inventory.packageScripts[key] = true
  except JsonParsingError, IOError, OSError:
    discard

proc addMakeTargets(inventory: var CommandInventory; root, file: string) =
  for line in safeRead(root, file).splitLines():
    if line.len == 0 or line[0].isSpaceAscii() or line.startsWith("."):
      continue
    let colon = line.find(':')
    if colon > 0 and not line[0 ..< colon].contains("="):
      for target in line[0 ..< colon].splitWhitespace():
        inventory.makeTargets[target] = true

proc addJustTargets(inventory: var CommandInventory; root, file: string) =
  for line in safeRead(root, file).splitLines():
    let trimmed = line.strip()
    if trimmed.len == 0 or trimmed.startsWith("#") or trimmed.startsWith("@") or
        trimmed.startsWith("set "):
      continue
    let name = trimmed.splitWhitespace()[0].split(":")[0]
    if name.len > 0 and name[0].isAlphaAscii():
      inventory.justTargets[name] = true

proc addTaskTargets(inventory: var CommandInventory; root, file: string) =
  var inTasks = false
  for line in safeRead(root, file).splitLines():
    if line.strip() == "tasks:":
      inTasks = true
      continue
    if inTasks:
      if line.len > 0 and not line[0].isSpaceAscii():
        break
      let stripped = line.strip()
      if stripped.endsWith(":") and not stripped.startsWith("-"):
        inventory.taskTargets[stripped[0 .. ^2]] = true

proc commandInventory(root: string; files: openArray[
    string]): CommandInventory =
  for file in files:
    case file.fileName()
    of "package.json":
      result.addPackageScripts(root, file)
    of "Makefile", "makefile":
      result.addMakeTargets(root, file)
    of "justfile", "Justfile":
      result.addJustTargets(root, file)
    of "Taskfile.yml", "Taskfile.yaml":
      result.addTaskTargets(root, file)
    else:
      discard

proc commandTarget(command: string): tuple[kind: string; target: string] =
  let parts = command.strip().splitWhitespace()
  if parts.len == 0:
    return ("", "")
  case parts[0]
  of "npm":
    if parts.len >= 3 and parts[1] == "run":
      return ("package", parts[2])
  of "pnpm":
    if parts.len >= 3 and parts[1] == "run":
      return ("package", parts[2])
    if parts.len >= 2:
      return ("package", parts[1])
  of "bun":
    if parts.len >= 3 and parts[1] == "run":
      return ("package", parts[2])
  of "yarn":
    if parts.len >= 2:
      if parts[1] == "run" and parts.len >= 3:
        return ("package", parts[2])
      return ("package", parts[1])
  of "make":
    if parts.len >= 2:
      return ("make", parts[1])
  of "just":
    if parts.len >= 2:
      return ("just", parts[1])
  of "task":
    if parts.len >= 2:
      return ("task", parts[1])
  else:
    discard
  ("", "")

proc isValid(command: string; inventory: CommandInventory): bool =
  let target = command.commandTarget()
  case target.kind
  of "package":
    inventory.packageScripts.hasKey(target.target)
  of "make":
    inventory.makeTargets.hasKey(target.target)
  of "just":
    inventory.justTargets.hasKey(target.target)
  of "task":
    inventory.taskTargets.hasKey(target.target)
  else:
    true

proc commandPrefix(line: string): string =
  var text = line.strip()
  if text.startsWith("- "):
    text = text[2 .. ^1].strip()
  if text.startsWith("$ "):
    text = text[2 .. ^1].strip()
  text

proc isCommandCandidate(line: string): bool =
  let text = line.commandPrefix()
  for prefix in ["npm run ", "pnpm run ", "pnpm ", "yarn ", "bun run ", "make ",
      "just ", "task "]:
    if text.startsWith(prefix):
      return true
  false

proc scanReadmeCommandDrift(result: var seq[Issue]; plan: ScanPlan;
    inventory: CommandInventory) =
  for file in repositoryFiles(plan):
    if file != "README.md" and not (file.startsWith("docs/") and file.endsWith(".md")):
      continue
    var lineNumber = 0
    var inFence = false
    var shellFence = false
    for line in safeRead(plan.repo.root, file).splitLines():
      inc lineNumber
      let trimmed = line.strip()
      if trimmed.startsWith("```"):
        let lang = trimmed[3 .. ^1].strip().toLowerAscii()
        inFence = not inFence
        shellFence = inFence and (lang in ["", "sh", "shell", "bash", "zsh",
            "console", "terminal"])
        continue
      if (not inFence or shellFence) and line.isCommandCandidate():
        let command = line.commandPrefix()
        if not command.isValid(inventory):
          result.add(commandWarning("readme-command-drift", "docs-drift", file,
              lineNumber, line.find(command.strip()) + 1, command))

proc workflowRunCommands(text: string): seq[tuple[line: int; column: int;
    command: string]] =
  let lines = text.splitLines()
  var i = 0
  while i < lines.len:
    let line = lines[i]
    var stripped = line.strip()
    if stripped.startsWith("- "):
      stripped = stripped[2 .. ^1].strip()
    let runAt = line.find("run:")
    if runAt >= 0 and stripped.startsWith("run:"):
      let after = stripped[4 .. ^1].strip()
      if after in ["|", ">"]:
        inc i
        while i < lines.len and (lines[i].len == 0 or lines[i][0].isSpaceAscii()):
          if lines[i].isCommandCandidate():
            let command = lines[i].commandPrefix()
            result.add((line: i + 1, column: lines[i].find(command.strip()) + 1,
                command: command))
          inc i
        continue
      elif after.len > 0:
        result.add((line: i + 1, column: line.find(after) + 1, command: after))
    inc i

proc scanCiCommandDrift(result: var seq[Issue]; plan: ScanPlan;
    inventory: CommandInventory) =
  for file in repositoryFiles(plan):
    if not (file.startsWith(".github/workflows/") and (file.endsWith(".yml") or
        file.endsWith(".yaml"))):
      continue
    for command in workflowRunCommands(safeRead(plan.repo.root, file)):
      if command.command.isCommandCandidate() and not command.command.isValid(inventory):
        result.add(commandError("ci-command-drift", "ci-drift", file,
            command.line, command.column, command.command))

proc scanPackageLockDrift(result: var seq[Issue]; plan: ScanPlan;
    files: openArray[string]) =
  var fileSet = initTable[string, bool]()
  var candidateSet = initTable[string, bool]()
  for file in files:
    fileSet[file] = true
  for candidate in plan.candidates:
    candidateSet[candidate.normalizeRepoPath()] = true

  for candidate in plan.candidates:
    let file = candidate.normalizeRepoPath()
    if file.fileName() != "package.json":
      continue
    let dir = file.parentDir()
    var found: seq[string]
    for lockfile in NodeLockfiles:
      let lockPath = joinRepoPath(dir, lockfile)
      if fileSet.hasKey(lockPath):
        found.add(lockPath)
    if found.len == 1 and not candidateSet.hasKey(found[0]):
      result.add(packageWarning(file))

proc scanCrossReference*(plan: ScanPlan; runtimeConfig = defaultConfig()): seq[Issue] =
  let files = repositoryFiles(plan)
  let inventory = commandInventory(plan.repo.root, files)
  result.scanEnvDrift(plan, files, runtimeConfig)
  result.scanReadmeCommandDrift(plan, inventory)
  result.scanCiCommandDrift(plan, inventory)
  result.scanPackageLockDrift(plan, files)
  result = result.applyRuleOverrides(runtimeConfig)
