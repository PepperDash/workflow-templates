#requires -Version 7.0
<#
  Detects whether the calling repo is a C# Essentials plugin and extracts the
  built assembly name, factory TypeNames, and MinimumEssentialsFrameworkVersion.

  Inputs (env):
    INPUT_BUILD_TYPE   Release | Debug  (default Release)
    INPUT_PACKAGE      expected package id / primary assembly base name (fallback)
  Outputs: is-csharp-plugin, assembly-name, type-names, type-names-list,
           min-framework-version
#>
. "$PSScriptRoot/../../_common/action.ps1"

$buildType = Get-ActionInput -Name 'build-type' -Default 'Release'
$package   = Get-ActionInput -Name 'package'
$root = if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).Path }

Add-ActionSummary "## Plugin metadata`n"

$isCsharpPlugin = $false
$typeNames = [System.Collections.Generic.List[string]]::new()
$minFwVersions = [System.Collections.Generic.List[string]]::new()

$csFiles = Get-ChildItem -Path $root -Recurse -Filter *.cs -File -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -notmatch '[\\/](obj|bin|packages)[\\/]' }

foreach ($file in $csFiles) {
  $text = Get-Content -Raw -Path $file.FullName
  if ($text -notmatch 'EssentialsPlugin\w*Factory') { continue }

  # TypeNames = new List<string>( ) { "a", "b" };   (single or multi-line, opt parens)
  foreach ($m in [regex]::Matches($text, 'TypeNames\s*=\s*new\s+List<string>\s*\(?\s*\)?\s*\{(?<body>[^}]*)\}')) {
    $isCsharpPlugin = $true
    foreach ($s in [regex]::Matches($m.Groups['body'].Value, '"([^"]+)"')) {
      $typeNames.Add($s.Groups[1].Value)
    }
  }
  foreach ($m in [regex]::Matches($text, 'MinimumEssentialsFrameworkVersion\s*=\s*"([^"]+)"')) {
    $minFwVersions.Add($m.Groups[1].Value)
  }
}

$uniqueTypeNames = $typeNames | Select-Object -Unique
$typeNamesSpace = ($uniqueTypeNames -join ' ')
$typeNamesList  = ($uniqueTypeNames -join ', ')

$minFw = ''
if ($minFwVersions.Count -gt 0) {
  $minFw = ($minFwVersions | Sort-Object {
    try { [version]($_ -replace '-.*$') } catch { [version]'0.0.0' }
  } -Descending | Select-Object -First 1)
}

# Primary assembly: prefer one matching the package id, else the newest
# non-third-party dll under bin\<build-type>.
$assemblyName = ''
$dlls = Get-ChildItem -Path $root -Recurse -Filter *.dll -File -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -match "[\\/]bin[\\/]$buildType" -and $_.FullName -notmatch '[\\/]packages[\\/]' }
if ($package -ne '') {
  $match = $dlls | Where-Object { $_.BaseName -eq $package } | Select-Object -First 1
  if ($match) { $assemblyName = $match.BaseName }
}
if ($assemblyName -eq '' -and $dlls.Count -gt 0) {
  $assemblyName = ($dlls | Sort-Object LastWriteTime -Descending | Select-Object -First 1).BaseName
}

Add-ActionOutput -Name 'is-csharp-plugin'      -Value ($isCsharpPlugin.ToString().ToLower())
Add-ActionOutput -Name 'assembly-name'         -Value $assemblyName
Add-ActionOutput -Name 'type-names'            -Value $typeNamesSpace
Add-ActionOutput -Name 'type-names-list'       -Value $typeNamesList
Add-ActionOutput -Name 'min-framework-version' -Value $minFw

Add-ActionSummary "- **C# Essentials plugin**: $isCsharpPlugin`n"
Add-ActionSummary "- **Assembly**: $(if ($assemblyName) { $assemblyName } else { '_not found_' })`n"
Add-ActionSummary "- **Factory TypeNames**: $(if ($typeNamesList) { $typeNamesList } else { '_none_' })`n"
Add-ActionSummary "- **MinimumEssentialsFrameworkVersion**: $(if ($minFw) { $minFw } else { '_none_' })`n"
