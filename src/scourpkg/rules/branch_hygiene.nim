import os, strutils

import ../config, ../issues, ../rule_issue, ../scan_plan
import ../source_text

type
  LineRule = object
    id: string
    message: string
    patterns: seq[string]

proc addFirstPatternIssue(result: var seq[Issue]; file, code: string;
    lineNumber: int; rule: LineRule) =
  for pattern in rule.patterns:
    let column = code.find(pattern)
    if column >= 0:
      result.add(newRuleIssue(rule.id, file, rule.message, lineNumber, column + 1))
      return

proc scanMergeConflict(result: var seq[Issue]; file, line: string;
    lineNumber: int) =
  for marker in ["<<<<<<<", "=======", ">>>>>>>"]:
    if line.startsWith(marker):
      result.add(newRuleIssue("merge-conflict", file,
          "Merge conflict marker found.", lineNumber, 1))
      return

proc isTestPath(path: string): bool =
  let normalized = path.replace('\\', '/').toLowerAscii()
  let name = normalized.splitFile.name
  name.endsWith("test") or name.endsWith("tests") or name.endsWith("spec") or
      "/test/" in normalized or "/tests/" in normalized or
      "/spec/" in normalized or "/specs/" in normalized

proc debuggerRule(path: string): LineRule =
  case path.extension()
  of ".py":
    LineRule(id: "debugger", message: "Debugger breakpoint found.",
      patterns: @["breakpoint(", "pdb.set_trace(", "ipdb.set_trace("])
  of ".rb":
    LineRule(id: "debugger", message: "Debugger breakpoint found.",
      patterns: @["binding.pry", "byebug"])
  of ".php":
    LineRule(id: "debugger", message: "Debugger breakpoint found.",
      patterns: @["xdebug_break("])
  else:
    LineRule(id: "debugger", message: "Debugger statement found.",
      patterns: @["debugger;"])

proc skippedTestRule(path: string): LineRule =
  case path.extension()
  of ".py":
    LineRule(id: "skipped-test", message: "Skipped test left in source.",
      patterns: @["@pytest.mark.skip", "@unittest.skip(", "pytest.skip("])
  of ".rb":
    LineRule(id: "skipped-test", message: "Skipped test left in source.",
      patterns: @["xdescribe ", "xcontext ", "xit "])
  of ".go":
    LineRule(id: "skipped-test", message: "Skipped test left in source.",
      patterns: @[".Skip(", ".Skipf(", ".SkipNow("])
  of ".rs":
    LineRule(id: "skipped-test", message: "Ignored test left in source.",
      patterns: @["#[ignore]"])
  of ".java", ".kt", ".kts":
    LineRule(id: "skipped-test", message: "Disabled test left in source.",
      patterns: @["@Disabled", "@Ignore"])
  of ".cs":
    LineRule(id: "skipped-test", message: "Ignored test left in source.",
      patterns: @["[Ignore(", "[Ignore]"])
  else:
    LineRule(id: "skipped-test", message: "Skipped test left in source.",
      patterns: @["describe.skip", "it.skip", "test.skip", "context.skip",
          "xdescribe(", "xit("])

proc focusedTestRule(path: string): LineRule =
  if path.extension() == ".rb":
    LineRule(id: "focused-test", message: "Focused test left in source.",
      patterns: @["fdescribe ", "fcontext ", "fit "])
  else:
    LineRule(id: "focused-test", message: "Focused test left in source.",
      patterns: @["describe.only", "it.only", "test.only", "context.only",
          "fdescribe(", "fit("])

proc scanBranchHygiene*(plan: ScanPlan; runtimeConfig = defaultConfig()): seq[Issue] =
  for candidate in plan.candidates:
    let path = plan.repo.root / candidate
    if not fileExists(path):
      continue

    let kind = candidate.sourceLexKind()
    let jsTs = candidate.hasExtension(JsTsExtensions)
    let ts = candidate.hasExtension(TsExtensions)
    let testFile = candidate.isTestPath()
    var state: SourceLexState
    var lineNumber = 0
    for line in readFile(path).splitLines():
      inc lineNumber
      result.scanMergeConflict(candidate, line, lineNumber)
      let code = line.maskSourceLine(kind, state)

      let debugger = candidate.debuggerRule()
      if debugger.patterns.len > 0:
        result.addFirstPatternIssue(candidate, code, lineNumber, debugger)

      if jsTs:
        if not runtimeConfig.ruleIsOff("console-log"):
          let consoleColumn = code.find("console.log(")
          if consoleColumn >= 0:
            result.add(newRuleIssue("console-log", candidate,
                "console.log call found.", lineNumber, consoleColumn + 1))
        result.addFirstPatternIssue(candidate, code, lineNumber,
            candidate.focusedTestRule())
        result.addFirstPatternIssue(candidate, code, lineNumber,
            candidate.skippedTestRule())
      elif testFile:
        if candidate.extension() == ".rb":
          result.addFirstPatternIssue(candidate, code, lineNumber,
              candidate.focusedTestRule())
        result.addFirstPatternIssue(candidate, code, lineNumber,
            candidate.skippedTestRule())

      if ts:
        let trimmed = line.strip(leading = true, trailing = false)
        let tsIgnoreColumn = line.find("@ts-ignore")
        if trimmed.startsWith("//") and tsIgnoreColumn >= 0:
          result.add(newRuleIssue("ts-ignore", candidate,
              "@ts-ignore suppression found.", lineNumber, tsIgnoreColumn + 1))

  result = result.applyRuleOverrides(runtimeConfig)
