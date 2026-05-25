Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Native needs Common + the Dotnet tier (it updates solution membership and reads project XML).
# [IO.Path]::Combine (not multi-arg Join-Path) so this loads on Windows PowerShell 5.1 too.
$shared = [System.IO.Path]::Combine($PSScriptRoot, '..', 'Shared')
foreach ($tier in 'Common', 'Dotnet') {
    foreach ($f in (Get-ChildItem -Path (Join-Path $shared $tier) -Filter '*.ps1' -ErrorAction SilentlyContinue)) { . $f.FullName }
}
foreach ($f in (Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue)) { . $f.FullName }

$public = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -ErrorAction SilentlyContinue)
foreach ($f in $public) { . $f.FullName }

Export-ModuleMember -Function $public.BaseName
