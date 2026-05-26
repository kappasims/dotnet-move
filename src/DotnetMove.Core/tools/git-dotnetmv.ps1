#!/usr/bin/env pwsh
# Forwarder for the opt-in `git dotnetmv` alias. Git appends the user's args, so this is
# invoked as: pwsh -NoProfile -File git-dotnetmv.ps1 <src> <dst> [--whatif] [--force] [--nobuild]
#
# This only adapts git-style args to PowerShell and hands off to Move-Dotnet, the top-level
# cmdlet that branches by detected type to each engine (the .NET project model, PowerShell,
# Unity, or native C++). All routing lives in that tested cmdlet; this never edits PATH or git
# config itself.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DotnetMove.Core (which exports Move-Dotnet) is always required.
if (-not (Get-Command Move-Dotnet -ErrorAction SilentlyContinue)) {
    $coreManifest = [System.IO.Path]::Combine($PSScriptRoot, '..', 'DotnetMove.Core.psd1')
    if (Test-Path -LiteralPath $coreManifest) {
        # Running from a clone: the sibling Shared module is not on the module path, so load it by
        # path first (Core calls its helpers but declares no RequiredModules), then Core. When
        # installed, the else branch imports by name and PowerShell auto-loads Shared on first use.
        $sharedManifest = [System.IO.Path]::Combine($PSScriptRoot, '..', '..', 'DotnetMove.Shared', 'DotnetMove.Shared.psd1')
        if (Test-Path -LiteralPath $sharedManifest) { Import-Module $sharedManifest -Force }
        Import-Module $coreManifest -Force
    } else {
        Import-Module DotnetMove.Core -ErrorAction Stop
    }
}

# Parse git-style args: first two non-flag tokens are source/destination.
$rest = @(); $whatIf = $false; $force = $false; $noBuild = $false
foreach ($a in $args) {
    switch -regex ($a) {
        '^--whatif$'  { $whatIf = $true; continue }
        '^--force$'   { $force = $true; continue }
        '^--nobuild$' { $noBuild = $true; continue }
        default       { $rest += $a }
    }
}
if ($rest.Count -lt 2) {
    Write-Host 'usage: git dotnetmv <source> <destination> [--whatif] [--force] [--nobuild]' -ForegroundColor Red
    exit 2
}
$src = $rest[0]; $dst = $rest[1]

# `!`-aliases run at the repo top-level with GIT_PREFIX = the subdir the user invoked from;
# resolve relative args against it so paths mean what the user typed.
if ($env:GIT_PREFIX) {
    if (-not [System.IO.Path]::IsPathRooted($src)) { $src = Join-Path $env:GIT_PREFIX $src }
    if (-not [System.IO.Path]::IsPathRooted($dst)) { $dst = Join-Path $env:GIT_PREFIX $dst }
}

$params = @{ Path = $src; Destination = $dst; WhatIf = $whatIf; Confirm = $false }
if ($force) { $params.Force = $true }
if ($noBuild) { $params.NoBuild = $true }
# Let Move-Dotnet derive the repo root from the target path. Do NOT use
# `git rev-parse --show-toplevel`: git canonicalizes symlinks (on macOS the temp/repo path
# /var/folders/... becomes /private/var/folders/...), which would not match the OS-form paths the
# rest of the toolkit uses (Get-ChildItem, Get-RepoRoot), breaking path comparisons on a repo that
# sits under a symlinked directory.

Move-Dotnet @params
