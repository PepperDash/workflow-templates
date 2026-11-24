# PepperDash GitHub Workflows Documentation

Welcome to the PepperDash GitHub Workflows documentation. This documentation provides comprehensive information about the available GitHub workflows in the PepperDash workflow templates repository and how to implement them in your projects.

## Documentation Contents

1. [Workflows Overview](workflows.md) - A comprehensive overview of all available workflows
2. [Workflow Details](workflow-details.md) - Detailed information about each workflow
3. [Getting Started Guide](getting-started.md) - Step-by-step instructions for implementing workflows

## Quick Start

To get started with PepperDash workflows:

1. Add a `.github/workflows` directory to your project root
2. Add appropriate caller YAML files to the `.github/workflows` directory
3. Configure your caller files to reference the required workflows

Example caller for an Essentials Plugin that targets Essentials 2.x or later:

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

Each branch calls **one** of the builds, depending on the Essentials version it targets: `essentialsplugins-3Series-builds.yml` for Essentials 1.x, `essentialsplugins-4Series-builds.yml` for every later version. Never call both: they upload to the same release, and only the 4-series build generates the [release metadata](pepperdash-metadata-workflow.md) Portal uses.

For more detailed information, please refer to the documentation sections linked above.

## Support

If you encounter issues with the workflows:

1. Check the workflow logs to identify where the build failed
2. Ensure that repo callers are using the right references
3. Review the troubleshooting steps in the [Getting Started Guide](getting-started.md)
4. Reach out to the CI/CD/Git Foundation Team via Slack at [#ci-cd-git-foundation](https://pepperdash.slack.com/archives/C08KDBTD55G)
