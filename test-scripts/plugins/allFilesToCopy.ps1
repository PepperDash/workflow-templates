$sourceDir = "C:\_pd-github\pd\workflow-templates\output"
$validExtensions = @("*.cpz", "*.clz", "*.cplz", "*.dll")

Write-Host "All Files to Copy:"
$allFilesToCopy = Get-ChildItem -Path $sourceDir -Recurse -Include $validExtensions 
$allFilesToCopy | ForEach-Object { Write-Host " -> $($_.FullName)" }

# Display the full names of the files found
Write-Host "Sorting Files to Copy:"
$allFilesToCopy = $allFilesToCopy | Sort-Object FullName -Unique
$allFilesToCopy | ForEach-Object { Write-Host " -> $($_.FullName)" }