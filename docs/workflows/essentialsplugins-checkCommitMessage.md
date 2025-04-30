# Workflow: Commit Message Check (`essentialsplugins-checkCommitMessage.yml`)

This reusable workflow checks if the latest commit message adheres to the Conventional Commits specification or is a standard Git merge commit message.

## Trigger

This workflow is triggered by `workflow_call`.

## Inputs

| Name                | Description                                      | Required | Type    | Default |
|---------------------|--------------------------------------------------|----------|---------|---------|
| `bypassCommitCheck` | Set to `true` to bypass the commit message check. | `false`  | boolean | `false` |

## Jobs

### `check_commit_message`

Runs on `ubuntu-latest`.

**Condition:** This job only runs if the `bypassCommitCheck` input is not `'true'`.

**Steps:**

1.  **Checkout repository:** Checks out the repository code using `actions/checkout@v4`. Fetches full depth (`fetch-depth: 0`) to ensure `git log` can access previous commits if needed (though only the latest is checked here).
2.  **Check Commit Messages:**
    -   Retrieves the subject line (`%s`) of the latest commit (`-n 1`).
    -   Defines regex patterns for:
        -   Conventional Commits: `^(feat|fix|chore|docs|style|refactor|perf|test|build|ci|revert|wip)(\(.+\))?:\s.+`
        -   Standard Merge Commits: `^(Merge (branch|remote-tracking branch|commit) '.*'( into .*)?)$`
    -   Checks if the latest commit message matches either pattern.
    -   If it doesn't match, it prints an error message using `echo "::error::..."` and exits with code 1, failing the workflow.
    -   If it matches, it prints a confirmation message.
