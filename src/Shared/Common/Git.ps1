function Get-RepoRoot {
    # Walk up from $StartPath looking for a .git dir/file; fall back to the start path.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StartPath)
    $dir = Get-Item -LiteralPath $StartPath
    if (-not $dir.PSIsContainer) { $dir = $dir.Directory }
    while ($null -ne $dir) {
        if (Test-Path (Join-Path $dir.FullName '.git')) { return $dir.FullName }
        $dir = $dir.Parent
    }
    return (Get-Item -LiteralPath $StartPath).FullName
}

function Move-PathTracked {
    # Move one path: git mv when tracked (preserves history), else Move-Item. Creates the
    # destination parent if needed. Shared by every move cmdlet's filesystem step.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][bool]$UseGit,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$RepoRoot
    )
    $parent = Split-Path -Parent $Destination
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    if ($UseGit -and (Test-GitTracked -Path $Source)) {
        Push-Location $RepoRoot
        try { & git mv -- $Source $Destination; if ($LASTEXITCODE -ne 0) { throw "git mv failed: $Source -> $Destination" } }
        finally { Pop-Location }
    } else {
        Move-Item -LiteralPath $Source -Destination $Destination
    }
}

function Test-GitTracked {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $dir = Split-Path -Parent $Path
    try {
        Push-Location $dir
        & git ls-files --error-unmatch -- $Path *> $null
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
    finally { Pop-Location }
}
