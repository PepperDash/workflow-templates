# Shared helpers for composite-action bash scripts. Source with:
#   . "$(dirname "$0")/../../_common/action.sh"
#
# Reads inputs from $INPUT_<UPPER_SNAKE>; writes to $GITHUB_OUTPUT /
# $GITHUB_STEP_SUMMARY (plain file paths, so tests point them at temp files).

set -uo pipefail

action_input() {   # action_input NAME [DEFAULT]
  local name key val
  name="$1"
  key="INPUT_$(printf '%s' "$name" | tr '[:lower:]-' '[:upper:]_')"
  val="${!key:-}"
  if [ -z "$val" ]; then printf '%s' "${2:-}"; else printf '%s' "$val"; fi
}

action_output() {  # action_output NAME VALUE
  [ -n "${GITHUB_OUTPUT:-}" ] && printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"
  printf 'output: %s=%s\n' "$1" "$2"
}

action_summary() { # action_summary TEXT...
  [ -n "${GITHUB_STEP_SUMMARY:-}" ] && printf '%s\n' "$*" >> "$GITHUB_STEP_SUMMARY"
  printf '%s\n' "$*"
}

die() {            # die MESSAGE
  action_summary "❌ $*"
  printf '%s\n' "$*" >&2
  exit 1
}
