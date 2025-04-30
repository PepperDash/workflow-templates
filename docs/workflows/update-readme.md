# Workflow: Update README (`update-readme.yml`)

This reusable workflow automatically updates the `README.md` file in the caller repository using a Python script from the `PepperDash/workflow-templates` repository. It commits the changes to a dedicated `robot-docs` branch.

## Trigger

This workflow is triggered by `workflow_call`.

## Inputs

| Name            | Description                                       | Required | Type   |
|-----------------|---------------------------------------------------|----------|--------|
| `target-branch` | The branch in the caller repo to check out initially. | `true`   | string |

## Permissions

- `contents: write` - To commit changes and push to a branch in the caller repository.

## Jobs

### `update-readme`

Runs on `ubuntu-latest`.

**Steps:**

1.  **Checkout Caller Repository:** Checks out the caller repository using `actions/checkout@v3`.
    -   Checks out the branch specified by the `target-branch` input.
    -   Fetches full depth (`fetch-depth: 0`).
    -   Checks out into a subdirectory named `repo`.
2.  **Checkout Workflow Repository:** Checks out the `PepperDash/workflow-templates` repository using `actions/checkout@v3`.
    -   Checks out the `development` branch.
    -   Checks out into a subdirectory named `workflow-templates`.
3.  **Set up Python:** Sets up Python 3.x using `actions/setup-python@v4`.
4.  **Install Python Dependencies:** Installs/upgrades `pip`. (Currently commented out: `pip install -r requirements.txt`).
5.  **Run README Update Script:**
    -   Changes the working directory to `repo` (the caller repository checkout).
    -   Executes the Python script `../workflow-templates/.github/scripts/metadata.py` (relative path from `repo` to the script in the `workflow-templates` checkout). The script is passed `.` as an argument, likely indicating the current directory (`repo`) as the target for updates.
6.  **Check for Changes:**
    -   Changes the working directory to `repo`.
    -   Runs `git diff --quiet` to check if the `metadata.py` script modified any files (specifically `README.md`).
    -   Sets a step output `no_changes` to `true` or `false`.
7.  **Create or Switch to 'robot-docs' Branch:**
    -   Changes the working directory to `repo`.
    -   Runs `git checkout -B robot-docs` which creates the `robot-docs` branch if it doesn't exist or switches to it if it does, discarding any local changes on the previous branch (though changes from the script should be staged next).
8.  **Commit and Push Changes to 'robot-docs' Branch:**
    -   Changes the working directory to `repo`.
    -   Configures Git user email and name for the commit.
    -   Stages the `README.md` file.
    -   Commits the changes with the message "Automated README update". Uses `|| echo "No changes to commit"` to prevent failure if the script made no changes (though step 6 should ideally prevent this step if no changes occurred).
    -   Force-pushes (`--force`) the `robot-docs` branch to the origin repository. This overwrites the history of the `robot-docs` branch.
