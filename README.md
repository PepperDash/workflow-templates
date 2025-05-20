# GitHub Workflows

## Get Versions Workflow

### Notes

- Creates a new version number when the workflow is triggered.
  - Standardizes version information based on semantic release and is required by subsequent workflows.
  - If the version information is not generated subsequent builds relying on version will not get triggered.

### Troubleshooting

What do I do when a action or build fails?

1. Check the workflow logs to identify where the build failed.
2. Check to ensure the repo callers are using the right reference.
3. Reach out to the [CI/CD/Git Foundation Team via Slack](https://pepperdash.slack.com/archives/C08KDBTD55G)
 
## Getting Started

### Using Workflows in a Project

1. Add `.github\workflows` directory to project root
2. Add caller YAML file to `.github\workflows` directory

```
/Project-Repo/
├── .gitub/
│   └── workflows/
│       └── essentialsplugins-builds-caller.yml // <== Essentials Plugins (EPI) caller
│       └── essentials-builds-caller.yml        // <== Essentials & Core caller
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

3. Edit caller YAML file.
   - Reference `Essentials/Core`, `4-Series` or `3-Series` Workflows for required information. 

## Workflows

The following GitHub workflows are available.  The information below provides high-level details on what the workflows are doing. 

### PepperDash Essentials & PepperDash Core

> [!IMPORTANT]
> `essentialsplugins-getversion.yml` is a shared reference.
> 
> PepperDash Essentials and PepperDash Core have specific build references that are not shared with Plugins.


#### 4-Series 

`essentialsplugins-builds-4series-caller.yml`

```yml
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

#### 3-Series / Maintenance-1x

`essentialsplugins-builds-3-series-caller.yml`

```yml
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


### PepperDash Essentials Plugins (EPIs) 

The caller file below implments both `3-Series` and `4-Series` caller references.  Be mindful of what branch each caller reference is using.  `@main` is default, and other branches should only be referenced in specific cases.

> [!NOTE]
> Remove the `build-3Seires` reference if you only need `.net472+` files.

```yml
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
