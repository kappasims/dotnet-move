#requires -Modules Pester

BeforeAll {
    . (Join-Path $PSScriptRoot TestHelpers.ps1)
    Import-Module (Join-Path $PSScriptRoot (Join-Path '..' (Join-Path 'src' (Join-Path 'DotnetMove.Core' ('DotnetMove.Core.psd1'))))) -Force

    function New-Fixture {
        # Build a throwaway 2-project solution: App -> Lib, in a fresh temp git repo.
        param([ValidateSet('sln', 'slnx')][string]$Format = 'slnx')
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("dotnetmove_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $root | Out-Null
        Push-Location $root
        try {
            & git init -q
            New-StubClassLib -Name Lib -Directory (Join-Path $root (Join-Path 'src' ('Lib'))) | Out-Null
            New-StubConsole -Name App -Directory (Join-Path $root (Join-Path 'src' ('App'))) | Out-Null
            & dotnet new sln -n Demo --format $Format | Out-Null
            $sln = (Get-ChildItem -LiteralPath $root -File -Include '*.sln', '*.slnx').FullName
            & dotnet sln $sln add (Join-Path $root (Join-Path 'src' (Join-Path 'Lib' ('Lib.csproj')))) | Out-Null
            & dotnet sln $sln add (Join-Path $root (Join-Path 'src' (Join-Path 'App' ('App.csproj')))) | Out-Null
            & dotnet add (Join-Path $root (Join-Path 'src' (Join-Path 'App' ('App.csproj')))) reference (Join-Path $root (Join-Path 'src' (Join-Path 'Lib' ('Lib.csproj')))) | Out-Null
            & git add -A; & git commit -qm "fixture" | Out-Null
        } finally { Pop-Location }
        return $root
    }
}

Describe 'Move-DotnetProject' {
    It 'moves a referenced library and keeps the <Format> solution buildable' -ForEach @(
        @{ Format = 'slnx' }, @{ Format = 'sln' }
    ) {
        $root = New-Fixture -Format $Format
        try {
            $lib = Join-Path $root (Join-Path 'src' (Join-Path 'Lib' ('Lib.csproj')))
            $dest = Join-Path $root (Join-Path 'libs' ('Lib'))
            $sln = (Get-ChildItem -LiteralPath $root -File -Include '*.sln', '*.slnx').FullName

            Move-DotnetProject -Project $lib -Destination $dest -RepoRoot $root -NoBuild -Confirm:$false

            # File physically moved.
            Join-Path $dest 'Lib.csproj' | Should -Exist
            $lib | Should -Not -Exist

            # Solution lists the new path (GUIDs preserved by the CLI).
            $listed = & dotnet sln $sln list
            ($listed -join "`n") | Should -Match 'libs[\\/]Lib[\\/]Lib\.csproj'

            # Consumer reference resolves and the whole thing builds.
            & dotnet build $sln 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 0
        } finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'supports -WhatIf without moving anything and emits a plan object' {
        $root = New-Fixture
        try {
            $lib = Join-Path $root (Join-Path 'src' (Join-Path 'Lib' ('Lib.csproj')))
            $result = Move-DotnetProject -Project $lib -Destination (Join-Path $root (Join-Path 'libs' ('Lib'))) -RepoRoot $root -WhatIf
            $lib | Should -Exist
            (Join-Path $root (Join-Path 'libs' (Join-Path 'Lib' ('Lib.csproj')))) | Should -Not -Exist
            $result.Performed | Should -BeFalse
            $result.ConsumerCount | Should -Be 1
        } finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'accepts the project from the pipeline (Get-Item)' {
        $root = New-Fixture
        try {
            $lib = Join-Path $root (Join-Path 'src' (Join-Path 'Lib' ('Lib.csproj')))
            $result = Get-Item $lib | Move-DotnetProject -Destination (Join-Path $root (Join-Path 'libs' ('Lib'))) -RepoRoot $root -WhatIf
            $result.Source | Should -Match 'Lib\.csproj'
        } finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'writes a non-terminating error (not throw) for a missing project' {
        Move-DotnetProject -Project 'X:/does/not/exist.csproj' -Destination 'X:/y' -ErrorVariable errs -ErrorAction SilentlyContinue | Out-Null
        $errs | Should -Not -BeNullOrEmpty
        $errs[0].FullyQualifiedErrorId | Should -Match 'ProjectNotFound'
    }

    It 'refuses to move a project into its own subtree (no mutation)' {
        $root = New-Fixture
        try {
            $lib = Join-Path $root (Join-Path 'src' (Join-Path 'Lib' ('Lib.csproj')))
            $dest = Join-Path $root (Join-Path 'src' (Join-Path 'Lib' ('nested')))   # under the source
            Move-DotnetProject -Project $lib -Destination $dest -RepoRoot $root -NoBuild -Confirm:$false `
                -ErrorVariable errs -ErrorAction SilentlyContinue | Out-Null
            $errs[0].FullyQualifiedErrorId | Should -Match 'PathOverlap'
            $lib | Should -Exist   # nothing moved
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
