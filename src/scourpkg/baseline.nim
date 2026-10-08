import os, std/json, std/os, std/sequtils, std/sets, std/strutils, std/tables

import config, errors, issues, scan_plan

type
  Suppression* = object
    rule*: string
    file*: string
    line*: int
    reason*: string
    expires*: string

proc isExpiredYmd*(expires: string; today: string): bool =
  ## True when the expiry date is at or before today (ISO YYYY-MM-DD).
  ## A missing expiry means the suppression never expires.
  if expires.len == 0:
    return false
  if not (expires.len == 10 and expires[4] == '-' and expires[7] == '-'):
    fatal("suppression expiry must be an ISO date such as 2027-12-31")
  let expired = expires <= today
  expired

proc suppressionApplies*(suppression: config.Suppression; issue: Issue): bool =
  if suppression.rule != issue.ruleId:
    return false
  if suppression.file.len > 0 and suppression.file != issue.file:
    return false
  if suppression.line > 0 and suppression.line != issue.line:
    return false
  true

type
  BaselineFile = object
    version*: int
    ids*: seq[string]

proc parseBaseline(path: string): BaselineFile =
  let content =
    try:
      readFile(path)
    except IOError, OSError:
      fatal("baseline file not readable: " & path)
  var parsed: JsonNode
  try:
    parsed = parseJson(content)
  except JsonParsingError:
    fatal("baseline file is not valid JSON: " & path)
  if parsed.kind != JObject or not parsed.hasKey("version") or
      parsed["version"].getInt() != 1 or not parsed.hasKey("findings"):
    fatal("baseline file format mismatch: " & path)
  if parsed["findings"].kind != JArray:
    fatal("baseline findings must be strings: " & path)
  for item in parsed["findings"]:
    if item.kind != JString:
      fatal("baseline findings must be strings: " & path)
  BaselineFile(version: 1, ids: parsed["findings"].mapIt(it.getStr()))

proc writeBaselineFile*(path: string; issues: seq[Issue]) =
  var ids: seq[string] = @[]
  var seenIds = initTable[string, int]()
  for issue in issues:
    var item = issue
    item.findingId = stableFindingId(item, seenIds)
    ids.add(item.findingId)
  let content = %*{"version": 1, "findings": ids}
  try:
    writeFile(path, $content & "\n")
  except IOError, OSError:
    fatal("cannot write baseline to " & path)

proc loadBaselineIds*(path: string): seq[string] =
  let baseline = parseBaseline(path)
  baseline.ids

proc applyBaseline*(issues: seq[Issue]; baselineIds: seq[string]): tuple[
    active: seq[Issue], suppressed: int] =
  let known = baselineIds.toHashSet()
  for issue in issues:
    var item = issue
    var seen = initTable[string, int]()
    item.findingId = stableFindingId(item, seen)
    if item.findingId in known:
      inc result.suppressed
    else:
      result.active.add(item)
