import algorithm, json, os, osproc, sequtils, strutils, tables

import ../config, ../issues, ../rule_issue, ../scan_plan, ../source_text

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

proc envError(file: string; line, column: int; name: string): Issue =
  newRuleIssue(
    "env-drift",
    file,
    "Environment variable " & name & " is used but absent from env example files.",
    line,
    column
  )

proc commandWarning(ruleId, file: string; line, column: int;
    command: string): Issue =
  newRuleIssue(
    ruleId,
    file,
    "Command `" & command & "` references a missing script or task target.",
    line,
    column
  )

proc commandError(ruleId, file: string; line, column: int;
    command: string): Issue =
  newRuleIssue(
    ruleId,
    file,
    "Command `" & command & "` references a missing script or task target.",
    line,
    column
  )

proc packageWarning(file: string): Issue =
  newRuleIssue(
    "package-lock-drift",
    file,
    "package.json changed without its existing Node lockfile."
  )

proc dependencyWarning(file, lockfile: string): Issue =
  newRuleIssue(
    "dependency-lock-drift",
    file,
    file.fileName() & " changed without its existing " & lockfile.fileName() & "."
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
    file, text, code, prefix: string;
    documented: Table[string, bool];
    ignoredNames: openArray[string]
) =
  var searchFrom = 0
  while true:
    let index = code.find(prefix, searchFrom)
    if index < 0:
      break
    let nameStart = index + prefix.len
    var nameEnd = nameStart
    if nameStart < code.len and code[nameStart].isEnvStart():
      while nameEnd < code.len and code[nameEnd].isEnvPart():
        inc nameEnd
      result.addEnvIssue(file, text, code[nameStart ..< nameEnd], index,
          documented, ignoredNames)
    searchFrom = max(index + 1, nameEnd)

