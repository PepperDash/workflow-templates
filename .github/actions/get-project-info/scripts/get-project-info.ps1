#requires -Version 7.0
<#
  Derives make / model / title / NuGet package id from the repository name using
  the PepperDash EPI convention (org/epi-make-model[-variant]).

  Inputs (env):
    INPUT_PACKAGE_PREFIX   default 'PepperDash.Essentials.Plugins.'
    INPUT_PACKAGE_STYLE    'dotted' (default) => <prefix>Make.Model
                           'concatenated'     => <prefix>MakeModel
    GITHUB_REPOSITORY      'owner/repo'
  Outputs: make, model, title, package, repo-is-plugin, repo-name
#>
. "$PSScriptRoot/../../_common/action.ps1"

$prefix = Get-ActionInput -Name 'package-prefix' -Default 'PepperDash.Essentials.Plugins.'
$style  = Get-ActionInput -Name 'package-style'  -Default 'dotted'

$repoFullName = $env:GITHUB_REPOSITORY
if ([string]::IsNullOrWhiteSpace($repoFullName)) {
  Stop-Action "GITHUB_REPOSITORY is not set."
}

Add-ActionSummary "## Get Project Info`n"

$repoName = $repoFullName.Split('/')[-1]
$parts = @($repoName -split '-')

switch ($parts.Count) {
  0 { Stop-Action "Could not parse a make/model from repo name '$repoName'." }
  1 { $make = $parts[0].Replace(' ', ''); $model = '' }
  2 { $make = $parts[0].Replace(' ', ''); $model = $parts[1].Replace(' ', '') }
  default {
    # org/epi-make-model[-variant]
    $make  = $parts[1].Replace(' ', '')
    $model = ($parts[2..($parts.Count - 1)] -join '').Replace(' ', '')
  }
}

if ($model -eq '') {
  $title = $make
  $package = $title -replace ' ', ''
  $repoIsPlugin = $false
}
else {
  $ti = (Get-Culture).TextInfo
  $makeTc  = ($ti.ToTitleCase($make))  -replace ' ', ''
  $modelTc = ($ti.ToTitleCase($model)) -replace ' ', ''
  $title = "$makeTc$modelTc"
  $package = if ($style -eq 'concatenated') { "$prefix$makeTc$modelTc" } else { "$prefix$makeTc.$modelTc" }
  $repoIsPlugin = $true
}

Add-ActionOutput -Name 'repo-name'      -Value $repoName
Add-ActionOutput -Name 'make'           -Value $make
Add-ActionOutput -Name 'model'          -Value $model
Add-ActionOutput -Name 'title'          -Value $title
Add-ActionOutput -Name 'package'        -Value $package
Add-ActionOutput -Name 'repo-is-plugin' -Value ($repoIsPlugin.ToString().ToLower())

Add-ActionEnv -Name 'REPO_NAME'      -Value $repoName
Add-ActionEnv -Name 'REPO_FULL_NAME' -Value $repoFullName
Add-ActionEnv -Name 'REPO_IS_PLUGIN' -Value $repoIsPlugin
Add-ActionEnv -Name 'EPI_TITLE'      -Value $title
Add-ActionEnv -Name 'EPI_PACKAGE'    -Value $package

Add-ActionSummary "- **Repo**: $repoName`n"
Add-ActionSummary "- **Make / Model**: $make / $(if ($model) { $model } else { '_n/a_' })`n"
Add-ActionSummary "- **Title**: $title`n"
Add-ActionSummary "- **Package**: $package`n"
Add-ActionSummary "- **Is plugin**: $repoIsPlugin`n"
