#requires -Version 5.1
<#
.SYNOPSIS
    Install or update DotnetMove from GitHub, no clone or git required. Re-run to update.

.DESCRIPTION
    Downloads a release's source zip, extracts it, and copies the modules onto your PowerShell
    module path (edition-aware), so `Import-Module DotnetMove` works by name. Running it again
    overwrites the installed copy with the chosen version - install and update are the same gesture.

    Designed to run straight from the web:
        irm https://raw.githubusercontent.com/kappasims/dotnet-move/master/install.ps1 | iex

    Not on the PowerShell Gallery yet; when it is, `Install-Module`/`Update-Module` replaces this.

.PARAMETER Version
    Semver to install (e.g. 1.1.0). Defaults to the latest GitHub release.

.PARAMETER InstallPath
    Target modules directory. Defaults to the CurrentUser module path for the running edition.

.PARAMETER Repository
    owner/name of the GitHub repository. Defaults to the project repository.

.EXAMPLE
    ./install.ps1
    Installs (or updates to) the latest release.

.EXAMPLE
    ./install.ps1 -Version 1.1.0
    Installs a specific version.
#>
[CmdletBinding()]
param(
    [string]$Version,
    [string]$InstallPath,
    [string]$Repository = 'kappasims/dotnet-move',
    # Opt out of the retroactive-undo journal. Prefers git config (git config --global
    # dotnetmove.journal false) when git is present - the durable, config-first switch; falls back to
    # the DOTNETMOVE_JOURNAL env var with no git. Either way the choice survives future
    # installs/updates - they never switch journaling back on.
    [switch]$NoJournal
)

$ErrorActionPreference = 'Stop'
$headers = @{ 'User-Agent' = 'DotnetMove-Installer' }

function Test-IsWindowsHost {
    if ($PSVersionTable.PSEdition -eq 'Desktop') { return $true }
    if (Test-Path Variable:\IsWindows) { return [bool](Get-Variable -Name IsWindows -ValueOnly) }
    return $false
}

# Resolve the tag: explicit -Version, else the latest release.
if ($Version) {
    $tag = 'v' + ($Version -replace '^v', '')
} else {
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repositories/$Repository/releases/latest" -Headers $headers
    $tag = "$($rel.tag_name)"
    if (-not $tag) { throw "No releases found for $Repository." }
}
Write-Host "Installing DotnetMove $tag..." -ForegroundColor Cyan

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("dotnetmove_install_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $zip = Join-Path $tmp 'src.zip'
    Invoke-WebRequest -Uri "https://github.com/$Repository/archive/refs/tags/$tag.zip" -OutFile $zip -Headers $headers
    Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
    $extracted = Get-ChildItem -LiteralPath $tmp -Directory | Select-Object -First 1   # <repository>-<version>/
    $srcRoot = Join-Path $extracted.FullName 'src'
    if (-not (Test-Path -LiteralPath $srcRoot)) { throw "Downloaded archive has no src/ folder: $srcRoot" }

    if (-not $InstallPath) {
        $InstallPath = if (Test-IsWindowsHost) {
            $editionDir = if ($PSVersionTable.PSEdition -eq 'Core') { 'PowerShell' } else { 'WindowsPowerShell' }
            Join-Path ([Environment]::GetFolderPath('MyDocuments')) (Join-Path $editionDir 'Modules')
        } else {
            Join-Path $HOME '.local/share/powershell/Modules'
        }
    }
    New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null

    # DotnetMove.Shared holds the helpers the engines call; install it alongside them.
    foreach ($name in 'DotnetMove.Shared', 'DotnetMove.Core', 'DotnetMove.Unity', 'DotnetMove.Native', 'DotnetMove') {
        $dest = Join-Path $InstallPath $name
        if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
        Copy-Item -LiteralPath (Join-Path $srcRoot $name) -Destination $dest -Recurse -Force
    }
    Write-Host "Installed DotnetMove $tag to $InstallPath" -ForegroundColor Green
    Write-Host "    Import-Module DotnetMove" -ForegroundColor Green

    if ($NoJournal) {
        # Persist the opt-out where the module reads it. Prefer the durable, config-first switch
        # (global git config), so it holds for every repository; fall back to the env var with no git.
        $gitAvailable = [bool](Get-Command git -ErrorAction SilentlyContinue)
        if ($gitAvailable) {
            & git config --global dotnetmove.journal false 2>$null
        }
        if ($gitAvailable -and $LASTEXITCODE -eq 0) {
            Write-Host "Undo journaling disabled for every repository (git config --global dotnetmove.journal false)." -ForegroundColor Yellow
        } elseif (Test-IsWindowsHost) {
            [Environment]::SetEnvironmentVariable('DOTNETMOVE_JOURNAL', 'off', 'User')
            $env:DOTNETMOVE_JOURNAL = 'off'
            Write-Host "Undo journaling disabled (set DOTNETMOVE_JOURNAL=off for your user)." -ForegroundColor Yellow
        } else {
            $env:DOTNETMOVE_JOURNAL = 'off'
            Write-Host "Undo journaling disabled for this session. To persist, add to your profile:" -ForegroundColor Yellow
            Write-Host "    `$env:DOTNETMOVE_JOURNAL = 'off'" -ForegroundColor Yellow
        }
    }
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
