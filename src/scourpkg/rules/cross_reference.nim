import algorithm, json, os, osproc, sequtils, strutils, tables

import ../config, ../files, ../issues, ../rule_issue, ../scan_plan, ../source_text

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
  WorkspaceTargets = object
    packageScripts: Table[string, bool]
    makeTargets: Table[string, bool]
    justTargets: Table[string, bool]
    taskTargets: Table[string, bool]

  CommandInventory = object
    byDir: Table[string, WorkspaceTargets]
    merged: WorkspaceTargets
    sharedMode: bool

proc yamlUnquote(value: string): string =
  let text = value.strip()
  if text.len >= 2 and ((text[0] == '"' and text[^1] == '"') or
      (text[0] == '\'' and text[^1] == '\'')):
    text[1 ..< text.high]
  else:
    text

proc normalizeRepoPath(path: string): string =
  path.replace('\\', '/')

proc parentDir(path: string): string =
  path.normalizeRepoPath().splitFile.dir.normalizeRepoPath()

proc fileName(path: string): string =
  let split = path.normalizeRepoPath().splitFile
  split.name & split.ext

proc workspaceKey(dir: string): string =
  var trimmed = dir.normalizeRepoPath().strip().replace("./", "")
  trimmed = trimmed.strip(chars = {'/'}, leading = false, trailing = true)
  if trimmed == ".":
    ""
  else:
    trimmed

proc joinRepoPath(dir, name: string): string =
  if dir.len == 0:
    name
  else:
    dir & "/" & name

proc runGit(root: string; args: string): tuple[output: string; exitCode: int] =
  execCmdEx("git -C " & quoteShell(root) & " " & args)

proc repositoryFiles(plan: ScanPlan): seq[string] =
  if plan.repo.isGit:
    let git = runGit(plan.repo.root, "ls-files -z")
    if git.exitCode == 0:
      for line in git.output.split('\0'):
        if line.len > 0:
          result.add(line.normalizeRepoPath())
      result = result.deduplicate()
      result.sort()
      return

  for candidate in plan.candidates:
    result.add(candidate.normalizeRepoPath())
  result = result.deduplicate()
  result.sort()

proc safeRead(root, file: string; mode = scanAll; stats: ScanStats = nil): string =
  if mode != scanStaged:
    let path = root / file
    if not fileExists(path):
      return ""
    try:
      result = readFile(path)
    except IOError, OSError:
      if stats != nil:
        inc(stats.unreadable)
      result = ""
  else:
    let git = runGit(root, "show :\"" & file & "\"")
    if git.exitCode == 0:
      result = git.output

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

type
  EnvDocuments = object
    byDir: Table[string, Table[string, bool]]
    merged: Table[string, bool]

proc loadEnvNames(root: string; files: openArray[string];
    exampleNames: openArray[string]): EnvDocuments =
  for file in files:
    if file.fileName() notin exampleNames:
      continue
    let workspace = workspaceKey(parentDir(file))
    if not result.byDir.hasKey(workspace):
      result.byDir[workspace] = initTable[string, bool]()
    for line in safeRead(root, file).splitLines():
      let trimmed = line.strip()
      if trimmed.len == 0 or trimmed.startsWith("#"):
        continue
      let equals = trimmed.find('=')
      if equals > 0:
        let name = trimmed[0 ..< equals].strip()
        result.byDir[workspace][name] = true
        result.merged[name] = true

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
  let documents = loadEnvNames(plan.repo.root, files,
      runtimeConfig.envExampleFiles)
  for candidate in plan.candidates:
    var documented = documents.merged
    if not runtimeConfig.sharedCommands:
      var workspace = workspaceKey(parentDir(candidate))
      while workspace.len > 0 and not documents.byDir.hasKey(workspace):
        let slash = workspace.find('/')
        workspace = if slash > 0: workspace[0 ..< slash] else: ""
      let directory =
        if documents.byDir.hasKey(workspace): workspace else: ""
      if documents.byDir.hasKey(directory):
        documented = documents.byDir[directory]
  for candidate in plan.candidates:
    var documented = documents.merged
    if not runtimeConfig.sharedCommands:
      var workspace = workspaceKey(parentDir(candidate))
      while workspace.len > 0 and not documents.byDir.hasKey(workspace):
        let slash = workspace.find('/')
        workspace = if slash > 0: workspace[0 ..< slash] else: ""
      let directory =
        if documents.byDir.hasKey(workspace): workspace else: ""
      if documents.byDir.hasKey(directory):
        documented = documents.byDir[directory]
    let text = safeRead(plan.repo.root, candidate, plan.mode, plan.stats)
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

proc touchWorkspace(inventory: var CommandInventory;
    workspace: string): var WorkspaceTargets =
  if not inventory.byDir.hasKey(workspace):
    inventory.byDir[workspace] = WorkspaceTargets()
  result = inventory.byDir[workspace]

