# TESTING - Essentials - Get Project Info
$Env:GITHUB_WORKSPACE = "C:\_pd-github\pd\Essentials"
$repoFullName = "PepperDash/Essentials"

# TESTING - PepperDashCore - Get Project Info
# $Env:GITHUB_WORKSPACE = "C:\_pd-github\pd\PepperDashCore"
# $repoFullName = "PepperDash/PepperDashCore"

# TESTING - global variables
$env:GITHUB_ENV = ".\output\github-env.txt"
$env:GITHUB_STEP_SUMMARY = ".\output\github-step-summary.txt"

# ^^^^ Test variable data for local testing

$workspace = $Env:GITHUB_WORKSPACE
$filter = "*.3Series.sln"

$solution_file = Get-ChildItem -Path $workspace -Filter $filter -Recurse -Exclude "packages"

Write-Output "Solution File: $($solution_file.BaseName)"
Write-Output "Solution Path: $($solution_file.Name)"
Write-Output "Solution Directory: $($solution_file.DirectoryName)"

Write-Output "SOLUTION_FILE=$($solution_file.BaseName)" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
Write-Output "SOLUTION_PATH=$($solution_file.Name)" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
Write-Output "SOLUTION_DIR=$($solution_file.DirectoryName)" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append

# WIP - Move file naming to this section
# $repoFullName = "${{ github.repository }}"
$repoName = $repoFullName.Split('/')[-1]

Write-Output "Repo Full Name: $repoFullName"
Write-Output "Repo Name: $repoName"
Write-Output "Repo is Plugin: $repoIsPlugin"

Write-Output "REPO_FULL_NAME=$repoFullName" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
Write-Output "REPO_NAME=$repoName" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
Write-Output "REPO_IS_PLUGIN=$repoIsPlugin" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append


# switch -Regex ($repoFullName) {
#     '(?i)Essentials' {
#         Write-Output "Repository: '$repoName'"
#         $repoIsPlugin = $false
#     }
#     '(?i)PepperDashCore' {
#         Write-Output "Repository: '$repoName'"
#         $repoIsPlugin = $false
#     }
#     default {
#         Write-Error "Repository name '$repoName' is not valid. Expected 'Essentials' or 'PepperDashCore' (case insensitive)."
#         exit 1
#     }
# }


