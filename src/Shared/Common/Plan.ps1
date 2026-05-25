# Shared move-plan engine used by the move cmdlets so the transaction is uniform.
#
# A move is a transaction: detach references (while old paths resolve) -> move -> reattach.
# Each reconciliation item bundles its Detach + Reattach. Confirmation/preview is the caller's
# job via $PSCmdlet.ShouldProcess (canonical -WhatIf/-Confirm); this engine just runs the
# transaction once the operation is approved.

function New-MoveResult {
    # Build a move cmdlet's result object with a uniform base shape (Engine, Source,
    # Destination, Performed, SkippedCount) plus engine-specific extras, and stamp the
    # given PSTypeName for formatting/filtering. Every move cmdlet emits one of these.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TypeName,
        [Parameter(Mandatory)][ValidateSet('dotnet', 'native', 'unity', 'powershell')][string]$Engine,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [bool]$Performed,
        [int]$SkippedCount = 0,
        [hashtable]$Extra = @{}
    )
    $ordered = [ordered]@{
        Engine       = $Engine
        Source       = $Source
        Destination  = $Destination
        Performed    = $Performed
        SkippedCount = $SkippedCount
    }
    foreach ($k in $Extra.Keys) { $ordered[$k] = $Extra[$k] }
    $obj = [pscustomobject]$ordered
    $obj.PSObject.TypeNames.Insert(0, $TypeName)
    return $obj
}

function Resolve-MoveContext {
    # Shared front-half of every move: resolve git usage (red guidance + ShouldContinue/abort
    # when missing) and whether to confirm per-line. Returns { UseGit; PerLine } or $null on
    # abort (after writing the GitMissingAborted error via the calling cmdlet).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Management.Automation.PSCmdlet]$Cmdlet,
        [switch]$Force,
        [Parameter(Mandatory)]$TargetForError
    )
    $gitMode = Resolve-GitUsage -Cmdlet $Cmdlet -Force:$Force
    if ($gitMode -eq 'Abort') {
        $Cmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                [System.OperationCanceledException]::new('Aborted: git not found and the plain-move fallback was declined.'),
                'GitMissingAborted', [System.Management.Automation.ErrorCategory]::OperationStopped, $TargetForError))
        return $null
    }
    [pscustomobject]@{ UseGit = ($gitMode -eq 'Git') }
}

function New-MoveItem {
    # Build one reconciliation item. Pass module-bound scriptblocks (not .GetNewClosure() -
    # closures rebind to the caller's scope and lose module-private functions like Invoke-Dotnet)
    # and hand loop values in via *Args. Mark Optional for heuristic/non-load-bearing items.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Description,
        [scriptblock]$Detach,
        [object[]]$DetachArgs = @(),
        [scriptblock]$Reattach,
        [object[]]$ReattachArgs = @(),
        [switch]$Optional
    )
    [pscustomobject]@{
        Description  = $Description
        Detach       = $Detach;   DetachArgs   = $DetachArgs
        Reattach     = $Reattach; ReattachArgs = $ReattachArgs
        Optional     = [bool]$Optional
    }
}

function Invoke-MovePlan {
    # Run the move transaction: detach all reconciliation items (old paths still resolve),
    # perform the move, reattach all items. Confirmation/-WhatIf is the caller's ShouldProcess
    # gate - this only runs once approved.
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Caption,
        [AllowEmptyCollection()][object[]]$Items = @(),
        [Parameter(Mandatory)][scriptblock]$Move,
        [object[]]$MoveArgs = @()
    )
    Write-Verbose "Reconciling $($Items.Count) reference(s) around: $Caption"

    # NOTE: @var is the splat operator (needs a bare variable); @(expr) is array-subexpression
    # and would pass the whole array as one argument. So copy to a local, then splat.
    foreach ($it in $Items) {
        if ($it.Detach) { $da = @($it.DetachArgs); & $it.Detach @da }
    }
    $ma = @($MoveArgs); & $Move @ma
    foreach ($it in $Items) {
        if ($it.Reattach) { $ra = @($it.ReattachArgs); & $it.Reattach @ra }
    }

    [pscustomobject]@{ Applied = $Items.Count; Skipped = 0 }
}
