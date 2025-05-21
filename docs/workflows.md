# GitHub Workflows Documentation

This document provides detailed information about the available GitHub workflows in the PepperDash workflow templates repository and how to use them in your projects.

## Available Workflows

The repository provides several reusable workflows for building and versioning PepperDash projects:

### Version Management

- **essentialsplugins-getversion.yml**: Creates version numbers based on semantic release principles
  - Outputs:
    - `version`: The semantic version number
    - `tag`: The git tag for the version
    - `newVersion`: Boolean indicating if a new version was generated
    - `channel`: The release channel (empty for production releases)

### Build Workflows

#### Essentials & Core Builds

- **essentials-3Series-builds.yml**: Builds PepperDash Essentials/Core for 3-Series processors
  - Inputs:
    - `newVersion`: Boolean indicating if this is a new version
    - `version`: Semantic version number
    - `tag`: Git tag for the version
    - `channel`: Release channel

#### Plugins Builds

- **essentialsplugins-3Series-builds.yml**: Builds Essentials Plugins for 3-Series processors
  - Inputs:
    - `newVersion`: Boolean indicating if this is a new version
    - `version`: Semantic version number
    - `tag`: Git tag for the version
    - `channel`: Release channel

- **essentialsplugins-4Series-builds.yml**: Builds Essentials Plugins for 4-Series processors
  - Inputs:
    - `newVersion`: Boolean indicating if this is a new version
    - `version`: Semantic version number
    - `tag`: Git tag for the version
    - `channel`: Release channel
    - `bypassPackageCheck`: Optional boolean to bypass package name validation

#### Other Workflows

- **essentialsplugins-checkCommitMessage.yml**: Validates commit messages
- **projects-4series-builds.yml**: Generic 4-Series project builds
- **update-readme.yml**: Updates README file with build status and other information

## Implementation Guide

### Project Setup

To use these workflows in your project:

1. Create a `.github/workflows` directory in your project's root folder:
   ```
   mkdir -p .github/workflows
   ```

2. Create a caller YAML file in the `.github/workflows` directory:

### Example: Essentials Plugin with both 3-Series and 4-Series Support

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

### Example: Essentials/Core 3-Series Build

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

### Example: Essentials/Core 4-Series Build

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

## Project Requirements

To ensure the workflows function correctly, your project should adhere to the following structure:

```
/Project-Repo/
├── .gitub/
│   └── workflows/
│       ├── essentialsplugins-builds-caller.yml  // <== Essentials Plugins (EPI) caller
│       └── essentials-builds-caller.yml         // <== Essentials & Core caller
├── src/
│   ├── Directory.Build.props
│   ├── Directory.Build.targets
│   ├── *.3series.csproj
│   ├── *.4series.csproj    
│   └── // source code
├── *.3series.sln
├── *.4series.sln
├── .releaserc.json
├── LICENSE.md
└── README.md
```

## Troubleshooting

If your workflow fails:

1. Check the workflow logs to identify where the build failed
2. Verify that your repo callers are referencing the correct workflow version
3. Ensure your project structure matches the required format
4. Check that all required inputs are provided to the workflows
5. If you continue to have issues, reach out to the CI/CD/Git Foundation Team via Slack

## Branch References

By default, workflow references use the `@main` branch. Only reference other branches in specific cases where needed.

## Workflow Specifics

### Version Management

The `essentialsplugins-getversion.yml` workflow:
- Manages semantic versioning based on commit history
- Requires proper commit message formatting for version bumps
- Generates version numbers, tags, and channel information
- Should be called first in workflow chains

### Build Process

Build workflows handle:
- Compiling projects for specific platforms (3-Series or 4-Series)
- Creating distribution packages
- Publishing artifacts to appropriate registries
- Generating documentation and release notes
