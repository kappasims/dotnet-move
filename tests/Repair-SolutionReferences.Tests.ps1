#requires -Modules Pester

BeforeAll {
    Import-Module ([System.IO.Path]::Combine($PSScriptRoot, '..', 'src', 'DotnetMove.Core', 'DotnetMove.Core.psd1')) -Force

    function New-RepairFixtureBase {
        # App -> Lib in a solution. Returns the repo root with Lib still in place.
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("dotnetmove_rep_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $root | Out-Null
        Push-Location $root
        try {
            & git init -q
            & dotnet new classlib -n Lib -o (Join-Path $root 'Lib') | Out-Null
            & dotnet new console -n App -o (Join-Path $root 'App') | Out-Null
            & dotnet add (Join-Path $root (Join-Path 'App' 'App.csproj')) reference (Join-Path $root (Join-Path 'Lib' 'Lib.csproj')) | Out-Null
            & dotnet new sln -n Demo --format slnx | Out-Null
            & dotnet sln Demo.slnx add (Join-Path $root (Join-Path 'Lib' 'Lib.csproj')) (Join-Path $root (Join-Path 'App' 'App.csproj')) | Out-Null
        } finally { Pop-Location }
        return $root
    }

    function New-MovedFixture {
        # Lib's folder is moved by hand (no reconciliation), so the .sln entry and App's
        # <ProjectReference> dangle but Lib.csproj still exists at the new path.
        $root = New-RepairFixtureBase
        New-Item -ItemType Directory -Path (Join-Path $root 'libs') | Out-Null
        Move-Item -LiteralPath (Join-Path $root 'Lib') -Destination (Join-Path $root (Join-Path 'libs' 'Lib'))
        return $root
    }

    function New-DeletedFixture {
        # Lib is deleted outright, so the dangling entries have no new home.
        $root = New-RepairFixtureBase
        Remove-Item -LiteralPath (Join-Path $root 'Lib') -Recurse -Force
        return $root
    }
}

Describe 'Repair-SolutionReferences' {
    It 'reports dangling entries and whether each can be relocated' {
        $root = New-MovedFixture
        try {
            $probs = Repair-SolutionReferences -RepoRoot $root
            ($probs.Kind | Sort-Object -Unique) | Should -Contain 'Solution'
            ($probs.Kind | Sort-Object -Unique) | Should -Contain 'Reference'
            ($probs.Resolution | Sort-Object -Unique) | Should -Contain 'Relocatable'
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 're-points dangling entries at the moved project with -Fix (and it builds)' {
        $root = New-MovedFixture
        try {
            Repair-SolutionReferences -RepoRoot $root -Fix -Confirm:$false | Out-Null
            $list = (& dotnet sln (Join-Path $root 'Demo.slnx') list) -join "`n"
            $list | Should -Match 'libs[\\/]Lib[\\/]Lib\.csproj'
            & dotnet build (Join-Path $root 'Demo.slnx') 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 0
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'leaves a genuinely-missing entry for -Prune, which removes it' {
        $root = New-DeletedFixture
        try {
            # -Fix cannot relocate a deleted project; the entry stays.
            Repair-SolutionReferences -RepoRoot $root -Fix -Confirm:$false | Out-Null
            (& dotnet sln (Join-Path $root 'Demo.slnx') list) -join "`n" | Should -Match 'Lib[\\/]Lib\.csproj'
            # -Prune removes the gone entries.
            Repair-SolutionReferences -RepoRoot $root -Prune -Confirm:$false | Out-Null
            (& dotnet sln (Join-Path $root 'Demo.slnx') list) -join "`n" | Should -Not -Match 'Lib[\\/]Lib\.csproj'
            (Get-Content (Join-Path $root (Join-Path 'App' 'App.csproj')) -Raw) | Should -Not -Match 'Lib\.csproj'
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
