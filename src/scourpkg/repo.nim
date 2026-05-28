import os, osproc, strutils

import errors, scan_plan

proc gitRoot(): string =
  let git = execCmdEx("git rev-parse --show-toplevel")
  if git.exitCode == 0:
    git.output.strip()
  else:
    ""

proc discoverRepo*(): RepoContext =
  let root = gitRoot()
  if root.len > 0:
    RepoContext(root: root, isGit: true)
  else:
    RepoContext(root: getCurrentDir(), isGit: false)

proc discoverConfig*(repo: RepoContext; explicitPath: string): ConfigDiscovery =
  if explicitPath.len > 0:
    let fullPath =
      if explicitPath.isAbsolute: explicitPath
      else: normalizedPath(repo.root / explicitPath)
    if not fileExists(fullPath):
      fatal("config file not found: " & explicitPath)
    return ConfigDiscovery(path: fullPath, isExplicit: true)

  for name in ["scour.toml", ".scour.toml", ".config/scour.toml"]:
    let candidate = repo.root / name
    if fileExists(candidate):
      return ConfigDiscovery(path: candidate, isExplicit: false)

  ConfigDiscovery(path: "", isExplicit: false)
