#!/usr/bin/env bash
# Validates the tag input. Inputs (env): INPUT_TAG.
. "$(dirname "$0")/../../_common/action.sh"

action_summary "## Upload Release"
[ -n "$(action_input tag)" ] || die "upload-release: no tag supplied."
