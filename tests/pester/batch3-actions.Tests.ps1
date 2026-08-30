BeforeAll {
  . "$PSScriptRoot/_helpers.ps1"
}

Describe 'update-assembly-info' {
  BeforeAll { $script:S = Get-ActionScript -Action 'update-assembly-info' -Script 'update-assembly-info.ps1' }

  It 'sets AssemblyVersion to base.* and AssemblyInformationalVersion to the full string' {
    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("ai-" + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Force -Path (Join-Path $work 'Properties') | Out-Null
    @'
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyInformationalVersion("1.0.0")]
'@ | Set-Content (Join-Path $work 'Properties/AssemblyInfo.cs')

    $r = Invoke-ActionScript -Path $S -Inputs @{ version = '2002.3.1-beta.2' } -Env @{ GITHUB_WORKSPACE = $work } -WorkDir $work -KeepWorkDir
    $r.ExitCode | Should -Be 0
    $txt = Get-Content -Raw (Join-Path $work 'Properties/AssemblyInfo.cs')
    $txt | Should -Match 'AssemblyVersion\("2002\.3\.1\.\*"\)'
    $txt | Should -Match 'AssemblyInformationalVersion\("2002\.3\.1-beta\.2"\)'
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'warns (does not fail) when there are no AssemblyInfo files' {
    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("ai-" + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $r = Invoke-ActionScript -Path $S -Inputs @{ version = '1.0.0' } -Env @{ GITHUB_WORKSPACE = $work } -WorkDir $work
    $r.ExitCode | Should -Be 0
    $r.Summary  | Should -Match 'No AssemblyInfo'
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'rejects a non x.y.z version' {
    $r = Invoke-ActionScript -Path $S -Inputs @{ version = 'v2' }
    $r.ExitCode | Should -Be 1
    $r.Summary  | Should -Match '❌ .*does not match x.y.z'
  }
}

Describe 'pack-nuget' {
  BeforeAll { $script:S = Get-ActionScript -Action 'pack-nuget' -Script 'pack-nuget.ps1' }

  It 'skips (exit 0) for the EssentialsPluginTemplate' {
    $r = Invoke-ActionScript -Path $S -Inputs @{ 'nuspec-file' = 'EssentialsPluginTemplate'; version = '1.0.0' }
    $r.ExitCode | Should -Be 0
    $r.Summary  | Should -Match 'Skipped .*template'
  }

  It 'fails clearly when the nuspec file is missing' {
    $r = Invoke-ActionScript -Path $S -Inputs @{ 'nuspec-file' = 'project'; version = '1.0.0' }
    $r.ExitCode | Should -Be 1
    $r.Summary  | Should -Match "❌ .*nuspec file '.*project.nuspec' not found"
  }

  It 'fails when no nuspec-file name is supplied' {
    $r = Invoke-ActionScript -Path $S -Inputs @{ version = '1.0.0' }
    $r.ExitCode | Should -Be 1
    $r.Summary  | Should -Match 'No nuspec file name supplied'
  }
}

Describe 'publish-nuget-org fail-closed gate' {
  BeforeAll { $script:S = Get-ActionScript -Action 'publish-nuget-org' -Script 'publish-nuget-org.ps1' }

  It 'skips for a non-PepperDash owner' {
    $r = Invoke-ActionScript -Path $S -Inputs @{ 'nuget-api-key' = 'k' } -Env @{ GITHUB_REPOSITORY_OWNER = 'SomeoneElse'; GH_REPO_VISIBILITY = 'public' }
    $r.ExitCode | Should -Be 0
    $r.Summary  | Should -Match 'not a public pepperdash repo'
  }

  It 'skips for a private PepperDash repo' {
    $r = Invoke-ActionScript -Path $S -Inputs @{ 'nuget-api-key' = 'k' } -Env @{ GITHUB_REPOSITORY_OWNER = 'PepperDash'; GH_REPO_VISIBILITY = 'private' }
    $r.ExitCode | Should -Be 0
    $r.Summary  | Should -Match 'not a public pepperdash repo'
  }

  It 'passes the gate for public PepperDash but exits 0 when there is no package' {
    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("po-" + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $r = Invoke-ActionScript -Path $S -Inputs @{ 'nuget-api-key' = 'k' } -Env @{ GITHUB_REPOSITORY_OWNER = 'PepperDash'; GH_REPO_VISIBILITY = 'public'; GITHUB_WORKSPACE = $work } -WorkDir $work
    $r.ExitCode | Should -Be 0
    $r.Summary  | Should -Match 'No .nupkg files found'
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  }
}

Describe 'add-files-to-nupkg' {
  BeforeAll {
    $script:S = Get-ActionScript -Action 'add-files-to-nupkg' -Script 'add-files-to-nupkg.ps1'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
  }

  It 'injects schema files into every .nupkg under output/' {
    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("afn-" + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Force -Path (Join-Path $work 'output/schemas') | Out-Null
    Set-Content (Join-Path $work 'output/schemas/Foo.schema.json') '{}'
    Set-Content (Join-Path $work 'output/schemas/Bar.schema.json') '{}'
    # a .nupkg is just a zip
    $stage = Join-Path $work '_pkg'; New-Item -ItemType Directory -Force -Path $stage | Out-Null
    Set-Content (Join-Path $stage 'x.nuspec') '<package/>'
    [System.IO.Compression.ZipFile]::CreateFromDirectory($stage, (Join-Path $work 'output/My.Plugin.1.0.0.nupkg'))

    $r = Invoke-ActionScript -Path $S -Inputs @{ 'source-dir' = 'output/schemas'; 'target-path' = 'schemas'; pattern = '*.schema.json' } -Env @{ GITHUB_WORKSPACE = $work } -WorkDir $work -KeepWorkDir
    $r.ExitCode | Should -Be 0
    $zip = [System.IO.Compression.ZipFile]::OpenRead((Join-Path $work 'output/My.Plugin.1.0.0.nupkg'))
    try { $names = $zip.Entries.FullName } finally { $zip.Dispose() }
    $names | Should -Contain 'schemas/Foo.schema.json'
    $names | Should -Contain 'schemas/Bar.schema.json'
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'no-op (exit 0) when the source dir is empty and required=false' {
    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("afn-" + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Force -Path (Join-Path $work 'output/schemas') | Out-Null
    $r = Invoke-ActionScript -Path $S -Inputs @{ 'source-dir' = 'output/schemas' } -Env @{ GITHUB_WORKSPACE = $work } -WorkDir $work
    $r.ExitCode | Should -Be 0
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  }
}

Describe 'embed-devtools-spa' {
  BeforeAll { $script:S = Get-ActionScript -Action 'embed-devtools-spa' -Script 'embed-devtools-spa.ps1' }

  It 'is a no-op (exit 0) when devtools-version is empty' {
    $r = Invoke-ActionScript -Path $S -Inputs @{ 'devtools-version' = '' }
    $r.ExitCode | Should -Be 0
  }
}

Describe 'dotnet-build input validation' {
  BeforeAll { $script:S = Get-ActionScript -Action 'dotnet-build' -Script 'dotnet-build.ps1' }

  It 'fails clearly when the solution file is missing' {
    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("db-" + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $r = Invoke-ActionScript -Path $S -Inputs @{ 'solution-file' = 'Nope'; 'build-type' = 'Release'; version = '1.0.0' } -Env @{ GITHUB_WORKSPACE = $work } -WorkDir $work
    $r.ExitCode | Should -Be 1
    $r.Summary  | Should -Match "❌ .*Solution '.*Nope.sln' not found"
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  }
}

Describe 'cleanup-failed-release (bash)' {
  BeforeAll { $script:S = Get-ActionScript -Action 'cleanup-failed-release' -Script 'cleanup-failed-release.sh' }

  It 'with no tag and fail=false: exit 0, notes nothing to do' {
    $r = Invoke-ActionScript -Path $S -Inputs @{ tag = ''; fail = 'false' }
    $r.ExitCode | Should -Be 0
    $r.Summary  | Should -Match 'nothing to clean up'
  }

  It 'with fail=true: exits 1 (job marked failed)' {
    $r = Invoke-ActionScript -Path $S -Inputs @{ tag = ''; fail = 'true' }
    $r.ExitCode | Should -Be 1
  }
}

Describe 'upload-release scripts (bash)' {
  It 'validate.sh fails when tag is empty' {
    $s = Get-ActionScript -Action 'upload-release' -Script 'validate.sh'
    $r = Invoke-ActionScript -Path $s -Inputs @{ tag = '' }
    $r.ExitCode | Should -Be 1
    $r.Summary  | Should -Match 'no tag supplied'
  }

  It 'ensure-body.sh creates a placeholder CHANGELOG when missing' {
    $s = Get-ActionScript -Action 'upload-release' -Script 'ensure-body.sh'
    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("ub-" + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $r = Invoke-ActionScript -Path $s -Inputs @{ 'body-file' = './CHANGELOG.md'; tag = 'v2002.3.1' } -WorkDir $work -KeepWorkDir
    $r.ExitCode | Should -Be 0
    (Get-Content -Raw (Join-Path $work 'CHANGELOG.md')).Trim() | Should -Be 'Release v2002.3.1'
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  }
}
