#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
bin="$tmp/bin"
fixtures="$tmp/fixtures"
mkdir -p "$bin" "$fixtures"

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_contains() { grep -F -- "$2" "$1" >/dev/null || fail "$1 missing: $2"; }

make_release() {
  version=$1 target=$2
  dir="$fixtures/scour-$version-$target"
  mkdir -p "$dir"
  printf '#!/bin/sh\necho installed\n' > "$dir/scour"
  chmod +x "$dir/scour"
  tar -czf "$fixtures/scour-$version-$target.tar.gz" -C "$dir" scour
  if command -v sha256sum >/dev/null 2>&1; then
    sum=$(sha256sum "$fixtures/scour-$version-$target.tar.gz" | awk '{print $1}')
  else
    sum=$(shasum -a 256 "$fixtures/scour-$version-$target.tar.gz" | awk '{print $1}')
  fi
  printf '%s  %s\n' "$sum" "scour-$version-$target.tar.gz" >> "$fixtures/scour-$version-checksums.txt"
}

cat > "$bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url=$2
if [[ "$url" == *"/releases/latest" ]]; then
  printf '{"tag_name":"v0.2.0"}\n'
  exit
fi
dest=$4
cp "$FIXTURES/${url##*/}" "$dest"
EOF
chmod +x "$bin/curl"

make_release v0.2.0 linux-x86_64
make_release v0.2.0 macos-aarch64
PATH="$bin:$PATH" FIXTURES="$fixtures" SCOUR_VERSION=0.2.0 \
  SCOUR_INSTALL_DIR="$tmp/install" SCOUR_UNAME_S=Linux SCOUR_UNAME_M=x86_64 \
  "$root/scripts/install.sh"
[[ -x "$tmp/install/scour" ]] || fail "install directory override failed"
PATH="$bin:$PATH" FIXTURES="$fixtures" SCOUR_VERSION=latest \
  SCOUR_INSTALL_DIR="$tmp/latest" SCOUR_UNAME_S=Darwin SCOUR_UNAME_M=arm64 \
  "$root/scripts/install.sh"
[[ -x "$tmp/latest/scour" ]] || fail "latest macOS install failed"

cp "$fixtures/scour-v0.2.0-checksums.txt" "$tmp/checksums"
printf 'bad  scour-v0.2.0-linux-x86_64.tar.gz\n' > "$fixtures/scour-v0.2.0-checksums.txt"
if PATH="$bin:$PATH" FIXTURES="$fixtures" SCOUR_VERSION=v0.2.0 \
  SCOUR_INSTALL_DIR="$tmp/bad" SCOUR_UNAME_S=Linux SCOUR_UNAME_M=x86_64 \
  "$root/scripts/install.sh" 2>"$tmp/bad.err"; then
  fail "bad checksum accepted"
fi
assert_contains "$tmp/bad.err" "checksum verification failed"
cp "$tmp/checksums" "$fixtures/scour-v0.2.0-checksums.txt"
if PATH="$bin:$PATH" FIXTURES="$fixtures" SCOUR_VERSION=v0.2.0 \
  SCOUR_UNAME_S=Plan9 SCOUR_UNAME_M=x86_64 "$root/scripts/install.sh" 2>"$tmp/os.err"; then
  fail "unsupported platform accepted"
fi
assert_contains "$tmp/os.err" "unsupported platform"

action="$tmp/action"
mkdir -p "$action/scripts" "$tmp/action-bin"
cp "$root/scripts/run-action.sh" "$action/scripts/"
cat > "$action/scripts/install.sh" <<'EOF'
#!/usr/bin/env bash
mkdir -p "$SCOUR_INSTALL_DIR"
cp "$FAKE_SCOUR" "$SCOUR_INSTALL_DIR/scour"
chmod +x "$SCOUR_INSTALL_DIR/scour"
EOF
cat > "$tmp/fake-scour" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SCOUR_CALLS"
if [[ " $* " == *" --format json "* ]]; then
  printf '{"summary":{"total":4,"errors":1,"warnings":2,"info":1,"triage":{"blockers":1,"fix_now":1,"review":1,"cleanup":1}}}\n'
elif [[ " $* " == *" triage "* ]]; then
  echo "triage report"
else
  echo "::error file=app.ts,line=1::finding"
  exit 1
fi
EOF
chmod +x "$action/scripts/install.sh" "$tmp/fake-scour"
cat > "$tmp/action-bin/uname" <<'EOF'
#!/bin/sh
echo Linux
EOF
chmod +x "$tmp/action-bin/uname"
export GITHUB_ACTION_PATH="$action" RUNNER_TEMP="$tmp/runner" FAKE_SCOUR="$tmp/fake-scour"
export SCOUR_CALLS="$tmp/calls" GITHUB_OUTPUT="$tmp/output" GITHUB_STEP_SUMMARY="$tmp/summary"
export PATH="$tmp/action-bin:$PATH"
export SCOUR_INPUT_SINCE=main SCOUR_INPUT_STAGED=false SCOUR_INPUT_ALL=false
export SCOUR_INPUT_FORMAT=github SCOUR_INPUT_FAIL_ON=warning SCOUR_INPUT_CONFIG=scour.toml
export SCOUR_INPUT_VERSION=v0.2.0 SCOUR_INPUT_EXIT_ZERO=false SCOUR_INPUT_TRIAGE=true
if "$root/scripts/run-action.sh"; then fail "annotation exit code was not propagated"; fi
assert_contains "$tmp/calls" "--since main --config scour.toml --fail-on warning --format json"
assert_contains "$tmp/output" "total=4"
assert_contains "$tmp/output" "fix-now=1"
assert_contains "$tmp/summary" "triage report"
echo "distribution tests passed"
