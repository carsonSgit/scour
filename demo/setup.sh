#!/usr/bin/env bash
set -euo pipefail

demo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
workspace="$demo_dir/workspace"

rm -rf "$workspace"
mkdir -p "$workspace"
cp -R "$demo_dir/template/." "$workspace/"

git -C "$workspace" init -q -b demo
git -C "$workspace" config user.name "Scour Demo"
git -C "$workspace" config user.email "scour-demo@example.com"
git -C "$workspace" add .
git -C "$workspace" commit -qm "Create intentionally broken demo project"

cat > "$workspace/staged/package.json" <<'EOF'
{"scripts":{"test":"true"},"description":"staged manifest edit for package-lock-drift"}
EOF
git -C "$workspace" add staged/package.json

printf 'Created demo workspace at %s\n' "$workspace"
