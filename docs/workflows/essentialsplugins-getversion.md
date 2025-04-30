# Workflow: Essentials Plugin Build Get Version (`essentialsplugins-getversion.yml`)

This reusable workflow uses `semantic-release` to determine the next semantic version based on commit messages, generates a changelog, creates a Git tag, and optionally creates/updates a GitHub release.

## Trigger

This workflow is triggered by `workflow_call`.

## Outputs

| Name         | Description                                  | Value                                        |
|--------------|----------------------------------------------|----------------------------------------------|
| `version`    | The calculated semantic version.             | `${{ jobs.GetVersionNumber.outputs.version }}`    |
| `tag`        | The Git tag created (e.g., `v1.2.3`).        | `${{ jobs.GetVersionNumber.outputs.tag }}`        |
| `newVersion` | `'true'` if a new version was generated.     | `${{ jobs.GetVersionNumber.outputs.newVersion }}` |
| `channel`    | The release channel (e.g., `beta`, `rc`). Empty for stable release. | `${{ jobs.GetVersionNumber.outputs.channel }}`   |

## Jobs

### `GetVersionNumber`

Runs on `ubuntu-latest`.

**Outputs:** Mirrors the workflow outputs (`newVersion`, `tag`, `version`, `channel`).

**Steps:**

1.  **Checkout repo:** Checks out the repository code using `actions/checkout@v4`.
2.  **Set up Node.js:** Sets up Node.js version 20 using `actions/setup-node@v4`.
3.  **Get branch name:** Extracts the branch name from `github.ref` and outputs it as `branch`. Also creates a sanitized `prerelease` channel name (replacing `/` with `-`).
4.  **Replace branch name in .releaserc.json:** If the branch is *not* `main`, replaces the placeholder `replace-me-feature-branch` in `.releaserc.json` with the actual branch name. Uses `jacobtomlinson/gha-find-replace`.
5.  **Replace prerelease name in .releaserc.json:** If the branch is *not* `main`, replaces the placeholder `replace-me-prerelease` in `.releaserc.json` with the sanitized `prerelease` channel name from step 3. Uses `jacobtomlinson/gha-find-replace`.
6.  **Get version number:** Executes `semantic-release` using `npx`. This step analyzes commits since the last release, determines the version bump (major, minor, patch) or pre-release version, generates `CHANGELOG.md`, creates a Git tag, and potentially publishes a GitHub release (depending on `.releaserc.json` config). The outputs (`newVersion`, `tag`, `version`, `channel`, `type`) from `semantic-release` (via `@semantic-release/exec` configuration in `.releaserc.json`) are captured by the step's `id: get_version`.
7.  **Print summary if no new version:** If `semantic-release` did not generate a new version (`newVersion != 'true'`), adds a note to the GitHub step summary.
8.  **Upload release notes:** If a new version *was* generated, uploads the created `CHANGELOG.md` file as an artifact named `change-log`.
9.  **Upload Release:** If a new version *was* generated, creates or updates a GitHub release using `ncipollo/release-action@v1`.
    -   Uses the `tag` output from step 6.
    -   Marks as pre-release if the `channel` output from step 6 is not empty.
    -   Uses the generated `CHANGELOG.md` as the release body.
    -   `allowUpdates: true` permits updating an existing release for the same tag.
10. **Print results:** If a new version *was* generated, adds a summary of the outputs (`version`, `tag`, `newVersion`, `channel`, `type`) to the GitHub step summary.

## Example Summaries

### New Version Generated

```markdown
# Summary
Version: 1.2.3
Tag: v1.2.3
New Version: true
Channel:
Type: patch
```

### No New Version Generated

```markdown
# Summary
No new version generated
```
