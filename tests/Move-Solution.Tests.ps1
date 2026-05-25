#requires -Modules Pester

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot (Join-Path '..' (Join-Path 'src' (Join-Path 'DotnetMove.Core' ('DotnetMove.Core.psd1'))))) -Force

    function New-SlnFixture {
        param([ValidateSet('sln', 'slnx')][string]$Format = 'slnx')
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("dotnetmove_sln_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $root | Out-Null
        Push-Location $root
        try {
            & git init -q
            & dotnet new classlib -n Lib -o (Join-Path $root (Join-Path 'src' ('Lib'))) | Out-Null
            & dotnet new sln -n Demo --format $Format | Out-Null
            $sln = (Get-ChildItem -LiteralPath $root -File | Where-Object { $_.Extension -in '.sln', '.slnx' }).FullName
            & dotnet sln $sln add (Join-Path $root (Join-Path 'src' (Join-Path 'Lib' ('Lib.csproj')))) | Out-Null
            & git add -A; & git commit -qm fixture | Out-Null
        } finally { Pop-Location }
        return $root
    }
}

Describe 'Move-Solution' {
    It 'rebases project paths when a <Format> solution moves into a subfolder' -ForEach @(
        @{ Format = 'slnx' }, @{ Format = 'sln' }
    ) {
        $root = New-SlnFixture -Format $Format
        try {
            $sln = (Get-ChildItem -LiteralPath $root -File | Where-Object { $_.Extension -in '.sln', '.slnx' }).FullName
            $dest = Join-Path (Join-Path $root 'build') (Split-Path -Leaf $sln)

            $r = Move-Solution -Path $sln -Destination $dest -Confirm:$false -WarningAction SilentlyContinue
            $r.ProjectsRebased | Should -Be 1
            $dest | Should -Exist
            $sln | Should -Not -Exist

            # The moved solution still resolves its project and builds.
            $listed = & dotnet sln $dest list
            ($listed -join "`n") | Should -Match 'Lib\.csproj'
            & dotnet build $dest 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 0
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
