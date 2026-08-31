#requires -Version 7.0
<#
  Locates the solution file matching a filter and exposes its base name plus the
  repo-root-relative path (4 leading path segments stripped) for c:\project mounts.

  Inputs (env): INPUT_FILTER  (required) e.g. "*.4Series.sln"
  Outputs: solution-file, solution-name, solution-dir, solution-path
#>
. "$PSScriptRoot/../../_common/action.ps1"

$filter = Get-ActionInput -Name 'filter' -Required
Add-ActionSummary "## Get Solution Info`n"

$root = if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).Path }
$matches = @(Get-ChildItem -Path $root -Filter $filter -Recurse -Exclude 'packages' -ErrorAction SilentlyContinue)

if ($matches.Count -eq 0) {
  Stop-Action "No solution file matching '$filter' found in the repository."
}
if ($matches.Count -gt 1) {
  Add-ActionSummary "⚠️ Multiple solutions match '$filter'; using the first: $($matches[0].Name)`n"
  $matches | ForEach-Object { Write-Host "  candidate: $($_.FullName)" }
}
$solution = $matches[0]
$relative = $solution.FullName -replace '(?:[^\\/]*[\\/]){4}', ''

Add-ActionOutput -Name 'solution-file' -Value $solution.BaseName
Add-ActionOutput -Name 'solution-name' -Value $solution.Name
Add-ActionOutput -Name 'solution-dir'  -Value $solution.DirectoryName
Add-ActionOutput -Name 'solution-path' -Value $relative

Add-ActionSummary "- **Solution**: $($solution.Name)`n"
Add-ActionSummary "- **Path**: $relative`n"
