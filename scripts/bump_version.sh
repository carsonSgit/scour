#!/usr/bin/env bash
# Rewrite the Scour version string everywhere it is hardcoded.
#
# Usage: scripts/bump_version.sh <version>
#   <version> is a bare semantic version without a leading "v", e.g. 0.2.0
#
# Updated locations:
#   - scour.nimble                 version       = "X.Y.Z"
#   - src/scourpkg/help.nim         const version* = "scour X.Y.Z"
#   - src/scourpkg/help.nim         "scour X.Y.Z" inside helpText
set -euo pipefail

version=${1:-}
if [[ -z "$version" ]]; then
  echo "usage: $0 <version> (bare semver, e.g. 0.2.0)" >&2
  exit 1
fi
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: version '$version' is not a bare X.Y.Z semver" >&2
  exit 1
fi

root=$(cd "$(dirname "$0")/.." && pwd)
nimble="$root/scour.nimble"
help="$root/src/scourpkg/help.nim"

# sed -i differs between GNU and BSD/macOS; use a portable in-place wrapper.
sed_inplace() {
  if sed --version >/dev/null 2>&1; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

# scour.nimble: the version assignment line.
sed_inplace -E "s/^version([[:space:]]*)=([[:space:]]*)\"[0-9]+\.[0-9]+\.[0-9]+\"/version\1=\2\"$version\"/" "$nimble"

# help.nim: every "scour X.Y.Z" occurrence (const + helpText banner).
sed_inplace -E "s/scour [0-9]+\.[0-9]+\.[0-9]+/scour $version/g" "$help"

echo "bumped to $version"
grep -E '^version' "$nimble"
grep -E 'scour [0-9]+\.[0-9]+\.[0-9]+' "$help"
