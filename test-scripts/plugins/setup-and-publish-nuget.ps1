$workspace = "C:\_pd-github\pd\epi-uintled-colorlightZ6"
$env:GITHUB_ENV = ".\output\github-env.txt"
$env:GITHUB_STEP_SUMMARY = ".\output\github-step-summary.txt"
$owner = "SomeOtherThingPepperDash-Services"
$visibility = "Public"
# ^^^^ Test variable data for local testing

Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value "### Nuget.org`n"
          
# $owner = "${{ github.repository_owner }}"
# $visibility = "${{ github.event.repository.visibility }}"

Write-Output "Repository Owner: $owner"
Write-Output "Repository Visibility: $visibility"

if ($owner.ToLower() -notlike '*pepperdash*' -or $visibility.ToLower() -ne 'public') {
    Write-Error "Repository is not public, skipping publishing to NuGet.org." | Add-Content -Path $env:GITHUB_STEP_SUMMARY
    exit 0
}
else {
    if (-not (Test-Path -Path ".\output\*.nupkg")) {
        $msg = "No NuGet package found in the output directory. Check if the build process created the package correctly."
        Write-Error $msg | Add-Content -Path $env:GITHUB_STEP_SUMMARY
        exit 1
    }
      
    Write-Output "Publishing {github.repository} to NuGet.org"
    # Write-Output "Publishing ${{ github.repository }} to NuGet.org" | Add-Content -Path $env:GITHUB_STEP_SUMMARY
    # nuget setApiKey ${{ secrets.NUGET_API_KEY }} -Source https://api.nuget.org/v3/index.json
    # nuget push .\output\*.nupkg -Source https://api.nuget.org/v3/index.json
}

