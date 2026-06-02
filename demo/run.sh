#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace="$repo_root/demo/workspace"
scour_bin="$repo_root/scour"
reports_dir="$repo_root/demo/reports"
react_doctor_workspace="$repo_root/demo/react-doctor-workspace"
run_react_doctor=false

if [ "${1:-}" = "--with-react-doctor" ]; then
  run_react_doctor=true
fi

if [ ! -d "$workspace/.git" ]; then
  printf 'Demo workspace is missing. Run `bash demo/install.sh` first.\n' >&2
  exit 1
fi

if [ ! -x "$scour_bin" ]; then
  printf 'Scour binary is missing. Run `bash demo/install.sh` first.\n' >&2
  exit 1
fi

mkdir -p "$reports_dir"

run_scour_capture() {
  local output_file="$1"
  shift
  set +e
  "$scour_bin" "$@" > "$output_file"
  local status=$?
  set -e
  if [ "$status" -gt 1 ]; then
    printf 'Scour command failed: %s\n' "$*" >&2
    exit "$status"
  fi
}

run_scour_value() {
  set +e
  local value
  value=$("$scour_bin" "$@")
  local status=$?
  set -e
  if [ "$status" -gt 1 ]; then
    printf 'Scour command failed: %s\n' "$*" >&2
    exit "$status"
  fi
  printf '%s\n' "$value"
}

extract_summary_fields() {
  local file="$1"
  sed -n 's/.*"summary":{"errors":\([0-9][0-9]*\),"warnings":\([0-9][0-9]*\),"info":\([0-9][0-9]*\),"total":\([0-9][0-9]*\),"files":\([0-9][0-9]*\),"triage":{"blockers":\([0-9][0-9]*\).*/\1 \2 \3 \4 \5 \6/p' "$file"
}

cd "$workspace"

printf '== Scour Doctor demo ==\n\n'
printf '1. Running the full Scour scan on the intentionally broken workspace.\n'
run_scour_capture "$reports_dir/scour-all.json" --all --format json
run_scour_capture "$reports_dir/scour-all.txt" --all
run_scour_capture "$reports_dir/scour-doctor.txt" --all --format doctor
run_scour_capture "$reports_dir/scour-triage.txt" triage --all
run_scour_capture "$reports_dir/scour-rules.txt" rules
run_scour_capture "$reports_dir/explain-env-drift.txt" explain env-drift
run_scour_capture "$reports_dir/explain-ci-command-drift.txt" explain ci-command-drift
run_scour_capture "$reports_dir/explain-merge-conflict.txt" explain merge-conflict

score=$(run_scour_value --all --score)
read -r errors warnings infos total files blockers <<EOF
$(extract_summary_fields "$reports_dir/scour-all.json")
EOF

printf '\n2. Scour Doctor score\n'
printf '   score=%s/100  total=%s  errors=%s  warnings=%s  blockers=%s  files=%s\n' \
  "$score" "$total" "$errors" "$warnings" "$blockers" "$files"
printf '   formula: 100 - (10*errors) - (4*warnings) - (1*info) - (3*blockers)\n'
printf '   source: scour --all --score\n'

printf '\n3. Reports written to %s\n' "$reports_dir"
printf '   - scour-all.txt\n'
printf '   - scour-all.json\n'
printf '   - scour-doctor.txt\n'
printf '   - scour-triage.txt\n'
printf '   - scour-rules.txt\n'
printf '   - explain-env-drift.txt\n'
printf '   - explain-ci-command-drift.txt\n'
printf '   - explain-merge-conflict.txt\n'

printf '\n4. Suggested walkthrough\n'
printf '   - Read scour-doctor.txt first for the React Doctor-style summary.\n'
printf '   - Read scour-triage.txt next for deterministic fix order.\n'
printf '   - Open explain-env-drift.txt to see a blocker with a concrete fix direction.\n'
printf '   - Open explain-ci-command-drift.txt to see docs/CI drift surfaced like a launch gate.\n'
printf '   - Re-run bash demo/run.sh after each fix and watch the score trend upward.\n'

printf '\n5. Linked references\n'
printf '   - Scour launch plan: docs/scour-doctor-launch-plan.md\n'
printf '   - Rule catalog: src/scourpkg/rule_catalog.nim\n'
printf '   - React Doctor docs: https://www.react.doctor/docs\n'
printf '   - React Doctor CLI reference: https://www.react.doctor/docs/reference/cli-reference\n'

if [ "$run_react_doctor" = true ]; then
  if command -v npx >/dev/null 2>&1; then
    if [ ! -f "$react_doctor_workspace/package.json" ]; then
      printf '\n6. React Doctor workspace is missing. Run `bash demo/install.sh` first.\n' >&2
      exit 1
    fi
    printf '\n6. Running optional React Doctor comparison via npx.\n'
    (
      cd "$react_doctor_workspace"
      npx -y react-doctor@latest . --verbose --full
    ) | tee "$reports_dir/react-doctor.txt"
  else
    printf '\n6. Skipped React Doctor comparison because npx is not installed.\n' >&2
    exit 1
  fi
fi
