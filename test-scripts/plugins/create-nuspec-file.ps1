Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value "## Create Nuspec File`n"
Write-Output "Owner: ${{ github.repository_owner }}" | Add-Content -Path $env:GITHUB_STEP_SUMMARY
Write-Output "Repo: ${{ github.repository }}" | Add-Content -Path $env:GITHUB_STEP_SUMMARY
Write-Output "Repo Name: ${{ env.REPO_NAME }}" | Add-Content -Path $env:GITHUB_STEP_SUMMARY
Write-Output "Repo is Plugin: ${{ env.REPO_IS_PLUGIN }}" | Add-Content -Path $env:GITHUB_STEP_SUMMARY
Write-Output "Title: ${{ env.EPI_TITLE }}" | Add-Content -Path $env:GITHUB_STEP_SUMMARY
Write-Output "Package: ${{ env.EPI_PACKAGE }}" | Add-Content -Path $env:GITHUB_STEP_SUMMARY
Write-Output "Output Directory: ${{ github.workspace }}\output" | Add-Content -Path $env:GITHUB_STEP_SUMMARY

if ($env:REPO_IS_PLUGIN -eq 'true') {
    # Remove any existing nuspec files
    Get-ChildItem -Path .\ -Filter *.nuspec -Recurse | Remove-Item -Force

    $year = (Get-Date).Year

    # Create a new nuspec file
    $nuspecContent = @"
<?xml version='1.0' encoding='utf-8'?>
<package>
    <metadata>
        <id>${{ env.EPI_PACKAGE }}</id>
        <version>${{ env.VERSION }}</version>
        <title>${{ env.EPI_TITLE}}</title>
        <authors>PepperDash Technology</authors>
        <owners>PepperDash</owners>
        <requireLicenseAcceptance>false</requireLicenseAcceptance>
        <license type='file'>LICENSE.md</license>
        <projectUrl>https://github.com/${{ github.repository }}</projectUrl>
        <copyright>Copyright $year</copyright>
        <description>${{ env.REPO_NAME}}</description>
        <tags>crestron 3series</tags>
        <repository type='git' url='https://github.com/${{ github.repository }}'/>
    </metadata>
    <files>
        <file src='LICENSE.md' target=''/>
        <file src='README.md' target=''/>
        <file src='.\output\**' target='lib\net35'/>
    </files>
</package>
"@

    # Write the nuspec content to a file
    Write-Output $nuspecContent > ${{ github.workspace }}\project.nuspec    
    $nuspec_file = (Get-ChildItem *.nuspec -recurse).BaseName
    Write-Output "Nuspec File: $nuspec_file"
    Write-Output "NUSPEC_FILE=$($nuspec_file)" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
}

