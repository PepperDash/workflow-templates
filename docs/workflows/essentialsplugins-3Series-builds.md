# Workflow: Essentials Plugin Build 3-Series (`essentialsplugins-3Series-builds.yml`)

This reusable workflow builds Essentials Plugins targeting the Crestron 3-Series platform.

## Trigger

This workflow is triggered by `workflow_call`.

## Inputs

| Name         | Description                               | Required | Type   |
|--------------|-------------------------------------------|----------|--------|
| `newVersion` | Indicates if this is a new version release. | `true`   | string |
| `version`    | The version string to use for the build.  | `true`   | string |
| `tag`        | The Git tag associated with the release.  | `true`   | string |
| `channel`    | The release channel (e.g., 'beta', 'rc'). Empty for release. | `true`   | string |

## Permissions

- `contents: write` - To create releases and commit changes (like version updates).
- `packages: write` - To publish NuGet packages to GitHub Packages.

## Jobs

### `Build_Project_3-Series`

Runs on `windows-2019`.

**Environment Variables:**

- `VERSION`: Set to the `version` input.
- `BUILD_TYPE`: Set to `Release` if `channel` input is empty, otherwise `Debug`.
- `NUSPEC_FILE`: Initially empty, later set to the generated nuspec filename.

**Steps:**

1.  **Checkout repo:** Checks out the repository code using `actions/checkout@v4`. Fetches full depth.
2.  **Fetch tags:** Fetches all Git tags.
3.  **Update AssemblyInfo.cs:** Uses PowerShell to update `AssemblyVersion` and `AssemblyInformationalVersion` in all `AssemblyInfo.cs` and `AssemblyInfo.vb` files found recursively, based on the `VERSION` environment variable.
4.  **Restore Nuget Packages:** Restores packages listed in `packages.config`.
5.  **Login to Docker:** Logs into Docker Hub using secrets.
6.  **Get SLN Path:** Finds the `*.3Series.sln` file and extracts its relative path, storing it in the `SOLUTION_PATH` environment variable.
7.  **Get SLN File:** Finds the `*.3Series.sln` file and extracts its base name, storing it in the `SOLUTION_FILE` environment variable.
8.  **Build Solution:** Runs the build process inside the `pepperdash/sspbuilder` Docker container, mounting the workspace and using `vsidebuild.exe`.
9.  **Zip Build Output:**
    -   Searches the `src/` directory for `.cpz`, `.clz`, and `.cplz` files.
    -   Copies found files to an `output/` directory.
    -   Renames the copied files in `output/` to include the `VERSION`.
    -   Adds a summary of the output files to the GitHub step summary.
10. **Remove Existing Nuspec Files:** Deletes any pre-existing `.nuspec` files.
11. **Create Nuspec File:** Generates a `project.nuspec` file dynamically using PowerShell. It extracts metadata like ID, title, and description from the repository name and includes files from the `output/` directory.
12. **Get nuget File:** Finds the generated `.nuspec` file and stores its base name in the `NUSPEC_FILE` environment variable.
13. **Add nuget.exe:** Sets up the NuGet CLI using `nuget/setup-nuget@v2`, unless the project is the template itself.
14. **Create nuget package:** Packs the `project.nuspec` file into a `.nupkg` file in the `output/` directory, unless it's the template project.
15. **Setup and Publish to GitHub feed:**
    -   Adds the GitHub Packages feed for the repository owner as a NuGet source if it doesn't exist.
    -   Pushes the generated `.nupkg` file to the GitHub Packages feed using the `GITHUB_TOKEN`.
16. **Setup Nuget for Public PepperDash Repo:** Sets the nuget.org API key if the repository is public and owned by 'PepperDash'.
17. **Notify Skipping Public Nuget Setup:** Adds a note to the summary if the public NuGet push is skipped.
18. **Publish to Nuget:** Pushes the `.nupkg` file to nuget.org if the conditions in step 16 are met.
19. **Get release notes:** Downloads the `change-log` artifact (presumably created by a previous versioning step).
20. **Upload Release:** Creates or updates a GitHub release using `ncipollo/release-action@v1`.
    -   Uses the `tag` input.
    -   Marks as pre-release if `channel` is not empty.
    -   Attaches files from the `output/` directory matching `*.*(cpz|cplz)` as release artifacts.
    -   Uses the downloaded `CHANGELOG.md` as the release body.
