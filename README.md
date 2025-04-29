# GitHub Workflows

## Get Versions Workflow

### Notes

- Creates a new version number when the workflow is triggered.
  - Standardizes version information based on semantic release and is required by subsequent workflows.
  - If the version information is not generated subsequent builds relying on version will not get triggered.

### Troubleshooting

What do I do when a action or build fails?
 

## Essentials Plugin Workflows

The following GitHub workflows are available.  The information below provides high-level details on what the workflows are doing. 

### 3-Series Workflow


### 4-Series Workflow


## Getting Started

### Using Workflows in a Project

1. Add `.github\workflows` directory to project root
2. Add `essentialsplugins-builds-caller.yml` YAML file to `.github\workflows` directory

```
/Project-Repo/
├── .gitub/
│   └── workflows/
│       └── essentialsplugins-builds-caller.yml
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

3. Edit `essentialsplugins-builds-caller.yml` file to include the following:

```yml
name: Build Essentials Plugin

on:
  push:
    branches:
      - '**'

jobs:
  getVersion:
    uses: PepperDash/workflow-templates/.github/workflows/essentialsplugins-getversion.yml@main
    secrets: inherit    
  
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