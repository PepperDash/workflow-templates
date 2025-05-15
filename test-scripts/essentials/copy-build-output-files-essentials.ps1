# TESTING - Essentials
# $Env:GITHUB_WORKSPACE = "C:\_pd-github\pd\Essentials"
# $env:SOLUTION_FILE = "PepperDashEssentials.3Series"
# $env:SOLUTION_PATH = "PepperDashEssentials.3Series.sln"
# $env:REPO_FULL_NAME = "PepperDash/Essentials"
# $env:REPO_NAME = "Essentials"

# C:\_pd-github\pd\Essentials\src\PepperDashEssentials\bin\PepperDashEssentials.cpz
# D:\a\Essentials\Essentials\src\PepperDashEssentials\bin\PepperDashEssentials.cpz

# TESTING - PepperDashCore
$Env:GITHUB_WORKSPACE = "C:\_pd-github\pd\PepperDashCore"
$env:SOLUTION_FILE = "Pepperdash_Core.3Series"
$env:SOLUTION_PATH = "PepperDash_Core.3Series.sln"
$env:REPO_FULL_NAME = "PepperDash/PepperDashCore"
$env:REPO_NAME = "PepperDashCore"

# TESTING - Global
$env:GITHUB_ENV = ".\output\github-env.txt"
$env:GITHUB_STEP_SUMMARY = ".\output\github-step-summary.txt"
$env:BUILD_TYPE = "Debug" # or "Release"

$env:REPO_IS_PLUGIN = "False"
$env:EPI_TITLE = ""
$env:EPI_PACKAGE = ""
$env:VERSION = "999.999.999"

$destinationDir = ".\output"

# Remove files in $destinationDir that match $validExtensions or ".dll"
$extensions += @(".cpz", ".clz", "cplz", ".dll", ".nuspec")
Get-ChildItem -Path $destinationDir | Where-Object { $extensions -contains $_.Extension } | ForEach-Object {
    Write-Output "Deleting file: $($_.FullName)"
    Remove-Item -Path $_.FullName -Force
}
Write-Output "`n"

# ^^^^ Test variable data for local testing

# GitHub Actions environment variables
$sourceDir = "$Env:GITHUB_WORKSPACE" 
$destinationDir = "$Env:GITHUB_WORKSPACE\output"
$package = $Env:EPI_PACKAGE
$version = $Env:VERSION
$plugin = ($Env:REPO_IS_PLUGIN).ToLower()
$buildDir = "\\bin\\"

# Define the target file extensions (with leading dot)
$validExtensions = @(".cpz", ".clz")

# Create the include patterns for Get-ChildItem -Include
$includePatterns = $validExtensions | ForEach-Object { "*$_" }                    

Write-Output "Target File Extensions: $($validExtensions -join ', ')"
Write-Output "Include Patterns: $($includePatterns -join ', ')"
Write-Output "Source Directory: $sourceDir"
Write-Output "Destination Directory: $destinationDir"
Write-Output "Package Name: $package"
Write-Output "Version: $version"
Write-Output "Plugin: $plugin"
Write-Output "`n"

# Create the destination directory if it doesn't exist.
if (Test-Path -Path $destinationDir) {
    Write-Output "Destination '$destinationDir' already exists. Deleting contents..."
    Get-ChildItem -Path $destinationDir | Remove-Item -Force
    Write-Output "`n"
}
else {
    Write-Output "Destination '$destinationDir' does not exist. Creating it..."
    New-Item -ItemType Directory -Force -Path $destinationDir
    Write-Output "`n"
}

switch -Wildcard ($env:REPO_FULL_NAME.ToLower()) {
    "pepperdash/essentials" {
        $validExtensions += @(".dll")
        $includePatterns += @("*.dll")
    }
    "pepperdash/pepperdashcore" {
        
    }
}

Write-Output "`n"
Write-Output "Source Directory Contents:"
Get-ChildItem -Path $sourceDir | ForEach-Object { Write-Output $_.FullName }

