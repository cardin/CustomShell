# Implements a small, read-only parser for concrete OpenSSH client host
# declarations. It exposes useful connection fields as objects without invoking
# SSH or modifying the user's configuration file.

function Get-SSHConfig {
    <#
    .SYNOPSIS
    Reads concrete host aliases from an OpenSSH client configuration file.

    .DESCRIPTION
    Returns an object for each non-wildcard alias and applies HostName, User,
    and Port values declared in the same Host block. This is a deliberately
    small parser, not a complete implementation of OpenSSH configuration
    precedence or Include processing.

    .PARAMETER ConfigPath
    Path to the OpenSSH client configuration file.
    #>
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string] $ConfigPath = (Join-Path $HOME '.ssh\config')
    )

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        Write-Warning "No SSH config file found at $ConfigPath"
        return
    }

    $results = [Collections.Generic.List[object]]::new()
    $currentAliases = @()

    foreach ($rawLine in Get-Content -LiteralPath $ConfigPath) {
        $line = $rawLine.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) {
            continue
        }

        if ($line -match '^(?i)Host\s+(.+)$') {
            $currentAliases = foreach ($aliasName in ($Matches[1] -split '\s+')) {
                $entry = [pscustomobject]@{
                    Alias    = $aliasName
                    HostName = $null
                    User     = $null
                    Port     = $null
                }
                $results.Add($entry)
                $entry
            }
            continue
        }

        if ($currentAliases.Count -eq 0) {
            continue
        }

        if ($line -match '^(?i)HostName\s+(.+)$') {
            foreach ($entry in $currentAliases) {
                $entry.HostName = $Matches[1].Trim()
            }
        }
        elseif ($line -match '^(?i)User\s+(.+)$') {
            foreach ($entry in $currentAliases) {
                $entry.User = $Matches[1].Trim()
            }
        }
        elseif ($line -match '^(?i)Port\s+(\d+)$') {
            foreach ($entry in $currentAliases) {
                $entry.Port = [int] $Matches[1]
            }
        }
    }

    $results |
        Where-Object { $_.Alias -notmatch '[\*\?]' } |
        Sort-Object Alias
}
