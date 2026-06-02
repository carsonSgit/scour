#!/usr/bin/env bash
set -euo pipefail

die() { echo "scour action: $*" >&2; exit 2; }
boolean() { [[ "$2" == "true" || "$2" == "false" ]] || die "$1 must be true or false"; }

[[ "$(uname -s)" == Linux ]] || die "the Scour Action supports Linux runners only"
boolean staged "${SCOUR_INPUT_STAGED:-false}"
boolean all "${SCOUR_INPUT_ALL:-false}"
boolean exit-zero "${SCOUR_INPUT_EXIT_ZERO:-false}"
boolean triage "${SCOUR_INPUT_TRIAGE:-false}"

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

json=$("$scour" "${args[@]}" --format json || true)
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
} >> "$GITHUB_OUTPUT"

status=0
"$scour" "${args[@]}" --format "${SCOUR_INPUT_FORMAT:-github}" || status=$?
if [[ "${SCOUR_INPUT_TRIAGE:-false}" == true ]]; then
  {
    echo "## Scour triage"
    echo '```text'
    "$scour" triage "${args[@]}" --exit-zero
    echo '```'
  } >> "$GITHUB_STEP_SUMMARY"
fi
exit "$status"
