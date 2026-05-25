$script:ManagedProjectExtensions = @('.csproj', '.fsproj', '.vbproj')
$script:NativeProjectExtensions = @('.vcxproj')

function Test-IsNativeProject {
    # C++/native (.vcxproj). dotnet CLI lists these in solutions but can't reconcile
    # their link model (AdditionalLibraryDirectories/Dependencies, .props imports).
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    return ([System.IO.Path]::GetExtension($Path) -in $script:NativeProjectExtensions)
}

function Find-ProjectFiles {
    # MSBuild project files beneath a root. Managed by default; -IncludeNative also returns .vcxproj.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [switch]$IncludeNative
    )
    $exts = $script:ManagedProjectExtensions
    if ($IncludeNative) { $exts = $exts + $script:NativeProjectExtensions }
    Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in $exts -and $_.FullName -notmatch '[\\/](bin|obj|\.vs|\.git)[\\/]' }
}

function Read-ProjectXml {
    # Read text (File.ReadAllText auto-detects BOM/encoding on both editions), strip any
    # residual BOM, then LoadXml from the string. Avoids both the 5.1 [xml]-cast BOM failure
    # and Load(path) URI quirks.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $full = Resolve-FullPath $Path
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        throw "Project file not found for XML read: $full"
    }
    $text = [System.IO.File]::ReadAllText($full).TrimStart([char]0xFEFF)
    $xml = New-Object System.Xml.XmlDocument
    $xml.LoadXml($text)
    return $xml
}

function Get-ProjectReferencePaths {
    # Absolute paths of every <ProjectReference Include=...> in a project file.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectFile)
    $projDir = Split-Path -Parent (Resolve-FullPath $ProjectFile)
    $xml = Read-ProjectXml -Path $ProjectFile
    $refs = @()
    foreach ($node in $xml.SelectNodes('//*[local-name()="ProjectReference"]')) {
        $include = $node.GetAttribute('Include')
        if ([string]::IsNullOrWhiteSpace($include)) { continue }
        $abs = [System.IO.Path]::GetFullPath((Join-Path $projDir $include))
        $refs += [pscustomobject]@{ Raw = $include; FullPath = $abs }
    }
    return $refs
}

function Get-ConsumingProjects {
    # Project files (from $Candidates) that have a ProjectReference to $ProjectFile.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectFile,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Candidates
    )
    $target = Resolve-FullPath $ProjectFile
    $hits = @()
    foreach ($proj in $Candidates) {
        if (Test-PathEqual (Resolve-FullPath $proj.FullName) $target) { continue }
        foreach ($ref in (Get-ProjectReferencePaths -ProjectFile $proj.FullName)) {
            if (Test-PathEqual $ref.FullPath $target) { $hits += $proj.FullName; break }
        }
    }
    return $hits
}

function Test-DirectoryBuildInheritance {
    # Warn if moving from $OldDir to $NewDir changes which Directory.Build.* files apply.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OldDir,
        [Parameter(Mandatory)][string]$NewDir,
        [Parameter(Mandatory)][string]$RepoRoot
    )
    function _chain([string]$start) {
        $found = @()
        $d = [System.IO.DirectoryInfo]::new($start)
        $rootFull = (Resolve-FullPath $RepoRoot)
        while ($null -ne $d) {
            foreach ($name in 'Directory.Build.props', 'Directory.Build.targets') {
                $p = Join-Path $d.FullName $name
                if (Test-Path $p) { $found += $p }
            }
            if (Test-PathEqual (Resolve-FullPath $d.FullName) $rootFull) { break }
            $d = $d.Parent
        }
        return $found
    }
    $before = _chain $OldDir
    $after  = _chain $NewDir
    $lost   = $before | Where-Object { ($after | ForEach-Object { Split-Path -Leaf $_ }) -notcontains (Split-Path -Leaf $_) }
    $gained = $after  | Where-Object { ($before | ForEach-Object { Split-Path -Leaf $_ }) -notcontains (Split-Path -Leaf $_) }
    if ($lost -or $gained) {
        Write-Warning "Directory.Build.* inheritance changes with this move:"
        $lost   | ForEach-Object { Write-Warning "  no longer applies: $_" }
        $gained | ForEach-Object { Write-Warning "  now applies:       $_" }
    }
}
