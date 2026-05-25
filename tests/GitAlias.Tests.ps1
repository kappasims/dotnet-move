#requires -Modules Pester

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot (Join-Path '..' (Join-Path 'src' (Join-Path 'DotnetMove.Core' ('DotnetMove.Core.psd1'))))) -Force

    function New-RepoFixture {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("dotnetmove_git_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $root | Out-Null
        Push-Location $root
        try {
            & git init -q
            & dotnet new classlib -n Lib -o (Join-Path $root (Join-Path 'src' ('Lib'))) | Out-Null
            & dotnet new sln -n Demo --format slnx | Out-Null
            & dotnet sln Demo.slnx add (Join-Path $root (Join-Path 'src' (Join-Path 'Lib' ('Lib.csproj')))) | Out-Null
            & git add -A; & git commit -qm fixture | Out-Null
        } finally { Pop-Location }
        return $root
    }
}

Describe 'Register/Unregister-DotnetMvGitAlias' {
    It 'sets and unsets a repo-local alias' {
        $root = New-RepoFixture
        Push-Location $root
        try {
            Register-DotnetMvGitAlias -Scope Local -Confirm:$false | Out-Null
            (& git config --local --get alias.dotnetmv) | Should -Match 'git-dotnetmv\.ps1'
            Unregister-DotnetMvGitAlias -Scope Local -Confirm:$false | Out-Null
            (& git config --local --get alias.dotnetmv) | Should -BeNullOrEmpty
        } finally { Pop-Location; Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does not set the alias under -WhatIf' {
        $root = New-RepoFixture
        Push-Location $root
        try {
            Register-DotnetMvGitAlias -Scope Local -WhatIf | Out-Null
            (& git config --local --get alias.dotnetmv) | Should -BeNullOrEmpty
        } finally { Pop-Location; Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'git dotnetmv (end-to-end, universal cross-engine routing)' {
    It 'routes a .csproj to the .NET engine' {
        $root = New-RepoFixture
        Push-Location $root
        try {
            Register-DotnetMvGitAlias -Scope Local -Confirm:$false | Out-Null
            & git -C $root dotnetmv src/Lib/Lib.csproj libs/Lib --nobuild 2>&1 | Out-Null
            (Join-Path $root (Join-Path 'libs' (Join-Path 'Lib' ('Lib.csproj')))) | Should -Exist
            (Join-Path $root (Join-Path 'src' (Join-Path 'Lib' ('Lib.csproj')))) | Should -Not -Exist
        } finally { Pop-Location; Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'routes a Unity asset (under Assets, has .meta) to the Unity engine' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("dotnetmove_gitu_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path (Join-Path $root (Join-Path 'Assets' ('Foo'))) -Force | Out-Null
        Set-Content (Join-Path $root (Join-Path 'Assets' (Join-Path 'Foo' ('Bar.cs')))) 'public class Bar {}'
        Set-Content (Join-Path $root (Join-Path 'Assets' (Join-Path 'Foo' ('Bar.cs.meta')))) "guid: 11112222333344445555666677778888"
        Push-Location $root
        try {
            & git init -q; & git add -A; & git commit -qm fixture | Out-Null
            Register-DotnetMvGitAlias -Scope Local -Confirm:$false | Out-Null
            & git -C $root dotnetmv Assets/Foo/Bar.cs Assets/Moved/Bar.cs 2>&1 | Out-Null
            (Join-Path $root (Join-Path 'Assets' (Join-Path 'Moved' ('Bar.cs')))) | Should -Exist
            (Join-Path $root (Join-Path 'Assets' (Join-Path 'Moved' ('Bar.cs.meta')))) | Should -Exist     # .meta rode along
        } finally { Pop-Location; Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'routes a .ps1 to the PowerShell engine' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("dotnetmove_gitp_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path (Join-Path $root 'lib') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root 'app') -Force | Out-Null
        Set-Content (Join-Path $root (Join-Path 'lib' ('helpers.ps1'))) 'function Get-Greeting { "hi" }'
        Set-Content (Join-Path $root (Join-Path 'app' ('main.ps1'))) '. "$PSScriptRoot\..\lib\helpers.ps1"'
        Push-Location $root
        try {
            & git init -q; & git add -A; & git commit -qm fixture | Out-Null
            Register-DotnetMvGitAlias -Scope Local -Confirm:$false | Out-Null
            & git -C $root dotnetmv lib/helpers.ps1 shared/helpers.ps1 2>&1 | Out-Null
            (Join-Path $root (Join-Path 'shared' ('helpers.ps1'))) | Should -Exist
            (Get-Content (Join-Path $root (Join-Path 'app' ('main.ps1'))) -Raw) | Should -Match 'shared[\\/]helpers\.ps1'
        } finally { Pop-Location; Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
