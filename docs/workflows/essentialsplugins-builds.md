# Workflow: Branch Build Using Docker (`essentialsplugins-builds.yml`)

This reusable workflow builds Essentials Plugins based on the branch being built, determines versioning, creates releases (for non-release branches), and publishes NuGet packages. It primarily uses Docker for the 3-Series build process.

## Trigger

This workflow is triggered by `workflow_call`.

## Inputs

| Name             | Description                                  | Required | Type   |
|------------------|----------------------------------------------|----------|--------|
| `branch`         | The name of the branch being built.          | `true`   | string |
| `default-branch` | The name of the default/release branch (e.g., `main`). | `true`   | string |

## Environment Variables

- `VERSION`: Calculated version string (e.g., `1.0.0`, `1.0.1-beta-123`). Initialized to `0.0.0-buildtype-buildnumber`.
- `BUILD_TYPE`: Set to `Release` for the `default-branch`, otherwise `Debug`.
- `RELEASE_BRANCH`: Set to the `default-branch` input.
- `UPLOAD_URL`: The URL for uploading release assets. Set dynamically after release creation.

## Jobs

### `Build_Project`

Runs on `windows-2019`.

**Steps:**

1.  **Checkout:** Checks out the specified `branch` using `actions/checkout@v3`.
2.  **Fetch tags:** Fetches all Git tags.
3.  **CheckForRelease:** Sets `BUILD_TYPE` to `Release` if the input `branch` matches the `default-branch`.
4.  **Set Version Number:**
    -   Determines the latest semantic version tag on the `RELEASE_BRANCH`.
    -   If `BUILD_TYPE` is `Release`, sets `VERSION` to the latest tag found.
    -   If `BUILD_TYPE` is `Debug`, calculates a pre-release version based on the latest tag and the branch name convention:
        -   `feature/*`: `major.minor.build+1-alpha-runnumber`
        -   `release/*`: `major.minor.build-rc-runnumber` (version from branch name)
        -   `dev*`: `major.minor.build+1-beta-runnumber`
        -   `hotfix/*`: `major.minor.build+1-hotfix-runnumber`
        -   Other branches: `major.minor.build+1-beta-runnumber`
    -   Stores the calculated version in the `VERSION` environment variable.
5.  **Update AssemblyInfo.cs:** Uses PowerShell to update `AssemblyVersion` and `AssemblyInformationalVersion` in `AssemblyInfo.cs`/`.vb` files based on the calculated `VERSION`.
6.  **Restore Nuget Packages:** Restores packages listed in `packages.config`.
7.  **Get SLN Path:** Finds the `*.sln` file and extracts its relative path into the `SOLUTION_PATH` environment variable.
8.  **Get SLN File:** Finds the `*.sln` file and extracts its base name into the `SOLUTION_FILE` environment variable.
9.  **Login to Docker:** Logs into Docker Hub using secrets.
10. **Build Solution:** Runs the build process inside the `pepperdash/sspbuilder` Docker container, mounting the workspace and using `vsidebuild.exe`. Uses the `BUILD_TYPE` environment variable for the configuration.
11. **Zip Build Output:**
    -   Creates an `output` directory.
    -   Copies build artifacts (`.clz`, `.cpz`, `.cplz`), documentation (`.md`), NuGet spec (`.nuspec`), and related files (`.dll`, `.xml`, `.json`) from the workspace into the `output` directory, excluding the `packages` folder.
    -   Renames `.cplz` files in the `output` directory to include the `VERSION`.
    -   Compresses the contents of the `output` directory into a zip file named `{SOLUTION_FILE}-{VERSION}.zip`.
12. **Write Version:** Writes the calculated `VERSION` to `output/version.txt`.
13. **Upload Build Output:** Uploads the generated zip file (`{SOLUTION_FILE}-{VERSION}.zip`) as an artifact named `Build`.
14. **Upload version.txt:** Uploads the `version.txt` file as an artifact named `Version`.
15. **Create Release:** If `BUILD_TYPE` is *not* `Release`, creates a pre-release on GitHub using `fleskesvor/create-release`. The tag and release name are set to the calculated `VERSION`.
16. **Set release url Release:** If a pre-release was created in the previous step, captures its `upload_url` output into the `UPLOAD_URL` environment variable.
17. **Upload Release Package:** Uploads the build zip artifact (`{SOLUTION_FILE}-{VERSION}.zip`) to the GitHub release created in step 15.

### `Push_Nuget_Package`

Depends on `Build_Project`. Runs on `windows-2019`.

**Steps:**

1.  **Download Build Version Info:** Downloads the `Version` artifact (`version.txt`).
2.  **Set Version Number:** Reads the version from `version.txt` and sets the `VERSION` environment variable.
3.  **Remove Existing Nuspec Files:** Deletes any pre-existing `.nuspec` files in the workspace.
4.  **Create Nuspec File:** Generates a `project.nuspec` file dynamically. Extracts metadata like ID and title from the repository name. Assumes targets for `net35` and `net47`. Sets license to MIT expression.
5.  **Download Build output:** Downloads the `Build` artifact (the zip file).
6.  **Unzip Build file:** Extracts the contents of the downloaded zip file.
7.  **Copy Files to root & delete output directory:** Cleans up the root directory and copies the extracted build files from the `output` subdirectory to the root. Deletes the now-empty `output` directory.
8.  **Get nuget File:** Finds the generated `project.nuspec` file and stores its base name in the `NUSPEC_FILE` environment variable.
9.  **Add nuget.exe:** Sets up the NuGet CLI using `nuget/setup-nuget@v2`, unless the project is the template itself (`EssentialsPluginTemplate`).
10. **Add Github Packages source:** Adds the `pepperdash` GitHub Packages feed as a NuGet source named `github`.
11. **Create nuget package:** Packs the `project.nuspec` file into a `.nupkg` file using the `VERSION`.
12. **Publish nuget package to Github registry:** Pushes the generated `.nupkg` file to the `github` NuGet source (GitHub Packages).
13. **Add nuget.org API Key:** Sets the nuget.org API key if the repository is public, owned by 'PepperDash', and not the template project.
14. **Publish nuget package to nuget.org:** Pushes the `.nupkg` file to nuget.org if the conditions in step 13 are met.
