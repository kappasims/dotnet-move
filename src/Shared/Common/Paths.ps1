function Resolve-FullPath {
    # Absolute, normalized path. Does not require the path to exist and emits no errors.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Path))
}

function Test-PathEqual {
    # OS-aware path equality (see Platform.ps1 for $script:PathComparison).
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$A,
          [Parameter(Mandatory)][AllowEmptyString()][string]$B)
    return [string]::Equals($A.TrimEnd('\', '/'), $B.TrimEnd('\', '/'), $script:PathComparison)
}

function Test-PathInList {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,
          [string[]]$List)
    foreach ($item in $List) { if (Test-PathEqual $Path $item) { return $true } }
    return $false
}

function Get-RelativePathSafe {
    # Relative path from directory $From to file/dir $To, returned with the platform separator
    # (MSBuild accepts both). On PowerShell 7 we use [IO.Path]::GetRelativePath, which is correct
    # on Windows and Unix. Windows PowerShell 5.1 (.NET Framework 4.x) lacks GetRelativePath, so
    # there we fall back to Uri.MakeRelativeUri - which only works for Windows drive-letter paths,
    # but 5.1 is Windows-only so that is fine.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$From,
          [Parameter(Mandatory)][string]$To)
    $fromFull = (Resolve-FullPath $From).TrimEnd('\', '/')
    $toFull = Resolve-FullPath $To
    if ($PSVersionTable.PSEdition -eq 'Core') {
        return [System.IO.Path]::GetRelativePath($fromFull, $toFull)
    }
    $fromUri = [Uri]($fromFull + [System.IO.Path]::DirectorySeparatorChar)
    $toUri = [Uri]$toFull
    $rel = [Uri]::UnescapeDataString($fromUri.MakeRelativeUri($toUri).ToString())
    return ($rel -replace '/', '\')
}

function Test-PathUnder {
    # True if $Path is strictly inside directory $Dir (not equal to it). OS-aware compare.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,
          [Parameter(Mandatory)][string]$Dir)
    $p = (Resolve-FullPath $Path).TrimEnd('\', '/')
    $d = (Resolve-FullPath $Dir).TrimEnd('\', '/')
    if (Test-PathEqual $p $d) { return $false }
    # Normalize separators so the prefix test is separator-agnostic.
    $pn = ($p -replace '/', '\') + '\'
    $dn = ($d -replace '/', '\') + '\'
    return $pn.StartsWith($dn, $script:PathComparison)
}
