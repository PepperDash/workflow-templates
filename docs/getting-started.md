# Getting Started with PepperDash Workflows

This guide will help you get started with implementing PepperDash workflows in your project.

## Prerequisites

Before implementing these workflows, ensure you have:

1. A GitHub repository for your project
2. Appropriate permissions to modify workflows in the repository
3. Proper project structure (see Project Structure Requirements below)

## Project Structure Requirements

Your project should follow this basic structure:

```
/Project-Repo/
├── .gitub/
│   └── workflows/
│       └── [your workflow caller files]
├── src/
│   ├── Directory.Build.props  (optional but recommended)
│   ├── Directory.Build.targets  (optional but recommended)
│   ├── *.3series.csproj  (for 3-Series builds)
│   ├── *.4series.csproj  (for 4-Series builds)
│   └── [source code files]
├── *.3series.sln  (for 3-Series builds)
├── *.4series.sln  (for 4-Series builds)
├── .releaserc.json  (required for semantic versioning)
├── LICENSE.md
└── README.md
```

## Step-by-Step Implementation

### 1. Create Workflow Directory

First, create the `.github/workflows` directory in your project repository:

```bash
mkdir -p .github/workflows
```

### 2. Choose the Appropriate Workflow Type

Determine which workflow type is appropriate for your project:

- **For PepperDash Essentials or Core Projects**:
  - Use `essentials-builds-caller.yml`
  - Reference `essentials-3Series-builds.yml` for 3-Series builds
  - Reference `essentialsplugins-4Series-builds.yml` for 4-Series builds (with bypassPackageCheck set to true)

- **For Essentials Plugins**:
  - Use a plugin-specific caller
  - Reference `essentialsplugins-3Series-builds.yml` for 3-Series builds
  - Reference `essentialsplugins-4Series-builds.yml` for 4-Series builds

### 3. Create Workflow Caller File

Create a workflow caller file in the `.github/workflows` directory. Examples are provided below.

#### 3.1 For Essentials Plugins (Both 3-Series and 4-Series)

Create a file named `.github/workflows/essentialsplugins-builds-caller.yml`:

```yaml
name: Build Essentials Plugin

on:
  push:
    branches:
      - '**'

jobs:
  # Get-Version caller
  getVersion:
    uses: PepperDash/workflow-templates/.github/workflows/essentialsplugins-getversion.yml@main
    secrets: inherit    
  
  # 3-Series caller
  build-3Series:  
    uses: PepperDash/workflow-templates/.github/workflows/essentialsplugins-3Series-builds.yml@main    
    secrets: inherit
    needs: getVersion
    if: needs.getVersion.outputs.newVersion == 'true'
    with:
      newVersion: ${{ needs.getVersion.outputs.newVersion }}
      version: ${{ needs.getVersion.outputs.version }}
      tag: ${{ needs.getVersion.outputs.tag }}
      channel: ${{ needs.getVersion.outputs.channel }}
  
  # 4-Series caller
  build-4Series:
    uses: PepperDash/workflow-templates/.github/workflows/essentialsplugins-4Series-builds.yml@main
    secrets: inherit
    needs: getVersion
    if: needs.getVersion.outputs.newVersion == 'true'
    with:
      newVersion: ${{ needs.getVersion.outputs.newVersion }}
      version: ${{ needs.getVersion.outputs.version }}
      tag: ${{ needs.getVersion.outputs.tag }}
      channel: ${{ needs.getVersion.outputs.channel }}
```

#### 3.2 For Essentials/Core 3-Series Only

Create a file named `.github/workflows/essentials-builds-caller.yml`:

```yaml
name: Build Essentials 1.X

on:
  push:
    branches:
      - '**'

jobs:
  getVersion:
    uses: PepperDash/workflow-templates/.github/workflows/essentialsplugins-getversion.yml@main
    secrets: inherit
  build-3Series:
    uses: PepperDash/workflow-templates/.github/workflows/essentials-3Series-builds.yml@main
    secrets: inherit
    needs: getVersion
    if: needs.getVersion.outputs.newVersion == 'true'
    with:
      newVersion: ${{ needs.getVersion.outputs.newVersion }}
      version: ${{ needs.getVersion.outputs.version }}
      tag: ${{ needs.getVersion.outputs.tag }}
      channel: ${{ needs.getVersion.outputs.channel }}
```

#### 3.3 For Essentials/Core 4-Series Only

Create a file named `.github/workflows/essentials-builds-caller.yml`:

```yaml
name: Build PepperDash Essentials

on:
  push:
    branches:
      - '**'

jobs:
  # Get-Version caller
  getVersion:
    uses: PepperDash/workflow-templates/.github/workflows/essentialsplugins-getversion.yml@main
    secrets: inherit    
  
  # 4-Series caller
  build-4Series:
    uses: PepperDash/workflow-templates/.github/workflows/essentialsplugins-4Series-builds.yml@main
    secrets: inherit
    needs: getVersion
    if: needs.getVersion.outputs.newVersion == 'true'
    with:
      newVersion: ${{ needs.getVersion.outputs.newVersion }}
      version: ${{ needs.getVersion.outputs.version }}
      tag: ${{ needs.getVersion.outputs.tag }}
      channel: ${{ needs.getVersion.outputs.channel }}
      bypassPackageCheck: true
```

### 4. Set Up Semantic Versioning

Create a `.releaserc.json` file in the root of your project to configure semantic versioning:

```json
{
  "branches": ["main"],
  "plugins": [
    "@semantic-release/commit-analyzer",
    "@semantic-release/release-notes-generator",
    "@semantic-release/github"
  ]
}
```

### 5. Commit and Push

Commit the workflow files and push to your repository:

```bash
git add .github/workflows .releaserc.json
git commit -m "chore: add GitHub workflow configuration"
git push
```

### 6. Monitor the Workflow Execution

After pushing your changes:
1. Go to your repository on GitHub
2. Click on the "Actions" tab to view workflow executions
3. Monitor the progress of your workflows

## Troubleshooting

If your workflows are not executing as expected, check the following:

1. **Workflow File Syntax**: Ensure your workflow files use correct YAML syntax
2. **Project Structure**: Verify that your project follows the required structure
3. **Branch References**: Make sure you're referencing the correct branch in your workflow calls (e.g., `@main`)
4. **Commit Messages**: For version-based workflows, ensure your commit messages follow conventional commit format
5. **Required Secrets**: Check if all required secrets are properly set up in your repository

## Branch Considerations

When referencing workflows, the `@main` branch is the default and most stable option. Only use other branches (like `@development`) in specific cases when necessary.

## Getting Help

If you encounter issues with the workflows:

1. Check the workflow logs to identify where the build failed
2. Ensure that repo callers are using the right references
3. Review the troubleshooting steps above
4. Reach out to the CI/CD/Git Foundation Team via Slack at [#ci-cd-git-foundation](https://pepperdash.slack.com/archives/C08KDBTD55G)
