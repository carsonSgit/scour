import os, strutils

import ../config, ../issues, ../scan_plan

const
  JsTsExtensions = [".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs", ".mts", ".cts"]
  TsExtensions = [".ts", ".tsx", ".mts", ".cts"]

type
  LineRule = object
    id: string
    message: string
    patterns: seq[string]

proc hasExtension(path: string; extensions: openArray[string]): bool =
  let extension = path.splitFile.ext.toLowerAscii()
  extension in extensions

proc isJsTs(path: string): bool =
  hasExtension(path, JsTsExtensions)

proc isTs(path: string): bool =
  hasExtension(path, TsExtensions)

proc isFullLineComment(line: string): bool =
  let trimmed = line.strip(leading = true, trailing = false)
  trimmed.startsWith("//") or trimmed.startsWith("#") or
    trimmed.startsWith("*") or trimmed.startsWith("<!--")

proc issue(ruleId, file: string; lineNumber, column: int; message: string): Issue =
  Issue(
    ruleId: ruleId,
    severity: severityError,
    category: "hygiene",
    triage: triageFixNow,
    file: file,
    line: lineNumber,
    column: column,
    message: message
  )

proc addFirstPatternIssue(
    result: var seq[Issue];
    file, line: string;
    lineNumber: int;
    rule: LineRule
) =
  for pattern in rule.patterns:
    let column = line.find(pattern)
    if column >= 0:
      result.add(issue(rule.id, file, lineNumber, column + 1, rule.message))
      return

proc scanMergeConflict(result: var seq[Issue]; file, line: string; lineNumber: int) =
  for marker in ["<<<<<<<", "=======", ">>>>>>>"]:
    let column = line.find(marker)
    if column == 0:
      result.add(issue(
        "merge-conflict",
        file,
        lineNumber,
        column + 1,
        "Merge conflict marker found."
      ))
      return

proc scanBranchHygiene*(plan: ScanPlan; runtimeConfig = defaultConfig()): seq[Issue] =
  let focusedTest = LineRule(
    id: "focused-test",
    message: "Focused test left in source.",
    patterns: @["describe.only", "it.only", "test.only", "context.only", "fdescribe", "fit"]
  )
  let skippedTest = LineRule(
    id: "skipped-test",
    message: "Skipped test left in source.",
    patterns: @["describe.skip", "it.skip", "test.skip", "context.skip", "xdescribe", "xit"]
  )

  for candidate in plan.candidates:
    let path = plan.repo.root / candidate
    if not fileExists(path):
      continue

    let jsTs = candidate.isJsTs()
    let ts = candidate.isTs()
    var lineNumber = 0
    for line in readFile(path).splitLines():
      inc lineNumber

      result.scanMergeConflict(candidate, line, lineNumber)

      if jsTs and not line.isFullLineComment():
        let debuggerColumn = line.find("debugger;")
        if debuggerColumn >= 0:
          result.add(issue(
            "debugger",
            candidate,
            lineNumber,
            debuggerColumn + 1,
            "Debugger statement found."
          ))

        if runtimeConfig.rules.consoleLog:
          let consoleColumn = line.find("console.log(")
          if consoleColumn >= 0:
            result.add(issue(
              "console-log",
              candidate,
              lineNumber,
              consoleColumn + 1,
              "console.log call found."
            ))

        result.addFirstPatternIssue(candidate, line, lineNumber, focusedTest)
        result.addFirstPatternIssue(candidate, line, lineNumber, skippedTest)

      if ts:
        let tsIgnoreColumn = line.find("@ts-ignore")
        if tsIgnoreColumn >= 0:
          result.add(issue(
            "ts-ignore",
            candidate,
            lineNumber,
            tsIgnoreColumn + 1,
            "@ts-ignore suppression found."
          ))