proc addPackageScripts(inventory: var CommandInventory; root, file: string;
    mode = scanAll) =
  var parsed: JsonNode
  try:
    parsed = parseJson(safeRead(root, file, mode))
  except JsonParsingError, IOError, OSError:
    return
  if not (parsed.kind == JObject and parsed.hasKey("scripts") and
      parsed["scripts"].kind == JObject):
    return
  let dir = workspaceKey(parentDir(file))
  discard touchWorkspace(inventory, dir)
  for key in parsed["scripts"].keys:
    inventory.byDir[dir].packageScripts[key] = true
    inventory.merged.packageScripts[key] = true

proc addMakeTargets(inventory: var CommandInventory; root, file: string;
    mode = scanAll) =
  var added = false
  var workspace = WorkspaceTargets()
  for line in safeRead(root, file, mode).splitLines():
    if line.len == 0 or line[0].isSpaceAscii() or line.startsWith("."):
      continue
    let colon = line.find(':')
    if colon > 0 and not line[0 ..< colon].contains("="):
      added = true
      for target in line[0 ..< colon].splitWhitespace():
        workspace.makeTargets[target] = true
        inventory.merged.makeTargets[target] = true
  if added:
    let dir = workspaceKey(parentDir(file))
    discard touchWorkspace(inventory, dir)
    for target, _ in workspace.makeTargets:
      inventory.byDir[dir].makeTargets[target] = true

proc addJustTargets(inventory: var CommandInventory; root, file: string;
    mode = scanAll) =
  var added = false
  var workspace = WorkspaceTargets()
  for line in safeRead(root, file, mode).splitLines():
    let trimmed = line.strip()
    if trimmed.len == 0 or trimmed.startsWith("#") or trimmed.startsWith("@") or
        trimmed.startsWith("set "):
      continue
    let name = trimmed.splitWhitespace()[0].split(":")[0]
    if name.len > 0 and name[0].isAlphaAscii():
      added = true
      workspace.justTargets[name] = true
      inventory.merged.justTargets[name] = true
  if added:
    let dir = workspaceKey(parentDir(file))
    discard touchWorkspace(inventory, dir)
    for target, _ in workspace.justTargets:
      inventory.byDir[dir].justTargets[target] = true

proc addTaskTargets(inventory: var CommandInventory; root, file: string;
    mode = scanAll) =
  var inTasks = false
  var added = false
  var workspace = WorkspaceTargets()
  let text = safeRead(root, file, mode)
  for line in text.splitLines():
    if line.strip() == "tasks:":
      inTasks = true
      continue
    if inTasks:
      if line.len > 0 and not line[0].isSpaceAscii():
        if line.strip() != "tasks:":
          break
      let stripped = line.strip()
      if stripped.endsWith(":") and not stripped.startsWith("-"):
        added = true
        workspace.taskTargets[stripped[0 .. ^2]] = true
        inventory.merged.taskTargets[stripped[0 .. ^2]] = true
  if added:
    let dir = workspaceKey(parentDir(file))
    discard touchWorkspace(inventory, dir)
    for target, _ in workspace.taskTargets:
      inventory.byDir[dir].taskTargets[target] = true

proc commandInventory(root: string; files: openArray[string];
    sharedMode = false; mode = scanAll): CommandInventory =
  result.sharedMode = sharedMode
  for file in files:
    case file.fileName()
    of "package.json":
      result.addPackageScripts(root, file, mode)
    of "Makefile", "makefile":
      result.addMakeTargets(root, file, mode)
    of "justfile", "Justfile":
      result.addJustTargets(root, file, mode)
    of "Taskfile.yml", "Taskfile.yaml":
      result.addTaskTargets(root, file, mode)
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

proc isValid(command: string; inventory: CommandInventory;
    workspace = ""): bool =
  let target = command.commandTarget()
  if target.target.contains('$') or target.target.startsWith("~("):
    return true
  if target.kind notin ["package", "make", "just", "task"]:
    return true
  var resolved = inventory.merged
  if not inventory.sharedMode:
    if inventory.byDir.hasKey(workspace):
      resolved = inventory.byDir[workspace]
    elif inventory.byDir.hasKey(""):
      resolved = inventory.byDir[""]
    else:
      resolved = WorkspaceTargets()
  let result = case target.kind
    of "package": resolved.packageScripts.hasKey(target.target)
    of "make": resolved.makeTargets.hasKey(target.target)
    of "just": resolved.justTargets.hasKey(target.target)
    of "task": resolved.taskTargets.hasKey(target.target)
    else: true
  result

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
    for line in safeRead(plan.repo.root, file, plan.mode, plan.stats).splitLines():
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
        if not command.isValid(inventory, workspaceKey(parentDir(file))):
          result.add(commandWarning("readme-command-drift", file,
              lineNumber, line.find(command.strip()) + 1, command))

