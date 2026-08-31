#requires -Version 7.0
<#
.SYNOPSIS
  Encodes PepperDash Essentials compatibility into a plugin's Major version:
  prefixed_major = (EssentialsMajor * 1000) + (semverMajor % 1000).

.DESCRIPTION
  Inputs (env INPUT_*):
    version           plain semver, e.g. "2.3.1" or "2.3.1-beta.1"   (required)
    tag               plain semver tag, e.g. "v2.3.1"                 (optional)
    essentials-major  "1" for 3-Series; blank => detect from csproj   (optional)
    csproj-filter     glob for detection, default "*.4Series.csproj"  (optional)

  Outputs: version, tag, essentials-major   +   env VERSION
#>
. "$PSScriptRoot/../../_common/action.ps1"

$inputVersion   = Get-ActionInput -Name 'version' -Required
$essentialsMajor = Get-ActionInput -Name 'essentials-major'
$csprojFilter   = Get-ActionInput -Name 'csproj-filter' -Default '*.4Series.csproj'

Add-ActionSummary "## Essentials Version Prefix`n"

if ([string]::IsNullOrWhiteSpace($essentialsMajor)) {
  $csproj = Get-ChildItem -Path . -Filter $csprojFilter -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -eq $csproj) {
    Stop-Action "No csproj matching '$csprojFilter' found and no essentials-major supplied."
  }
  Write-Host "Reading Essentials version from $($csproj.FullName)"
  [xml]$xml = Get-Content $csproj.FullName
  $ref = $xml.Project.ItemGroup.PackageReference | Where-Object { $_.Include -eq 'PepperDashEssentials' }
  if ($null -eq $ref) {
    Stop-Action "No PackageReference for 'PepperDashEssentials' in $($csproj.Name)."
  }
  $essentialsMajor = [regex]::Match([string]$ref.Version, '^(\d+)').Groups[1].Value
  if ([string]::IsNullOrWhiteSpace($essentialsMajor)) {
    Stop-Action "Could not parse a major version from PepperDashEssentials '$($ref.Version)'."
  }
}

if ($essentialsMajor -notmatch '^\d+$') {
  Stop-Action "essentials-major '$essentialsMajor' is not a non-negative integer."
}
$essentialsMajor = [int]$essentialsMajor
$baseMajor = $essentialsMajor * 1000

$m = [regex]::Match($inputVersion, '^(\d+)\.(\d+)\.(\d+)(.*)$')
if (-not $m.Success) {
  Stop-Action "Version '$inputVersion' does not match semver (x.y.z[-suffix])."
}

# Modulo 1000 keeps the prefix idempotent: an already-prefixed input (e.g.
# 1002.3.1, the newest tag semantic-release just read) re-yields 1002.3.1
# instead of inflating to 3002 / 4002 / ... on every run.
$prefixedMajor   = $baseMajor + ([int]$m.Groups[1].Value % 1000)
$prefixedVersion = "$prefixedMajor.$($m.Groups[2].Value).$($m.Groups[3].Value)$($m.Groups[4].Value)"
$prefixedTag     = "v$prefixedVersion"

Write-Host "Essentials major: $essentialsMajor (base $baseMajor)"
Write-Host "Input version:    $inputVersion"
Write-Host "Prefixed version: $prefixedVersion"
Write-Host "Prefixed tag:     $prefixedTag"

Add-ActionOutput -Name 'version'          -Value $prefixedVersion
Add-ActionOutput -Name 'tag'              -Value $prefixedTag
Add-ActionOutput -Name 'essentials-major' -Value $essentialsMajor
Add-ActionEnv    -Name 'VERSION'          -Value $prefixedVersion

Add-ActionSummary "- **Essentials Major**: $essentialsMajor`n"
Add-ActionSummary "- **Input Version**: $inputVersion`n"
Add-ActionSummary "- **Prefixed Version**: $prefixedVersion`n"
Add-ActionSummary "- **Prefixed Tag**: $prefixedTag`n"
