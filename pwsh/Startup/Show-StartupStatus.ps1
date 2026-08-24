# Defines commands that summarize missing tools and commonly used CustomShell
# helpers. Their startup output is emitted only for standalone terminals so
# embedded and nested PowerShell sessions remain quiet.

function global:Show-MissingShellCommand {
    <#
    .SYNOPSIS
    Displays configured command names that are not currently available.

    .DESCRIPTION
    Checks each supplied name with PowerShell command discovery and prints a
    single warning-style line when any are missing. By default it checks the
    required-command list loaded from CustomShell settings.

    .PARAMETER CommandName
    Command names to check; defaults to the list in CustomShell settings.
    #>
    [CmdletBinding()]
    param(
        [string[]] $CommandName = $global:CustomShellSettings.RequiredCommands
    )

    $missingCommands = @($CommandName | Where-Object {
        -not (Get-Command $_ -ErrorAction SilentlyContinue)
    })

    if ($missingCommands.Count -gt 0) {
        Write-Host -ForegroundColor Red "Missing commands: $($missingCommands -join ', ')"
    }
}

function global:Show-CustomShellHelp {
    <#
    .SYNOPSIS
    Displays a compact reminder of useful CustomShell commands.

    .DESCRIPTION
    Prints a short, colorized command reference for archive, SSH, navigation,
    search, and file-viewing helpers. It performs no command discovery or
    configuration changes.
    #>
    Write-Host -ForegroundColor Blue 'CustomShell commands'
    Write-Host -ForegroundColor Green @'
• Protect-Tar / Unprotect-Tar
• Get-SSHConfig
• z / zi / batx / vim
• rg <pattern> [path] / fd <pattern> [path]
• ssh [-p <port>] [-J <jump-host>] <host>
'@
}

if ($customShellState.IsStandaloneTerminal) {
    Show-MissingShellCommand
    Show-CustomShellHelp
}
