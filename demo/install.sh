#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace="$repo_root/demo/workspace"
reports_dir="$repo_root/demo/reports"
react_doctor_workspace="$repo_root/demo/react-doctor-workspace"

printf 'Building scour binary...\n'
cache_dir="${TMPDIR:-/tmp}/scour-demo-nimcache"
rm -rf "$cache_dir"
(cd "$repo_root" && nim c --nimcache:"$cache_dir" -o:"$repo_root/scour" src/scour.nim)

bash "$repo_root/demo/setup.sh"
rm -rf "$reports_dir"
mkdir -p "$reports_dir"
rm -rf "$react_doctor_workspace"
mkdir -p "$react_doctor_workspace"
cp -R "$repo_root/demo/react-doctor-template/." "$react_doctor_workspace/"

printf '\nScour demo workspace is ready.\n'
printf 'Workspace: %s\n' "$workspace"
printf 'React Doctor comparison workspace: %s\n' "$react_doctor_workspace"
printf 'Run the interactive walkthrough with:\n'
printf '  bash demo/run.sh\n'

if command -v npx >/dev/null 2>&1; then
  printf '\nOptional React Doctor integration is available through npx.\n'
  printf 'Run this inside demo/workspace when you want the side-by-side comparison:\n'
  printf '  bash ../run.sh --with-react-doctor\n'
else
  printf '\nReact Doctor integration is optional and requires npx on PATH.\n'
fi
