#requires -Modules Pester

BeforeAll {
    # [IO.Path]::Combine (not multi-arg Join-Path) so this loads on Windows PowerShell 5.1 too.
    Import-Module ([System.IO.Path]::Combine($PSScriptRoot, '..', 'src', 'DotnetMove.Core', 'DotnetMove.Core.psd1')) -Force
    # The Unity engine is cross-platform; import it so Move-UnityAsset is mockable for the
    # routing assertion. Removed again in AfterAll so it does not leak into other test files.
    Import-Module ([System.IO.Path]::Combine($PSScriptRoot, '..', 'src', 'DotnetMove.Unity', 'DotnetMove.Unity.psd1')) -Force

    function New-EngineFixture {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("dotnetmove_eng_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $root | Out-Null
        return $root
    }
}

Describe 'Move-Dotnet (top-level cross-namespace routing)' {
    It 'routes a .csproj to the .NET file engine' {
        $root = New-EngineFixture
        try {
            $proj = Join-Path $root 'Foo.csproj'
            Set-Content -LiteralPath $proj -Value '<Project/>'
            Mock -ModuleName DotnetMove.Core Move-DotnetFile { }
            Move-Dotnet -Path $proj -Destination (Join-Path $root 'dst')
            Should -Invoke -ModuleName DotnetMove.Core Move-DotnetFile -Times 1 -Exactly
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'routes a folder of projects to the .NET folder engine' {
        $root = New-EngineFixture
        try {
            $src = Join-Path $root 'src'
            New-Item -ItemType Directory -Path $src | Out-Null
            Set-Content -LiteralPath (Join-Path $src 'Foo.csproj') -Value '<Project/>'
            Mock -ModuleName DotnetMove.Core Move-DotnetFolder { }
            Move-Dotnet -Path $src -Destination (Join-Path $root 'source')
            Should -Invoke -ModuleName DotnetMove.Core Move-DotnetFolder -Times 1 -Exactly
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'routes a .ps1 to the PowerShell engine' {
        $root = New-EngineFixture
        try {
            $ps1 = Join-Path $root 'helper.ps1'
            Set-Content -LiteralPath $ps1 -Value '"hi"'
            Mock -ModuleName DotnetMove.Core Move-PowerShell { }
            Move-Dotnet -Path $ps1 -Destination (Join-Path $root 'moved.ps1')
            Should -Invoke -ModuleName DotnetMove.Core Move-PowerShell -Times 1 -Exactly
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'routes a .psd1 to the PowerShell engine' {
        $root = New-EngineFixture
        try {
            $psd1 = Join-Path $root 'MyMod.psd1'
            Set-Content -LiteralPath $psd1 -Value '@{ ModuleVersion = "1.0" }'
            Mock -ModuleName DotnetMove.Core Move-PowerShell { }
            Move-Dotnet -Path $psd1 -Destination (Join-Path $root 'modules')
            Should -Invoke -ModuleName DotnetMove.Core Move-PowerShell -Times 1 -Exactly
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'routes an asset under Assets/ to the Unity engine' {
        $root = New-EngineFixture
        try {
            $assets = Join-Path $root 'Assets'
            New-Item -ItemType Directory -Path $assets | Out-Null
            $asset = Join-Path $assets 'Foo.cs'
            Set-Content -LiteralPath $asset -Value '// c#'
            Set-Content -LiteralPath "$asset.meta" -Value 'guid: 0'
            Mock -ModuleName DotnetMove.Core Move-UnityAsset { }
            Move-Dotnet -Path $asset -Destination (Join-Path $assets 'Bar.cs')
            Should -Invoke -ModuleName DotnetMove.Core Move-UnityAsset -Times 1 -Exactly
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'routes a .vcxproj to the native engine on Windows' -Skip:(-not ($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop')) {
        $root = New-EngineFixture
        try {
            Import-Module ([System.IO.Path]::Combine($PSScriptRoot, '..', 'src', 'DotnetMove.Native', 'DotnetMove.Native.psd1')) -Force
            $vcx = Join-Path $root 'Foo.vcxproj'
            Set-Content -LiteralPath $vcx -Value '<Project/>'
            Mock -ModuleName DotnetMove.Core Move-NativeProject { }
            Move-Dotnet -Path $vcx -Destination (Join-Path $root 'moved')
            Should -Invoke -ModuleName DotnetMove.Core Move-NativeProject -Times 1 -Exactly
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'writes a non-terminating error for an unknown type' {
        $root = New-EngineFixture
        try {
            $txt = Join-Path $root 'notes.txt'
            Set-Content -LiteralPath $txt -Value 'x'
            Move-Dotnet -Path $txt -Destination (Join-Path $root 'x.txt') -ErrorVariable errs -ErrorAction SilentlyContinue
            $errs[0].FullyQualifiedErrorId | Should -Match 'UnknownEngine'
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

AfterAll {
    Remove-Module DotnetMove.Unity, DotnetMove.Native -Force -ErrorAction SilentlyContinue
}
