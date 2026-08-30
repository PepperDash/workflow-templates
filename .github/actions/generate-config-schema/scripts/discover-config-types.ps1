#requires -Version 7.0
<#
  Discovers config-root type names from `.ToObject<T>(` call sites in the repo's
  C# sources. An explicit INPUT_TYPES (semicolon/comma separated) short-circuits
  discovery.

  Inputs (env): INPUT_TYPES (optional)
  Outputs: types  (semicolon-joined, deduped, sorted; empty if none)
#>
. "$PSScriptRoot/../../_common/action.ps1"

$explicit = Get-ActionInput -Name 'types'
if ($explicit -ne '') {
  Add-ActionOutput -Name 'types' -Value $explicit
  return
}

$root = if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).Path }
$found = [System.Collections.Generic.List[string]]::new()

Get-ChildItem -Path $root -Recurse -Filter *.cs -File -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -notmatch '[\\/](obj|bin|packages)[\\/]' } |
  ForEach-Object {
    $text = Get-Content -Raw -Path $_.FullName
    foreach ($m in [regex]::Matches($text, '\.ToObject<\s*([A-Za-z_][A-Za-z0-9_.]*)\s*>\s*\(')) {
      $found.Add($m.Groups[1].Value)
    }
  }

$types = $found | Sort-Object -Unique
Add-ActionOutput -Name 'types' -Value ($types -join ';')

if ($types.Count -eq 0) {
  Add-ActionSummary "## Generate config schema`nNo ``ToObject<T>()`` call sites found; skipping.`n"
} else {
  Write-Host "Config types: $($types -join ', ')"
}
