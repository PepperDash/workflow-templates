$env:GITHUB_WORKSPACE = "C:\_pd-github\pd\epi-uintled-colorlightZ6"
$env:GITHUB_ENV = ".\output\github-env.txt"
$env:GITHUB_STEP_SUMMARY = ".\output\github-step-summary.txt"

# $repoFullName = "https://github.com/pepperdash/epi-uintled-colorlight-z6"
# $repoFullName = "https://github.com/pepperdash/Essentials"
$repoFullName = "https://github.com/pepperdash/PepperDashCore"


# ^^^^ Test variable data for local testing

$workspace = $Env:GITHUB_WORKSPACE
$filter = "*.3Series.sln"

$solution_file = Get-ChildItem -Path $workspace -Filter $filter -Recurse

Write-Output "Solution File: $($solution_file.BaseName)"
Write-Output "Solution Path: $($solution_file.Name)"

Write-Output "SOLUTION_FILE=$($solution_file.BaseName)" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
Write-Output "SOLUTION_PATH=$($solution_file.Name)" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append


# WIP - Move file naming to this section
# $repoFullName = "${{ github.repository }}"
$repoName = $repoFullName.Split('/')[-1]
$makeModelParts = $repoName -split '-'
if (-not $makeModelParts) {
    Write-Error "Error: \$makeModelParts is null or empty."
}
else {
    Write-Output "Number of items in \$($makeModelParts): $($makeModelParts.Count)"
    switch ($makeModelParts.Count) {
        0 {
            Write-Error "Error: \$makeModelParts is null or empty."
        }
        1 {
            # org/repoName
            $make = $makeModelParts[0].Replace(' ', '')
            $model = ''
        }
        2 {
            # org/repo-name
            $make = $makeModelParts[0].Replace(' ', '')
            $model = $makeModelParts[1].Replace(' ', '')
        }
        Default {            
            # org/epi-make-model
            $make = $makeModelParts[1].Replace(' ', '')
            $model = ($makeModelParts[2..($makeModelParts.Count - 1)] -join '').Replace(' ', '')
        }
    }
}

$repoIsPlugin = $false
if($model -eq '') {
    # assume non-plugin repo && name override is automatically generated
    $title = $make
    $package = $title -replace ' ', ''
    $repoIsPlugin = $false
}
else {
    # TODO [ ] review for standardization - original title implementation
    $title = (Get-Culture).TextInfo.ToTitleCase("$make") + (Get-Culture).TextInfo.ToTitleCase("$model")
    
    # TODO [ ] review for standardization - 4series uses `$make.$model`
    #$title = (Get-Culture).TextInfo.ToTitleCase("$make.$model")
    
    # TODO [ ] review for standardization - 4series build uses `Plugins`
    $package = "PepperDash.Essentials.Plugin." + ($title -replace ' ', '')
    $repoIsPlugin = $true
}

Write-Output "Repo Full Name: $repoFullName"
Write-Output "Repo Name: $repoName"
Write-Output "Repo is Plugin: $repoIsPlugin"
Write-Output "Make: $make"
Write-Output "Model: $model"
Write-Output "Title: $title"
Write-Output "Package: $package"

Write-Output "REPO_FULL_NAME=$repoFullName" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
Write-Output "REPO_NAME=$repoName" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
Write-Output "REPO_IS_PLUGIN=$repoIsPlugin" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
Write-Output "EPI_TITLE=$title" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
Write-Output "EPI_PACKAGE=$package" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append