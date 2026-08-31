#!/usr/bin/env bash
# Deletes the release and remote tag a previous step may have created, so a retry
# starts clean. Uses gh + git. Inputs (env): INPUT_TAG, INPUT_FAIL (default true),
# GH_TOKEN, GITHUB_REPOSITORY.
. "$(dirname "$0")/../../_common/action.sh"

TAG="$(action_input tag)"
DO_FAIL="$(action_input fail true)"

action_summary "## Build Failed Clean up"
action_summary "The build output above shows the errors that caused the failure."

if [ -z "$TAG" ]; then
  action_summary "No tag supplied; nothing to clean up."
else
  release_id="$(gh api "repos/${GITHUB_REPOSITORY}/releases/tags/${TAG}" --jq '.id' 2>/dev/null || true)"
  if [ -n "$release_id" ]; then
    if gh api -X DELETE "repos/${GITHUB_REPOSITORY}/releases/${release_id}"; then
      action_summary "Deleted release \`$TAG\`."
    else
      action_summary "⚠️ Failed to delete release \`$TAG\`."
    fi
  else
    action_summary "No release for tag '$TAG', skipping."
  fi

  if git ls-remote --tags origin "$TAG" 2>/dev/null | grep -q "$TAG"; then
    if git push origin --delete "$TAG"; then
      action_summary "Deleted tag \`$TAG\` from remote."
    else
      action_summary "⚠️ Failed to delete tag \`$TAG\` from remote."
    fi
  else
    action_summary "Tag '$TAG' not on remote, skipping."
  fi
fi

[ "$DO_FAIL" = "true" ] && exit 1
exit 0
