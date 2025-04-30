# Workflow: Build 4-Series (`projects-4series-builds.yml`)

This reusable workflow builds Crestron projects targeting the 4-Series platform using MSBuild and creates a GitHub release with the compiled `.cpz` artifacts.

## Trigger

This workflow is triggered by `workflow_call`.

## Inputs

| Name         | Description                               | Required | Type   |
|--------------|-------------------------------------------|----------|--------|
| `newVersion` | Indicates if this is a new version release. | `true`   | string |
| `version`    | The version string to use for the build.  | `true`   | string |
| `tag`        | The Git tag associated with the release.  | `true`   | string |
| `channel`    | The release channel (e.g., 'beta', 'rc'). Empty for release. | `true`   | string |

## Environment Variables

- `BUILD_TYPE`: Set to `Release` if `channel` input is empty, otherwise `Debug`.

## Jobs

### `Build_Project_4-Series`

Runs on `windows-latest`.

**Steps:**

1.  **Checkout repo:** Checks out the repository code using `actions/checkout@v4`.
2.  **Get SLN Info:**
    -   Finds the `*.4Series.sln` file.
    -   Outputs the base name as `SOLUTION_FILE`.
    -   Outputs the relative path as `SOLUTION_PATH`.
3.  **Setup MS Build:** Sets up MSBuild using `microsoft/setup-msbuild@v1.1`.
4.  **Restore Nuget Packages:** Restores NuGet packages for the solution file found in step 2.
5.  **Build Solution:** Builds the solution using `msbuild`. Passes the `BUILD_TYPE` as the configuration and the `version` input as the version property. Disables embedding source revision info.
6.  **Upload Compiled .cpz Files:** Uploads any files matching `**/*.cpz` as an artifact named `compiled-cpz-files`. (Note: This uses `actions/upload-artifact@v2`).
7.  **Get Release Notes:** Downloads the `change-log` artifact (presumably created by a previous versioning step).
8.  **Create Release:** Creates or updates a GitHub release using `ncipollo/release-action@v1`.
    -   This step only runs if the `newVersion` input is `'true'`.
    -   Uses the `tag` input.
    -   Marks as pre-release if `channel` is not empty.
    -   Attaches files matching `**/*.*(cpz|cplz)` as release artifacts.
    -   Uses the downloaded `CHANGELOG.md` as the release body.
    -   `allowUpdates: true` permits updating an existing release for the same tag.