proc scanQuotedEnv(
    result: var seq[Issue];
    file, text, code, prefix: string;
    documented: Table[string, bool];
    ignoredNames: openArray[string]
) =
  var searchFrom = 0
  while true:
    let index = text.find(prefix, searchFrom)
    if index < 0:
      break
    let quoteIndex = index + prefix.len
    let prefixIsCode = index + prefix.len <= code.len and
        code[index ..< index + prefix.len] == prefix
    if not prefixIsCode or quoteIndex >= text.len or text[quoteIndex] notin ['"', '\'']:
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
    let code = text.maskedSourceText(candidate)
    case candidate.extension()
    of ".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs", ".mts", ".cts":
      result.scanPropertyEnv(candidate, text, code, "process.env.", documented,
          runtimeConfig.ignoredEnvVars)
      result.scanPropertyEnv(candidate, text, code, "import.meta.env.", documented,
          runtimeConfig.ignoredEnvVars)
      result.scanQuotedEnv(candidate, text, code, "process.env[", documented,
          runtimeConfig.ignoredEnvVars)
      result.scanQuotedEnv(candidate, text, code, "import.meta.env[", documented,
          runtimeConfig.ignoredEnvVars)
      result.scanQuotedEnv(candidate, text, code, "Deno.env.get(", documented,
          runtimeConfig.ignoredEnvVars)
    of ".py":
      result.scanQuotedEnv(candidate, text, code, "os.getenv(", documented,
          runtimeConfig.ignoredEnvVars)
      result.scanQuotedEnv(candidate, text, code, "os.environ.get(", documented,
          runtimeConfig.ignoredEnvVars)
      result.scanQuotedEnv(candidate, text, code, "os.environ[", documented,
          runtimeConfig.ignoredEnvVars)
    of ".go":
      result.scanQuotedEnv(candidate, text, code, "os.Getenv(", documented,
          runtimeConfig.ignoredEnvVars)
      result.scanQuotedEnv(candidate, text, code, "os.LookupEnv(", documented,
          runtimeConfig.ignoredEnvVars)
    of ".rs":
      result.scanQuotedEnv(candidate, text, code, "std::env::var(", documented,
          runtimeConfig.ignoredEnvVars)
    of ".java", ".kt", ".kts":
      result.scanQuotedEnv(candidate, text, code, "System.getenv(", documented,
          runtimeConfig.ignoredEnvVars)
    of ".cs":
      result.scanQuotedEnv(candidate, text, code, "Environment.GetEnvironmentVariable(",
          documented, runtimeConfig.ignoredEnvVars)
    of ".rb":
      result.scanQuotedEnv(candidate, text, code, "ENV[", documented,
          runtimeConfig.ignoredEnvVars)
    of ".c", ".cc", ".cpp", ".cxx", ".h", ".hpp", ".php":
      result.scanQuotedEnv(candidate, text, code, "getenv(", documented,
          runtimeConfig.ignoredEnvVars)
    else:
      discard

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
    if parts.len >= 2 and parts[1] notin ["add", "audit", "ci", "create",
        "dlx", "exec", "fetch", "import", "init", "install", "i", "link",
        "list", "outdated", "pack", "patch", "prune", "publish", "rebuild",
        "remove", "setup", "store", "update", "why"]:
      return ("package", parts[1])
  of "bun":
    if parts.len >= 3 and parts[1] == "run":
      return ("package", parts[2])
  of "yarn":
    if parts.len >= 2:
      if parts[1] == "run" and parts.len >= 3:
        return ("package", parts[2])
      if parts[1] notin ["add", "audit", "cache", "config", "create", "dlx",
          "exec", "import", "info", "init", "install", "link", "list", "pack",
          "publish", "remove", "set", "unplug", "upgrade", "version", "why"]:
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
  let target = line.commandPrefix().commandTarget()
  target.kind.len > 0

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
          result.add(commandWarning("readme-command-drift", file,
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
        result.add(commandError("ci-command-drift", file,
            command.line, command.column, command.command))

proc isCommitSha(value: string): bool =
  if value.len != 40:
    return false
  for ch in value:
    if not ((ch >= '0' and ch <= '9') or (ch >= 'a' and ch <= 'f') or
        (ch >= 'A' and ch <= 'F')):
      return false
  true

proc scanUnpinnedGithubActions(result: var seq[Issue]; plan: ScanPlan) =
  for file in repositoryFiles(plan):
    if not (file.startsWith(".github/workflows/") and
        (file.endsWith(".yml") or file.endsWith(".yaml"))):
      continue
    var lineNumber = 0
    for line in safeRead(plan.repo.root, file).splitLines():
      inc lineNumber
      var text = line.strip()
      if text.startsWith("- "):
        text = text[2 .. ^1].strip()
      if not text.startsWith("uses:"):
        continue
      if text.len <= 5:
        continue
      var reference = text[5 .. ^1].strip()
      if reference.len == 0:
        continue
      if reference.len >= 2 and reference[0] in {'\'', '"'} and
          reference[^1] == reference[0]:
        reference = reference[1 ..< reference.high]
      else:
        reference = reference.splitWhitespace()[0]
        reference = reference.strip(chars = {'\'', '"'})
      if reference.startsWith("./") or reference.startsWith("docker://"):
        continue
      let separator = reference.rfind('@')
      if separator <= 0 or separator == reference.high:
        continue
      let revision = reference[separator + 1 .. ^1]
      if not revision.isCommitSha():
        result.add(newRuleIssue(
          "unpinned-github-action",
          file,
          "GitHub Action `" & reference & "` is not pinned to a full commit SHA.",
          lineNumber,
          line.find(reference) + 1
        ))

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

proc dependencyLockfiles(manifest: string): seq[string] =
  case manifest
  of "Cargo.toml": @["Cargo.lock"]
  of "Gemfile": @["Gemfile.lock"]
  of "composer.json": @["composer.lock"]
  of "go.mod": @["go.sum"]
  of "mix.exs": @["mix.lock"]
  of "pyproject.toml": @["poetry.lock", "uv.lock", "pdm.lock"]
  else: @[]

proc scanDependencyLockDrift(result: var seq[Issue]; plan: ScanPlan;
    files: openArray[string]) =
  var fileSet = initTable[string, bool]()
  var candidateSet = initTable[string, bool]()
  for file in files:
    fileSet[file] = true
  for candidate in plan.candidates:
    candidateSet[candidate.normalizeRepoPath()] = true

  for candidate in plan.candidates:
    let file = candidate.normalizeRepoPath()
    let lockfiles = file.fileName().dependencyLockfiles()
    if lockfiles.len == 0:
      continue
    let dir = file.parentDir()
    var existing: seq[string]
    for lockfile in lockfiles:
      let lockPath = joinRepoPath(dir, lockfile)
      if fileSet.hasKey(lockPath):
        existing.add(lockPath)
    if existing.len == 1 and not candidateSet.hasKey(existing[0]):
      result.add(dependencyWarning(file, existing[0]))

proc scanCrossReference*(plan: ScanPlan; runtimeConfig = defaultConfig()): seq[Issue] =
  let files = repositoryFiles(plan)
  let inventory = commandInventory(plan.repo.root, files)
  result.scanEnvDrift(plan, files, runtimeConfig)
  result.scanReadmeCommandDrift(plan, inventory)
  result.scanCiCommandDrift(plan, inventory)
  result.scanUnpinnedGithubActions(plan)
  result.scanPackageLockDrift(plan, files)
  result.scanDependencyLockDrift(plan, files)
  result = result.applyRuleOverrides(runtimeConfig)
