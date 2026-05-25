#requires -Modules Pester

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot (Join-Path '..' (Join-Path 'src' (Join-Path 'DotnetMove.Core' ('DotnetMove.Core.psd1'))))) -Force

    function New-DivergentRepo {
        # Two solutions: Both.sln lists Lib+App; Partial.slnx lists App only -> Lib diverges.
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("dotnetmove_div_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $root | Out-Null
        Push-Location $root
        try {
            & git init -q
            & dotnet new classlib -n Lib -o (Join-Path $root 'Lib') | Out-Null
            & dotnet new console  -n App -o (Join-Path $root 'App') | Out-Null
            & dotnet new sln -n Both --format sln | Out-Null
            & dotnet sln Both.sln add (Join-Path $root (Join-Path 'Lib' ('Lib.csproj'))) (Join-Path $root (Join-Path 'App' ('App.csproj'))) | Out-Null
            & dotnet new sln -n Partial --format slnx | Out-Null
            & dotnet sln Partial.slnx add (Join-Path $root (Join-Path 'App' ('App.csproj'))) | Out-Null
        } finally { Pop-Location }
        return $root
    }
}

Describe 'Test-SolutionConsistency' {
    It 'warns about and emits the divergent project' {
        $root = New-DivergentRepo
        try {
            $result = Test-SolutionConsistency -RepoRoot $root -WarningVariable warns -WarningAction SilentlyContinue
            $result.Project | Should -Match 'Lib\.csproj'
            ($result.AbsentFrom -join ',') | Should -Match 'Partial\.slnx'
            $warns | Should -Not -BeNullOrEmpty
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'escalates to a non-terminating error under -Strict' {
        $root = New-DivergentRepo
        try {
            Test-SolutionConsistency -RepoRoot $root -Strict -ErrorVariable errs -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-Null
            $errs | Should -Not -BeNullOrEmpty
            $errs[0].FullyQualifiedErrorId | Should -Match 'SolutionDivergence'
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'accepts RepoRoot from the pipeline (Get-Item)' {
        $root = New-DivergentRepo
        try {
            $result = Get-Item $root | Test-SolutionConsistency -WarningAction SilentlyContinue
            $result.Project | Should -Match 'Lib\.csproj'
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
