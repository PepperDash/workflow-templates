# Workflow: Essentials Plugin Build 4-Series (`essentialsplugins-4Series-builds.yml`)

This reusable workflow builds Essentials Plugins targeting the Crestron 4-Series platform using MSBuild.

## Trigger

This workflow is triggered by `workflow_call`.

## Inputs

| Name                 | Description                                       | Required | Type    | Default |
|----------------------|---------------------------------------------------|----------|---------|---------|
| `newVersion`         | Indicates if this is a new version release.       | `true`   | string  |         |
| `version`            | The version string to use for the build.          | `true`   | string  |         |
| `tag`                | The Git tag associated with the release.          | `true`   | string  |         |
| `channel`            | The release channel (e.g., 'beta', 'rc'). Empty for release. | `true`   | string  |         |
| `bypassPackageCheck` | Set to `true` to bypass the package name check.   | `false`  | boolean | `false` |

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
6.  **Get release notes:** Downloads the `change-log` artifact (presumably created by a previous versioning step).
7.  **Check Package Name:**
    -   This step is skipped if `bypassPackageCheck` input is `true`.
    -   Constructs an expected NuGet package name based on the repository name (e.g., `epi-foo-bar` becomes `PepperDash.Essentials.Plugins.Foo.Bar`).
    -   Finds the generated `.nupkg` file in the `output/` directory.
    -   Compares the actual package name (excluding version) with the expected name (case-insensitive).
    -   Fails the workflow with an error if the names don't match.
8.  **Upload Release:** Creates or updates a GitHub release using `ncipollo/release-action@v1`.
    -   This step only runs if the `newVersion` input is `'true'`.
    -   Uses the `tag` input.
    -   Marks as pre-release if `channel` is not empty.
    -   Attaches files matching `output\**\*.*(cpz|cplz)` as release artifacts.
    -   Uses the downloaded `CHANGELOG.md` as the release body.
9.  **Setup and Publish to GitHub feed:**
    -   Adds the GitHub Packages feed for the repository owner as a NuGet source if it doesn't exist.
    -   Pushes the generated `.nupkg` file(s) found in `output/` to the GitHub Packages feed using the `GITHUB_TOKEN`.
10. **Setup Nuget:** Sets the nuget.org API key using `nuget setApiKey` if the repository is public and owned by 'PepperDash'.
11. **Publish to Nuget:** Pushes the `.nupkg` file(s) found in `output/` to nuget.org if the conditions in step 10 are met.
