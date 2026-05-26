function Unregister-DotnetMvGitAlias {
    <#
    .SYNOPSIS
        Remove the `git dotnetmv` alias registered by Register-DotnetMvGitAlias.

    .PARAMETER Scope
        'Local' (this repo, default) or 'Global'.

    .OUTPUTS
        None.

    .EXAMPLE
        # Remove the alias for this repo (default scope is Local)
        Unregister-DotnetMvGitAlias
        # Remove the global alias from ~/.gitconfig
        Unregister-DotnetMvGitAlias -Scope Global
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [ValidateSet('Local', 'Global')]
        [string]$Scope = 'Local'
    )

    if (-not (Test-GitAvailable)) {
        Write-CapabilityGuidance -Tool git
        $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                [System.InvalidOperationException]::new('git is required but was not found.'),
                'GitMissing', [System.Management.Automation.ErrorCategory]::NotInstalled, $null))
        return
    }

    $scopeFlag = if ($Scope -eq 'Global') { '--global' } else { '--local' }
    if ($PSCmdlet.ShouldProcess("git config ($Scope)", 'unset alias.dotnetmv')) {
        & git config $scopeFlag --unset alias.dotnetmv 2>$null
        # exit 5 = key not present; treat as already-removed (idempotent).
        if ($LASTEXITCODE -in 0, 5) {
            Write-Host "Unregistered 'git dotnetmv' ($Scope)." -ForegroundColor Green
        } else {
            $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new("git config --unset failed (exit $LASTEXITCODE)."),
                    'GitConfigFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null))
        }
    }
}
