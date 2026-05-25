function Find-Solutions {
    # All .sln and .slnx files beneath a root.
    # Filter by extension via Where-Object, not Get-ChildItem -Include: on Windows
    # PowerShell 5.1, -Include is ignored when combined with -LiteralPath (returns
    # every file). Where-Object behaves identically on both editions.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)
    Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in '.sln', '.slnx' -and $_.FullName -notmatch '[\\/](bin|obj|\.vs|\.git)[\\/]' }
}

function Get-SolutionsReferencing {
    # Solutions (from $Candidates) whose project list includes $ProjectFile.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectFile,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Candidates
    )
    $target = Resolve-FullPath $ProjectFile
    $hits = @()
    foreach ($sln in $Candidates) {
        $slnDir = Split-Path -Parent $sln.FullName
        $listed = Invoke-DotnetRead sln $sln.FullName list
        if ($LASTEXITCODE -ne 0) { continue }
        foreach ($line in $listed) {
            $line = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($line) -or $line -notmatch '\.(cs|fs|vb|vcx)proj$') { continue }
            $abs = [System.IO.Path]::GetFullPath((Join-Path $slnDir $line))
            if (Test-PathEqual $abs $target) { $hits += $sln; break }
        }
    }
    return $hits
}

function Get-SolutionProjectEntries {
    # The project entries stored in a solution, as the exact string written in the file plus
    # its resolved absolute path. Used to rebase a solution's relative paths when it moves.
    # Skips solution folders (their second field is a name, not a project path).
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SolutionFile)
    $full = Resolve-FullPath $SolutionFile
    $dir = Split-Path -Parent $full
    $entries = @()
    if ([System.IO.Path]::GetExtension($full) -ieq '.slnx') {
        $xml = Read-ProjectXml -Path $full
        foreach ($n in $xml.SelectNodes('//*[local-name()="Project"]')) {
            $p = $n.GetAttribute('Path')
            if ([string]::IsNullOrWhiteSpace($p) -or $p -notmatch '\.(cs|fs|vb|vcx)proj$') { continue }
            $abs = [System.IO.Path]::GetFullPath((Join-Path $dir ($p -replace '/', '\')))
            $entries += [pscustomobject]@{ Stored = $p; Abs = $abs }
        }
    } else {
        foreach ($line in (Get-Content -LiteralPath $full)) {
            if ($line -match '^\s*Project\("\{[^}]+\}"\)\s*=\s*"[^"]*",\s*"([^"]+)",\s*"\{[^}]+\}"') {
                $p = $Matches[1]
                if ($p -notmatch '\.(cs|fs|vb|vcx)proj$') { continue }
                $abs = [System.IO.Path]::GetFullPath((Join-Path $dir $p))
                $entries += [pscustomobject]@{ Stored = $p; Abs = $abs }
            }
        }
    }
    return $entries
}

function Get-SolutionMembership {
    # For each solution, the absolute paths of every project it lists.
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Solutions)
    $result = @()
    foreach ($sln in $Solutions) {
        $slnDir = Split-Path -Parent $sln.FullName
        $projects = @()
        $listed = Invoke-DotnetRead sln $sln.FullName list
        if ($LASTEXITCODE -eq 0) {
            foreach ($line in $listed) {
                $line = $line.Trim()
                if ([string]::IsNullOrWhiteSpace($line) -or $line -notmatch '\.(cs|fs|vb|vcx)proj$') { continue }
                $projects += [System.IO.Path]::GetFullPath((Join-Path $slnDir $line))
            }
        }
        $result += [pscustomobject]@{ Solution = $sln.FullName; Projects = $projects }
    }
    return $result
}