Write-Output "Searching for nuspec files in $sourceDir..."
# Search the $sourceDir for any file with extension *.nuspec and copy to the $destinationDir
Get-ChildItem -Path $sourceDir -Recurse | Where-Object { 
    $_.Extension -eq ".nuspec" 
} | ForEach-Object {
    Write-Output "Copying $($_.Name) to $destinationDir"
    $_ | Copy-Item -Destination .\ -Force
    $nuspec_file = $_.BaseName
    Write-Output "Nuspec File: $nuspec_file"
    Write-Output "NUSPEC_FILE=$($nuspec_file)" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
}

Write-Output "`n"
Write-Output "$sourceDir Directory Contents:"
Get-ChildItem -Path "$sourceDir" -Recurse | Where-Object { 
    # $_.FullName -contains "$($buildDir -replace '\\', '\\\\')" -and $_.FullName -notmatch "\\packages\\" -and $validExtensions -contains $_.Extension
    $_.FullName -notmatch "\\packages\\" -and $validExtensions -contains $_.Extension
} | ForEach-Object { Write-Output $_.FullName }

# Find files recursively in the source directory with the specified extensions
# $filesToCopy = Get-ChildItem -Path $sourceDir -Recurse -Include $includePatterns | Where-Object { -not $_.FullName.Contains("\packages\") }
$filesToCopy = Get-ChildItem -Path $sourceDir -Recurse -Include $includePatterns | Where-Object { 
    -not $_.FullName.Contains("\\packages\\") -and $_.FullName -match "$buildDir" 
}

# Create a list to store all files to copy, including matching base name files
$allFilesToCopy = @()

# Iterate through each file found with the initial include patterns
$filesToCopy | ForEach-Object {
    $file = $_
    $baseName = $file.BaseName

    # Add the current file to the list
    $allFilesToCopy += $file

    # Search for any files in $sourceDir with a matching base name or matching the EPI package name
    $matchingFiles = Get-ChildItem -Path $sourceDir -Recurse | Where-Object { 
        $_.BaseName -eq $baseName -and $_.Extension -eq ".dll" 
    }

    # Add the matching files to the list
    $allFilesToCopy += $matchingFiles

    # Add the matching files to the list
    $allFilesToCopy += $matchingFiles
}

Write-Output "`n"
Write-Output "Found $($allFilesToCopy.Count) files to copy."
Write-Output $allFilesToCopy | ForEach-Object { $_.FullName }

# Remove duplicates from the list
$allFilesToCopy = $allFilesToCopy | Sort-Object FullName -Unique

# Copy all files to the destination directory
$allFilesToCopy | ForEach-Object {
    Write-Output "Copying $($_.FullName) to $destinationDir"
    $_ | Copy-Item -Destination $destinationDir -Force
}

Write-Output "`n"
Write-Output "File copy process completed."
Write-Output "Destination Directory Contents:"
Get-ChildItem -Path $destinationDir | ForEach-Object { Write-Output $_.FullName }

Write-Output "`n"
Write-Output "Renaming files in $destinationDir to include version '$version'..."

$validExtensions.Clear()
$validExtensions += @(".cpz", ".clz")
# Rename the copied files in the destination directory
Write-Host "Valid Extensions: $($validExtensions -join ', ')"
Get-ChildItem -Path $destinationDir | Where-Object { $validExtensions -contains $_.Extension } | ForEach-Object {
    if($_.Name -match "PepperDashEssentials" -or $_.Name -match "PepperDashCore" -or $_.Name -match "PepperDash_Core") {        
        # Remove the version number from the file name
        $oldName = $_.Name
        $baseName = $_.BaseName
        $extension = $_.Extension # Includes the dot (.)
        $newName = "$baseName.$version$extension" -Replace '.3Series', ''
                            
        Write-Output "- '$oldName' to '$newName'"    
        Rename-Item -Path $_.FullName -NewName $newName -Force    
    }
}

Write-Output "`n"
Write-Output "File renaming process completed."
Write-Output "Contents of destination directory ($destinationDir):"
Get-ChildItem -Path $destinationDir

Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value "## Copy build output files`n"
Get-ChildItem -Path $destinationDir | ForEach-Object {
    Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value "- $($_.Name)`n"
}