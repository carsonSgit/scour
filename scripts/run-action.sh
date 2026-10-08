#!/usr/bin/env bash
set -uo pipefail

die() { echo "scour action: $*" >&2; exit 2; }
boolean() { [[ "$2" == "true" || "$2" == "false" ]] || die "$1 must be true or false"; }
fatype() {
  case "$1" in none|preview|apply) return 0;; *) return 1;; esac
}

[[ "$(uname -s)" == Linux ]] || die "the Scour Action supports Linux runners only"
boolean staged "${SCOUR_INPUT_STAGED:-false}"
boolean all "${SCOUR_INPUT_ALL:-false}"
boolean exit-zero "${SCOUR_INPUT_EXIT_ZERO:-false}"
boolean triage "${SCOUR_INPUT_TRIAGE:-false}"
fatype "${SCOUR_INPUT_FIX:-none}" || die "fix must be none, preview, or apply"

selectors=0
[[ -n "${SCOUR_INPUT_SINCE:-}" ]] && ((selectors+=1))
[[ "${SCOUR_INPUT_STAGED:-false}" == true ]] && ((selectors+=1))
[[ "${SCOUR_INPUT_ALL:-false}" == true ]] && ((selectors+=1))
(( selectors <= 1 )) || die "since, staged, and all cannot be combined"

install_dir="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/scour-bin"
SCOUR_VERSION="${SCOUR_INPUT_VERSION:-latest}" SCOUR_INSTALL_DIR="$install_dir" \
  "$GITHUB_ACTION_PATH/scripts/install.sh"
scour="$install_dir/scour"
args=()
[[ -n "${SCOUR_INPUT_SINCE:-}" ]] && args+=(--since "$SCOUR_INPUT_SINCE")
[[ "${SCOUR_INPUT_STAGED:-false}" == true ]] && args+=(--staged)
[[ "${SCOUR_INPUT_ALL:-false}" == true ]] && args+=(--all)
[[ -n "${SCOUR_INPUT_CONFIG:-}" ]] && args+=(--config "$SCOUR_INPUT_CONFIG")
[[ -n "${SCOUR_INPUT_FAIL_ON:-}" ]] && args+=(--fail-on "$SCOUR_INPUT_FAIL_ON")
[[ "${SCOUR_INPUT_EXIT_ZERO:-false}" == true ]] && args+=(--exit-zero)

fix_mode="${SCOUR_INPUT_FIX:-none}"
case "$fix_mode" in
  preview) args+=(--fix);;
  apply) args+=(--fix-apply);;
esac

report_dir="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/scour-reports"
mkdir -p "$report_dir"
before_path="$report_dir/scan-before.json"
patch_path="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/scour-fix.patch"
after_path=""
fixed=0 remaining=0 unfixable=0

scan_status=0
"$scour" "${args[@]}" --format json > "$before_path" 2> "$report_dir/scan-before.stderr" || scan_status=$?
json=$(cat "$before_path" 2>/dev/null || echo "{}")
[[ "$json" == *"summary"* ]] || json='{"summary":{"total":0,"errors":0,"warnings":0,"info":0,"triage":{"blockers":0,"fix_now":0,"review":0,"cleanup":0,"ignored":0}},"issues":[]}'

{
  echo "total=$(jq -r '.summary.total' <<<"$json")"
  echo "errors=$(jq -r '.summary.errors' <<<"$json")"
  echo "warnings=$(jq -r '.summary.warnings' <<<"$json")"
  echo "info=$(jq -r '.summary.info' <<<"$json")"
  echo "blockers=$(jq -r '.summary.triage.blockers' <<<"$json")"
  echo "fix-now=$(jq -r '.summary.triage.fix_now' <<<"$json")"
  echo "review=$(jq -r '.summary.triage.review' <<<"$json")"
  echo "cleanup=$(jq -r '.summary.triage.cleanup' <<<"$json")"
  echo "json<<SCOUR_JSON"
  printf '%s\n' "$json"
  echo "SCOUR_JSON"
  echo "patch-path=$patch_path"
  echo "before-path=$before_path"
  echo "after-path=$after_path"
  echo "fixed=$fixed"
  echo "remaining=$remaining"
  echo "unfixable=$unfixable"
} >> "$GITHUB_OUTPUT"

status=0
if [[ "$fix_mode" == apply ]]; then
  "$scour" "${args[@]}" --format github > "$report_dir/scan-after.properties" 2>&1 || scan_status=$?
  "$scour" "${args[@]}" --format json > "$after_path" 2>> "$report_dir/scan-after.stderr" || scan_status=$?
  fixed=$(jq -r '.summary.total' < "$before_path")
  after=$(jq -r '.summary.total' < "$after_path" 2>/dev/null || echo 0)
  remaining=$(( after + 0 ))
  unfixable=0
  if [[ "$scan_status" == 2 ]]; then
    status=2
  elif [[ "$scan_status" != 0 ]]; then
    [[ "$remaining" -gt 0 ]] && status=1
  fi
  sed -i "s|after-path=$after|after-path=$report_dir/scan-after.json|" "$GITHUB_OUTPUT" 2>/dev/null || true
elif [[ "$fix_mode" == preview ]]; then
  # The patch already exists (written by --fix). Copy it out of the checkout.
  cp "$PWD/scour-fix.patch" "$patch_path" 2>/dev/null || status=2
fi

if [[ "$fix_mode" != apply ]]; then
  "$scour" "${args[@]}" --format "${SCOUR_INPUT_FORMAT:-github}" || status=$?
fi
if [[ "${SCOUR_INPUT_TRIAGE:-false}" == true ]]; then
  {
    echo "## Scour triage"
    echo '```text'
    "$scour" triage "${args[@]}" --exit-zero
    echo '```'
  } >> "$GITHUB_STEP_SUMMARY"
fi
exit "$status"
