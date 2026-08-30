# Shared helpers for composite-action scripts.
#
# Dot-source from a script at .github/actions/<name>/scripts/<file>.ps1:
#   . "$PSScriptRoot/../../_common/action.ps1"
#
# Scripts read inputs from $env:INPUT_<UPPER_SNAKE> (set by the action.yml step's
# env: block) and write results to $env:GITHUB_OUTPUT / $env:GITHUB_STEP_SUMMARY,
# which are plain file paths — so tests just point them at temp files and assert.

$ErrorActionPreference = 'Stop'

function Get-ActionInput {
  param(
    [Parameter(Mandatory)][string]$Name,
    [string]$Default = '',
    [switch]$Required
  )
  $key = "INPUT_" + ($Name.ToUpper() -replace '[-\s]', '_')
  $value = [Environment]::GetEnvironmentVariable($key)
  if ($null -eq $value -or $value -eq '') {
    if ($Required) { Stop-Action "Required input '$Name' ($key) was not provided." }
    return $Default
  }
  return $value
}

function Add-ActionOutput {
  param([Parameter(Mandatory)][string]$Name, [string]$Value = '')
  if ($env:GITHUB_OUTPUT) {
    "$Name=$Value" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
  }
  Write-Host "output: $Name=$Value"
}

function Add-ActionEnv {
  param([Parameter(Mandatory)][string]$Name, [string]$Value = '')
  if ($env:GITHUB_ENV) {
    "$Name=$Value" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
  }
  [Environment]::SetEnvironmentVariable($Name, $Value)
}

function Add-ActionSummary {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
  if ($env:GITHUB_STEP_SUMMARY) {
    Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $Text
  }
  Write-Host $Text
}

function Stop-Action {
  param([Parameter(Mandatory)][string]$Message)
  Add-ActionSummary "❌ $Message"
  Write-Error $Message
  exit 1
}