type PendingCommand* = tuple[line: int; column: int; command: string;
    workingDir: string]

proc yamlWorkingDirectory(lines: seq[string]; runIndex: int): string =
  for index in runIndex + 1 ..< min(runIndex + 12, lines.len):
    let line = lines[index]
    let indent = len(line) - len(line.strip(chars = {' '}))
    if indent == 0 and line.strip().startsWith("- "):
      break
    let colon = line.find(":")
    if colon > 0 and line[0 ..< colon].strip() == "working-directory":
      return yamlUnquote(line[colon + 1 .. ^1])
  ""

proc workflowRunCommands(text: string): seq[PendingCommand] =
  let lines = text.splitLines()
  var i = 0
  while i < lines.len:
    let line = lines[i]
    var stripped = line.strip()
    if stripped.startsWith("- "):
      stripped = stripped[2 .. ^1].strip()
    let runAt = line.find("run:")
    if runAt >= 0 and stripped.startsWith("run:"):
      let after = yamlUnquote(stripped[4 .. ^1])
      if after in ["|", ">"]:
        inc i
        while i < lines.len and (lines[i].len == 0 or lines[i][0].isSpaceAscii()):
          if lines[i].isCommandCandidate():
            let command = lines[i].commandPrefix()
            result.add((line: i + 1, column: lines[i].find(command.strip()) + 1,
                command: command, workingDir: yamlWorkingDirectory(lines, i)))
          inc i
        continue
      elif after.len > 0:
        result.add((line: i + 1, column: line.find(after) + 1, command: after,
            workingDir: yamlWorkingDirectory(lines, i)))
    inc i

proc gitlabScriptCommands(text: string): seq[PendingCommand] =
  let lines = text.splitLines()
  var section = ""
  for index, line in lines:
    let indent = len(line) - len(line.strip(chars = {' '}))
    let trimmed = line.strip()
    for key in ["script:", "before_script:", "after_script:"]:
      if trimmed.startsWith(key):
        section = key[0 ..< key.len - 1]
        break
    if indent == 0 and trimmed.endsWith(":") and trimmed.len > 1:
      section = ""
    if section.len == 0:
      continue
    if not trimmed.startsWith("- "):
      continue
    var command = trimmed[2 .. ^1]
    if command.startswith("|") or command.startswith(">"):
      continue
    command = yamlUnquote(command)
    var workingDir = ""
    let parts = command.splitWhitespace()
    if parts.len >= 4 and parts[0] == "cd" and (parts[2] == "&&" or
        parts[2] == ";"):
      workingDir = workspaceKey(parts[1])
      if parts.len > 4:
        command = yamlUnquote(parts[3 .. ^1].join(" "))
      else:
        continue
    if command.len == 0 or not command.isCommandCandidate():
      continue
    result.add((line: index + 1, column: line.find(command.strip()) + 1,
        command: command, workingDir: workingDir))

proc scanCiCommandDrift(result: var seq[Issue]; plan: ScanPlan;
    inventory: CommandInventory) =
  for file in repositoryFiles(plan):
    let pending =
      if file.startsWith(".github/workflows/") and (file.endsWith(".yml") or
          file.endsWith(".yaml")):
        workflowRunCommands(safeRead(plan.repo.root, file, plan.mode, plan.stats))
      elif file == ".gitlab-ci.yml":
        gitlabScriptCommands(safeRead(plan.repo.root, file, plan.mode, plan.stats))
      else:
        @[]
    for command in pending:
      if command.command.isCommandCandidate() and not command.command.isValid(
          inventory, workspaceKey(command.workingDir)):
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
    for line in safeRead(plan.repo.root, file, plan.mode, plan.stats).splitLines():
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
  for candidate in plan.selectedFiles:
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
  for candidate in plan.selectedFiles:
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
  let contextFiles =
    if plan.repo.isGit: files
    else: collectCandidates(plan.repo, scanAll, CliOptions()).files
  let inventory = commandInventory(plan.repo.root, contextFiles,
      runtimeConfig.sharedCommands, plan.mode)
  result.scanEnvDrift(plan, contextFiles, runtimeConfig)
  result.scanReadmeCommandDrift(plan, inventory)
  result.scanCiCommandDrift(plan, inventory)
  result.scanUnpinnedGithubActions(plan)
  result.scanPackageLockDrift(plan, contextFiles)
  result.scanDependencyLockDrift(plan, contextFiles)
  result = result.filterIt(passesConfiguredFilters(plan.repo.root, it.file, runtimeConfig))
  result = result.applyRuleOverrides(runtimeConfig)
