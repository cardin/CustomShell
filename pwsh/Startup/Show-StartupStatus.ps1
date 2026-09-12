# Defines commands that summarize commonly used CustomShell helpers. Their
# startup output is emitted only for standalone terminals so embedded and
# nested PowerShell sessions remain quiet.

function global:Show-Help {
    <#
    .SYNOPSIS
    Displays a compact reminder of useful CustomShell commands.

    .DESCRIPTION
    Prints a short, colorized command reference for archive, SSH, navigation,
    search, and file-viewing helpers. It performs no command discovery or
    configuration changes.
    #>
    Write-Host -ForegroundColor Blue '=== Show-Help ==='
    Write-Host -ForegroundColor Green @'
• conda / pipx / node
• z / zi / bat / nvitop / Get-SSHConfig / [Un]protect-Tar
• rg <regex> [--glob ..] [-t <py>] [--no-ignore] [--hidden] [--max-depth ..] 
    [-l] [-B|A|C <int>] [<path> ...]
• fd <regex> [--glob ..] [-t d|f] [--no-ignore] [--hidden] [--max|min-depth ..] 
    [--full-path] [-e <py>] [<targetDir>] [--exec <cmd> {} /;]
• ssh [-p <port>] [-NT] [-L [<local>:]<port>:<remote>:<port>] [-J <user>@<hop1>] <user>@<hop2>
• $env:USERPROFILE
'@
}

if ($customShellState.IsStandaloneTerminal) {
    Show-Help
}
