#requires -Modules Pester

BeforeAll {
    Import-Module ([System.IO.Path]::Combine($PSScriptRoot, '..', 'src', 'DotnetMove.Core', 'DotnetMove.Core.psd1')) -Force

    function New-RepoWithNestedWorktree {
        # A repo with a .sln and a .slnx (both listing Lib), plus a linked git worktree nested
        # under .claude/worktrees/wt holding duplicate copies of all of it.
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("dotnetmove_wt_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $root | Out-Null
        Push-Location $root
        try {
            & git init -q
            & git config user.email t@t.test; & git config user.name test
            & dotnet new classlib -n Lib -o (Join-Path $root 'Lib') | Out-Null
            & dotnet new sln -n Demo --format sln | Out-Null
            & dotnet new sln -n Demo --format slnx | Out-Null
            & dotnet sln Demo.sln add (Join-Path $root (Join-Path 'Lib' 'Lib.csproj')) | Out-Null
            & dotnet sln Demo.slnx add (Join-Path $root (Join-Path 'Lib' 'Lib.csproj')) | Out-Null
            & git add -A; & git commit -qm fixture | Out-Null
            & git worktree add --quiet -b wt (Join-Path $root (Join-Path '.claude' (Join-Path 'worktrees' 'wt'))) 2>$null
        } finally { Pop-Location }
        return $root
    }
}

Describe 'Nested worktrees are excluded from repo scans' {
    It 'Find-Solutions ignores the worktree copies' {
        $root = New-RepoWithNestedWorktree
        try {
            InModuleScope DotnetMove.Core -Parameters @{ Root = $root } {
                param($Root)
                # Two solutions at the root, not the four that the worktree copy would add.
                @(Find-Solutions -Root $Root).Count | Should -Be 2
                @(Find-Solutions -Root $Root | Where-Object { $_.FullName -match 'worktrees' }) | Should -BeNullOrEmpty
            }
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'Test-SolutionConsistency does not invent a divergence from worktree duplicates' {
        $root = New-RepoWithNestedWorktree
        try {
            $probs = Test-SolutionConsistency -RepoRoot $root -WarningVariable w -WarningAction SilentlyContinue
            $probs | Should -BeNullOrEmpty                 # both root solutions list Lib: consistent
            ($w -join "`n") | Should -Not -Match 'diverges'
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
