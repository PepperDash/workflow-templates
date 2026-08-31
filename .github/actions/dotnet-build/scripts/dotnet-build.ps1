#requires -Version 7.0
<#
  Runs `dotnet build` for a 4-Series solution, captures the log, writes a summary.

  Inputs (env INPUT_*): solution-file, build-type, version, extra-args,
    package-tags, repository-url, release-notes
#>
. "$PSScriptRoot/../../_common/action.ps1"

$solutionFile = Get-ActionInput -Name 'solution-file' -Required
$buildType    = Get-ActionInput -Name 'build-type' -Required
$version      = Get-ActionInput -Name 'version' -Required
$extraArgs    = Get-ActionInput -Name 'extra-args'
$packageTags  = Get-ActionInput -Name 'package-tags'
$repoUrl      = Get-ActionInput -Name 'repository-url'
$releaseNotes = Get-ActionInput -Name 'release-notes'

Add-ActionSummary "## Build Solution`n"

$sln = ".\$solutionFile.sln"
if (-not (Test-Path -Path $sln)) {
  Stop-Action "Solution '$sln' not found at the repo root."
}

$dnArgs = [System.Collections.Generic.List[string]]::new()
'build', $sln,
  '/p:Platform=Any CPU',
  "/p:Configuration=$buildType",
  "/p:Version=$version",
  '/p:IncludeSourceRevisionInInformationalVersion=false' | ForEach-Object { $dnArgs.Add($_) }
if ($packageTags -ne '') { $dnArgs.Add("/p:PackageTags=$packageTags") }
if ($repoUrl -ne '') {
  $dnArgs.Add("/p:RepositoryUrl=$repoUrl")
  $dnArgs.Add("/p:PackageProjectUrl=$repoUrl")
}
if ($releaseNotes -ne '') { $dnArgs.Add("/p:PackageReleaseNotes=$releaseNotes") }
if ($extraArgs -ne '') { $extraArgs.Split(' ', [StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $dnArgs.Add($_) } }
$dnArgs.Add('-m')

$buildOutput = dotnet @dnArgs 2>&1
$exit = $LASTEXITCODE
$buildOutput | Out-String | Write-Host
$buildOutput | Out-String | Out-File -FilePath 'build-output.log' -Encoding utf8

if ($exit -eq 0) {
  Add-ActionSummary "**BUILD SUCCESS**`n"
  Add-ActionSummary "- **Configuration**: $buildType`n"
  Add-ActionSummary "- **Version**: $version`n"
  Add-ActionSummary "- **Solution**: $solutionFile.sln`n"
} else {
  Stop-Action "**BUILD FAILED** — exit code $exit. See the step log and the build-output-log artifact."
}
