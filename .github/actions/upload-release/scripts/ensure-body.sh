#!/usr/bin/env bash
# Ensures the release body file exists; creates a placeholder if not.
# Inputs (env): INPUT_BODY_FILE, INPUT_TAG.
. "$(dirname "$0")/../../_common/action.sh"

body="$(action_input body-file ./CHANGELOG.md)"
if [ ! -f "$body" ]; then
  action_summary "⚠️ ${body} not found; creating a placeholder."
  printf 'Release %s\n' "$(action_input tag)" > "$body"
fi
