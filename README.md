# GitHub Workflows

## Get Versions Workflow



## Essentials Plugin Workflows

### 3-Series Workflow


### 4-Series Workflow


## Getting Started

Add information on how users will implement and consume the workflows from other projects.

1. Add `.github\workflows` directory to project root
2. Add `essentialsplugins-builds-caller.yml` YAML file to `.github\workflows` directory
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