function Update-Netscoot {
    <#
    .SYNOPSIS
        Update an installed netscoot to the latest GitHub release, in place. The one-command
        update for non-clone installs.

    .DESCRIPTION
        Checks GitHub for a newer release (via Test-NetscootUpdate) and, if the installed version
        is behind, runs the release's install.ps1 to overwrite the modules on your module path. No
        git, no clone. Does nothing when already current unless -Force. Honors -WhatIf/-Confirm.

        After it runs, reload the module in the current session with `Import-Module Netscoot -Force`.
        Needs network access to GitHub. For Gallery installs, `Update-Module Netscoot` is the
        simpler path; this command updates installer/clone installs in place from the GitHub release.

        Policy kill-switch: when the update policy is Disabled (see Set-NetscootUpdatePolicy, or an
        administrator's Group Policy / Intune push), this refuses to update so machine state stays
        managed. -Force overrides the policy (and also reinstalls when current).

    .PARAMETER Force
        Reinstall the latest release even if already current, and override a Disabled update policy.

    .PARAMETER Repository
        owner/name of the GitHub repository. Defaults to the project repository.

    .OUTPUTS
        Netscoot.Update - the record from Test-NetscootUpdate, so the decision is inspectable. Nothing on a failed check.

    .EXAMPLE
        # Update to the latest release if the installed copy is behind
        Update-Netscoot
        # Report what it would do without downloading or installing
        Update-Netscoot -WhatIf
        # Reinstall the latest even if already up to date
        Update-Netscoot -Force
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('Netscoot.Update')]
    param(
        [switch]$Force,
        [ValidatePattern('^[^/]+/[^/]+$')]
        [string]$Repository = 'kappasims/netscoot'
    )

    # Policy kill-switch (GPO/Intune-friendly): refuse when the update policy is Disabled, so a
    # managed fleet does not self-update outside its own pipeline. -Force overrides. Checked before
    # the network call so a disabled fleet makes no request.
    if ((-not $Force) -and ((Get-NetscootUpdatePolicy).State -eq 'Disabled')) {
        Write-Warning 'Updates are disabled by the update policy. Use -Force to override, or run Set-NetscootUpdatePolicy -State Manual.'
        return
    }

    $check = Test-NetscootUpdate -Repository $Repository
    if (-not $check) { return }   # connection error already surfaced by Test-NetscootUpdate

    if (-not $check.UpdateAvailable -and -not $Force) {
        Write-Host "netscoot is already up to date (installed $($check.Installed))." -ForegroundColor Green
        return $check
    }

    if ($PSCmdlet.ShouldProcess('Netscoot', "update to $($check.Tag) from GitHub")) {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("netscoot_update_" + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.ps1')
        try {
            # -OutFile writes the installer without a content-write cmdlet (keeps the first-party
            # drift monitor happy); Unblock-File clears the mark-of-the-web so it can run.
            Invoke-WebRequest -Uri "https://raw.githubusercontent.com/$Repository/$($check.Tag)/install.ps1" `
                -OutFile $tmp -Headers @{ 'User-Agent' = 'Netscoot' } -ErrorAction Stop
            if (Get-Command Unblock-File -ErrorAction SilentlyContinue) { Unblock-File -LiteralPath $tmp }
            & $tmp
            Write-Host 'Reload it in this session: Import-Module Netscoot -Force' -ForegroundColor Cyan
        } finally {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
    return $check
}
