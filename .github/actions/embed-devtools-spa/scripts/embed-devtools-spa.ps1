#requires -Version 7.0
<#
  Downloads an essentials-devtools release zip and embeds it (stored) as
  essentials-devtools.zip inside every .cpz under the output dir. No-op when
  INPUT_DEVTOOLS_VERSION is empty.

  Inputs (env): INPUT_DEVTOOLS_VERSION, INPUT_OUTPUT_DIR (default 'output')
#>
. "$PSScriptRoot/../../_common/action.ps1"

$tag = Get-ActionInput -Name 'devtools-version'
$outDir = Get-ActionInput -Name 'output-dir' -Default 'output'
$root = if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).Path }

if ([string]::IsNullOrWhiteSpace($tag)) {
  Write-Host "devtools-version is empty; skipping SPA embed."
  exit 0
}

Add-ActionSummary "## Embed essentials-devtools SPA`n"
$url = "https://github.com/PepperDash/essentials-devtools/releases/download/$tag/essentials-devtools-$tag.zip"
Write-Host "Downloading essentials-devtools $tag from $url"
Invoke-WebRequest -Uri $url -OutFile "essentials-devtools.zip" -UseBasicParsing

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$spaZip = (Resolve-Path "essentials-devtools.zip").Path
$cpzFiles = @(Get-ChildItem -Recurse -Path (Join-Path $root $outDir) -Filter '*.cpz' -ErrorAction SilentlyContinue)
if ($cpzFiles.Count -eq 0) {
  Stop-Action "No .cpz files found under $outDir to embed the SPA into."
}

foreach ($cpzFile in $cpzFiles) {
  Write-Host "Embedding SPA zip into $($cpzFile.FullName)"
  $zip = [System.IO.Compression.ZipFile]::Open($cpzFile.FullName, [System.IO.Compression.ZipArchiveMode]::Update)
  try {
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
      $zip, $spaZip, 'essentials-devtools.zip',
      [System.IO.Compression.CompressionLevel]::NoCompression) | Out-Null
  } finally {
    $zip.Dispose()
  }
  Add-ActionSummary "- $($cpzFile.Name)`n"
}
