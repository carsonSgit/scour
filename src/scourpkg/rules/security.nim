import os, strutils

import ../config, ../issues, ../rule_issue, ../scan_plan

proc isCredentialChar(ch: char): bool =
  ch.isAlphaNumeric() or ch in {'_', '-', '.'}

proc prefixedCredential(line, prefix: string; minimumTail: int): int =
  var searchFrom = 0
  while searchFrom < line.len:
    let index = line.find(prefix, searchFrom)
    if index < 0:
      return -1
    var tail = index + prefix.len
    while tail < line.len and line[tail].isCredentialChar():
      inc tail
    let hasBoundaryBefore = index == 0 or not line[index - 1].isCredentialChar()
    let hasEnoughTail = tail - (index + prefix.len) >= minimumTail
    if hasBoundaryBefore and hasEnoughTail:
      return index
    searchFrom = index + prefix.len
  -1

proc awsAccessKey(line: string): int =
  var searchFrom = 0
  while searchFrom < line.len:
    let index = line.find("AKIA", searchFrom)
    if index < 0:
      return -1
    let tokenEnd = index + 20
    var valid = tokenEnd <= line.len and
        (index == 0 or not line[index - 1].isAlphaNumeric()) and
        (tokenEnd == line.len or not line[tokenEnd].isAlphaNumeric())
    if valid:
      for position in index + 4 ..< tokenEnd:
        if not (line[position].isUpperAscii() or line[position].isDigit()):
          valid = false
          break
    if valid:
      return index
    searchFrom = index + 4
  -1

proc credentialSignature(line: string): tuple[index: int; kind: string] =
  let privateKey = line.find("PRIVATE KEY-----")
  if privateKey > 0 and "-----BEGIN " in line[0 ..< privateKey]:
    return (line.find("-----BEGIN "), "private key")

  for signature in [
    (prefix: "github_pat_", tail: 22, kind: "GitHub token"),
    (prefix: "ghp_", tail: 30, kind: "GitHub token"),
    (prefix: "gho_", tail: 30, kind: "GitHub token"),
    (prefix: "ghu_", tail: 30, kind: "GitHub token"),
    (prefix: "ghs_", tail: 30, kind: "GitHub token"),
    (prefix: "ghr_", tail: 30, kind: "GitHub token"),
    (prefix: "xoxb-", tail: 20, kind: "Slack token"),
    (prefix: "xoxp-", tail: 20, kind: "Slack token"),
    (prefix: "sk_live_", tail: 20, kind: "Stripe secret key"),
    (prefix: "AIza", tail: 30, kind: "Google API key"),
    (prefix: "SG.", tail: 30, kind: "SendGrid API key")
  ]:
    let index = line.prefixedCredential(signature.prefix, signature.tail)
    if index >= 0:
      return (index, signature.kind)

  let aws = line.awsAccessKey()
  if aws >= 0:
    return (aws, "AWS access key")
  (-1, "")

proc scanHardcodedSecrets(result: var seq[Issue]; plan: ScanPlan) =
  for candidate in plan.candidates:
    let path = plan.repo.root / candidate
    if not fileExists(path):
      continue
    var lineNumber = 0
    for line in readFile(path).splitLines():
      inc lineNumber
      let signature = line.credentialSignature()
      if signature.index >= 0:
        result.add(newRuleIssue(
          "hardcoded-secret",
          candidate,
          signature.kind & " appears to be committed in plaintext.",
          lineNumber,
          signature.index + 1
        ))

proc scanSecurity*(plan: ScanPlan; runtimeConfig = defaultConfig()): seq[Issue] =
  result.scanHardcodedSecrets(plan)
  result = result.applyRuleOverrides(runtimeConfig)
