# Workflow Details

This document provides detailed information about each workflow available in the PepperDash workflow-templates repository.

## Version Management Workflows

### essentialsplugins-getversion.yml

**Purpose**: Creates a new version number when the workflow is triggered.

**Features**:
- Standardizes version information based on semantic release principles
- Required by subsequent workflows for consistent versioning
- If the version information is not generated, subsequent builds relying on version will not get triggered

**Outputs**:
- `newVersion`: Boolean indicating if a new version was generated
- `tag`: The git tag for the version
- `version`: The semantic version number
- `channel`: The release channel (empty for production releases)

**Usage**:
```yaml
getVersion:
  uses: PepperDash/workflow-templates/.github/workflows/essentialsplugins-getversion.yml@main
  secrets: inherit
```

## Build Workflows

### essentials-3Series-builds.yml

**Purpose**: Builds PepperDash Essentials/Core for 3-Series processors.

**Features**:
- Compiles projects targeting 3-Series processors
- Creates distribution packages
- Publishes to appropriate registries

**Inputs**:
- `newVersion`: Boolean indicating if this is a new version
- `version`: Semantic version number
- `tag`: Git tag for the version
- `channel`: Release channel

**Usage**:
```yaml
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

### essentialsplugins-3Series-builds.yml

**Purpose**: Builds Essentials Plugins for 3-Series processors.

**Features**:
- Compiles plugin projects targeting 3-Series processors
- Creates distribution packages
- Publishes to appropriate registries

**Inputs**:
- `newVersion`: Boolean indicating if this is a new version
- `version`: Semantic version number
- `tag`: Git tag for the version
- `channel`: Release channel

**Usage**:
```yaml
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
```

### essentialsplugins-4Series-builds.yml

**Purpose**: Builds Essentials Plugins for 4-Series processors.

**Features**:
- Compiles plugin projects targeting 4-Series processors
- Creates distribution packages
- Publishes to appropriate registries

**Inputs**:
- `newVersion`: Boolean indicating if this is a new version
- `version`: Semantic version number
- `tag`: Git tag for the version
- `channel`: Release channel
- `bypassPackageCheck`: Optional boolean to bypass package name validation

**Usage**:
```yaml
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
    bypassPackageCheck: false
```

### projects-4series-builds.yml

**Purpose**: Generic build workflow for 4-Series projects.

**Features**:
- Provides a more generic approach for building 4-Series projects
- Can be used for projects that don't fit the Essentials/Plugins pattern

**Inputs**:
- Similar to other build workflows

**Usage**:
```yaml
build:
  uses: PepperDash/workflow-templates/.github/workflows/projects-4series-builds.yml@main
  secrets: inherit
  needs: getVersion
  if: needs.getVersion.outputs.newVersion == 'true'
  with:
    newVersion: ${{ needs.getVersion.outputs.newVersion }}
    version: ${{ needs.getVersion.outputs.version }}
    tag: ${{ needs.getVersion.outputs.tag }}
    channel: ${{ needs.getVersion.outputs.channel }}
```

## Utility Workflows

### essentialsplugins-checkCommitMessage.yml

**Purpose**: Validates commit messages to ensure they follow the required format for semantic versioning.

**Features**:
- Checks that commit messages follow conventional commit format
- Ensures proper versioning can be determined

**Usage**:
```yaml
check-commit:
  uses: PepperDash/workflow-templates/.github/workflows/essentialsplugins-checkCommitMessage.yml@main
```

### update-readme.yml

**Purpose**: Updates the README.md file with build status badges and other information.

**Features**:
- Automatically updates README with current build status
- Can add versioning information

**Usage**:
```yaml
update-readme:
  uses: PepperDash/workflow-templates/.github/workflows/update-readme.yml@main
  needs: [build-3Series, build-4Series]
  with:
    version: ${{ needs.getVersion.outputs.version }}
```
