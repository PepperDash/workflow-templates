#requires -Version 7.0
<#
  Pushes every .nupkg in the output dir to nuget.org — ONLY when the repo is
  owned by <required-owner> AND is public. Fail-closed; no caller opt-in.

  Inputs (env): INPUT_NUGET_API_KEY (required), INPUT_OUTPUT_DIR,
                INPUT_REQUIRED_OWNER (default 'pepperdash')
  Context (env): GITHUB_REPOSITORY_OWNER, GH_REPO_VISIBILITY
    (action.yml maps github.event.repository.visibility -> GH_REPO_VISIBILITY)
#>
. "$PSScriptRoot/../../_common/action.ps1"

$apiKey  = Get-ActionInput -Name 'nuget-api-key' -Required
$outDir  = Get-ActionInput -Name 'output-dir' -Default 'output'
$reqOwner = (Get-ActionInput -Name 'required-owner' -Default 'pepperdash').ToLower()

$owner = ($env:GITHUB_REPOSITORY_OWNER ?? '').ToLower()
$visibility = ($env:GH_REPO_VISIBILITY ?? '').ToLower()

Add-ActionSummary "### Nuget.org`n"
Write-Host "Repository Owner: $owner   Visibility: $visibility"

if ($owner -ne $reqOwner -or $visibility -ne 'public') {
  $msg = "Repository is not a public $reqOwner repo; skipping publish to NuGet.org."
  Write-Warning $msg
  Add-ActionSummary "$msg`n"
  exit 0
}

$nupkgFiles = Get-ChildItem -Path ".\$outDir" -Recurse -Filter *.nupkg -ErrorAction SilentlyContinue
if (@($nupkgFiles).Count -eq 0) {
  $msg = "No .nupkg files found in .\$outDir; nothing to publish to NuGet.org."
  Write-Warning $msg
  Add-ActionSummary "⚠️ $msg`n"
  exit 0
}

nuget setApiKey $apiKey -Source https://api.nuget.org/v3/index.json

$failed = @()
foreach ($pkg in $nupkgFiles) {
  Write-Host "Pushing $($pkg.Name) to NuGet.org..."
  nuget push $pkg.FullName -Source https://api.nuget.org/v3/index.json -SkipDuplicate
  if ($LASTEXITCODE -ne 0) {
    $failed += $pkg.Name
    Add-ActionSummary "❌ Failed to push $($pkg.Name) (exit $LASTEXITCODE)`n"
  } else {
    Add-ActionSummary "- Pushed $($pkg.Name)`n"
  }
}
if ($failed.Count -gt 0) {
  Stop-Action "Failed to push: $($failed -join ', ')"
}
