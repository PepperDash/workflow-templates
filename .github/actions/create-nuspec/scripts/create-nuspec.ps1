#requires -Version 7.0
<#
  Generates a .nuspec for a plugin repo (no-op when repo-is-plugin != "true").
  Embeds assembly name, repository URL, factory TypeNames and the minimum
  framework version. Only references LICENSE.md / README.md when they exist.

  Inputs (env INPUT_*): package, title, version, repo-name, repo-is-plugin,
    assembly-name, type-names, type-names-list, min-framework-version,
    tags, license-type, license-value, target-framework
  Outputs: nuspec-file
#>
. "$PSScriptRoot/../../_common/action.ps1"

$package        = Get-ActionInput -Name 'package' -Required
$title          = Get-ActionInput -Name 'title' -Required
$version        = Get-ActionInput -Name 'version' -Required
$repoName       = Get-ActionInput -Name 'repo-name' -Required
$repoIsPlugin   = Get-ActionInput -Name 'repo-is-plugin' -Default 'false'
$assemblyName   = Get-ActionInput -Name 'assembly-name'
$typeNames      = Get-ActionInput -Name 'type-names'
$typeNamesList  = Get-ActionInput -Name 'type-names-list'
$minFw          = Get-ActionInput -Name 'min-framework-version'
$tagsInput      = Get-ActionInput -Name 'tags' -Default 'crestron'
$licenseType    = Get-ActionInput -Name 'license-type' -Default 'file'
$licenseValue   = Get-ActionInput -Name 'license-value' -Default 'LICENSE.md'
$targetFramework = Get-ActionInput -Name 'target-framework' -Default 'net35'

$root = if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).Path }
$repository = if ($env:GITHUB_REPOSITORY) { $env:GITHUB_REPOSITORY } else { "PepperDash/$repoName" }
$repoUrl = "https://github.com/$repository"

Add-ActionSummary "## Create Nuspec File`n"

if ($repoIsPlugin -ne 'true') {
  Add-ActionSummary "Skipped — repo-is-plugin is not ``true``.`n"
  Add-ActionOutput -Name 'nuspec-file' -Value ''
  exit 0
}

$year = (Get-Date).Year
function Esc([string]$s) { [System.Security.SecurityElement]::Escape($s) }

$tagList = [System.Collections.Generic.List[string]]::new()
$tagsInput.Split(' ', [StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $tagList.Add($_) }
if ($typeNames -ne '') { $typeNames.Split(' ', [StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $tagList.Add($_) } }
$tags = ($tagList | Select-Object -Unique) -join ' '

$descLines = [System.Collections.Generic.List[string]]::new()
$descLines.Add($repoName)
if ($assemblyName -ne '') { $descLines.Add("Assembly: $assemblyName") }
$descLines.Add("Repository: $repoUrl")
if ($typeNamesList -ne '') { $descLines.Add("Factory TypeNames: $typeNamesList") }
if ($minFw -ne '') { $descLines.Add("MinimumEssentialsFrameworkVersion: $minFw") }
$description = [System.Security.SecurityElement]::Escape(($descLines -join "`n"))

$releaseNotes = ''
if ($typeNamesList -ne '') { $releaseNotes = [System.Security.SecurityElement]::Escape("Factory TypeNames: $typeNamesList") }

Get-ChildItem -Path $root -Filter *.nuspec -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force

$fileEntries = [System.Collections.Generic.List[string]]::new()
$fileEntries.Add("        <file src='.\output\**' target='lib\$targetFramework'/>")
foreach ($extra in 'LICENSE.md', 'README.md') {
  if (Test-Path -Path (Join-Path $root $extra)) {
    $fileEntries.Add("        <file src='$extra' target=''/>")
  } else {
    Add-ActionSummary "⚠️ $extra not found — omitted from the package.`n"
  }
}
$filesBlock = $fileEntries -join "`n"

$licenseLine = ''
if ($licenseType -eq 'file') {
  if (Test-Path -Path (Join-Path $root $licenseValue)) {
    $licenseLine = "        <license type='file'>$(Esc $licenseValue)</license>"
  } else {
    Add-ActionSummary "⚠️ license file $licenseValue not found — omitted.`n"
  }
} else {
  $licenseLine = "        <license type='expression'>$(Esc $licenseValue)</license>"
}

$nuspecContent = @"
<?xml version='1.0' encoding='utf-8'?>
<package>
    <metadata>
        <id>$(Esc $package)</id>
        <version>$(Esc $version)</version>
        <title>$(Esc $title)</title>
        <authors>PepperDash Technology</authors>
        <owners>PepperDash</owners>
        <requireLicenseAcceptance>false</requireLicenseAcceptance>
$licenseLine
        <projectUrl>$(Esc $repoUrl)</projectUrl>
        <copyright>Copyright $year</copyright>
        <description>$description</description>
        <releaseNotes>$releaseNotes</releaseNotes>
        <tags>$(Esc $tags)</tags>
        <repository type='git' url='$(Esc $repoUrl)'/>
    </metadata>
    <files>
$filesBlock
    </files>
</package>
"@

$path = Join-Path $root 'project.nuspec'
Set-Content -Path $path -Value $nuspecContent -Encoding utf8
Write-Host $nuspecContent

$nuspecFile = (Get-ChildItem -Path $root -Filter *.nuspec -Recurse | Select-Object -First 1).BaseName
Add-ActionOutput -Name 'nuspec-file' -Value $nuspecFile
Add-ActionEnv    -Name 'NUSPEC_FILE' -Value $nuspecFile

Add-ActionSummary "- **Package**: $package`n"
Add-ActionSummary "- **Assembly**: $(if ($assemblyName) { $assemblyName } else { '_n/a_' })`n"
Add-ActionSummary "- **Repository**: $repoUrl`n"
Add-ActionSummary "- **Tags**: $tags`n"
if ($typeNamesList -ne '') { Add-ActionSummary "- **Factory TypeNames**: $typeNamesList`n" }
