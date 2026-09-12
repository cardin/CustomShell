# Defines reload-safe aliases and lightweight wrappers for interactive shell
# use. Optional command aliases are installed only when their backing tools are
# available, while native fallbacks preserve useful behavior on minimal systems.

if (Get-Command pwsh_x -ErrorAction SilentlyContinue) {
    Set-Alias -Name pwsh -Value pwsh_x -Scope Global -Force
    Set-Alias -Name powershell -Value pwsh_x -Scope Global -Force
}

function global:Remove-ItemTree {
    <#
    .SYNOPSIS
    Recursively removes one or more explicitly supplied paths.

    .DESCRIPTION
    Provides an interactive recursive-removal helper while refusing the
    filesystem root, home directory, and CustomShell repository root. Paths are
    resolved before validation, and deletion honors PowerShell confirmation and
    WhatIf semantics.

    .PARAMETER Path
    One or more literal paths to remove recursively.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string[]] $Path
    )

    process {
        $repositoryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $protectedPaths = @(
            [IO.Path]::GetFullPath($HOME).TrimEnd('\', '/')
            [IO.Path]::GetFullPath($repositoryRoot).TrimEnd('\', '/')
        )

        foreach ($inputPath in $Path) {
            $resolvedPath = $ExecutionContext.SessionState.Path.
                GetUnresolvedProviderPathFromPSPath($inputPath)
            $normalizedPath = [IO.Path]::GetFullPath($resolvedPath).TrimEnd('\', '/')
            $pathRoot = [IO.Path]::GetPathRoot($normalizedPath).TrimEnd('\', '/')

            if (
                [string]::IsNullOrWhiteSpace($normalizedPath) -or
                $normalizedPath -eq $pathRoot -or
                $normalizedPath -in $protectedPaths
            ) {
                throw "Refusing to recursively remove protected path: $normalizedPath"
            }

            if ($PSCmdlet.ShouldProcess($normalizedPath, 'Remove recursively')) {
                Remove-Item -LiteralPath $normalizedPath -Recurse -Force
            }
        }
    }
}

# Prefer GNU Coreutils when it is installed. Its dispatcher is used only as a
# feature check: the aliases below target the companion rm.exe and ls.exe
# commands directly, preserving familiar Unix behavior in PowerShell.
if (Get-Command coreutils -ErrorAction SilentlyContinue) {
    # Replace PowerShell's built-in rm alias and wrappers with GNU commands.
    Set-Alias -Name rm -Value rm.exe -Scope Global -Force
    Remove-Alias -Name ls, ll -Scope Global -Force -ErrorAction SilentlyContinue

    function global:ls {
        <#
        .SYNOPSIS
        Lists directory entries through GNU ls with color enabled.

        .DESCRIPTION
        Forwards all supplied arguments to ls.exe and enables automatic color
        detection. This wrapper is defined only when GNU Coreutils is available.
        #>
        ls.exe --color=auto @args
    }

    function global:ll {
        <#
        .SYNOPSIS
        Lists detailed directory entries through GNU ls.

        .DESCRIPTION
        Invokes ls.exe with long, all-entry output and automatic color detection.
        Additional arguments are forwarded unchanged to the GNU command.
        #>
        ls.exe -la --color=auto @args
    }
}
else {
    # Fall back to PowerShell-native commands. Keep recursive deletion behind
    # the guarded Remove-ItemTree helper instead of overriding the safe rm alias.
    Set-Alias -Name rmrf -Value Remove-ItemTree -Scope Global -Force

    function global:ls {
        <#
        .SYNOPSIS
        Lists directory entries compactly with PowerShell file colors.

        .DESCRIPTION
        Retrieves entries with Get-ChildItem and writes their names in a compact
        row. Directories, symbolic links, and executable files use the matching
        PSStyle colors when GNU Coreutils is unavailable.
        #>
        $items = Get-ChildItem @args

        foreach ($item in $items) {
            $style = if ($item.PSIsContainer) {
                $PSStyle.FileInfo.Directory
            }
            elseif ($item.LinkType) {
                $PSStyle.FileInfo.SymbolicLink
            }
            elseif ($item.Extension -in '.exe', '.bat', '.cmd', '.ps1') {
                $PSStyle.FileInfo.Executable
            }
            else {
                ''
            }

            Write-Host "$style$($item.Name)$($PSStyle.Reset)  " -NoNewline
        }

        Write-Host
    }

    Set-Alias -Name ll -Value Get-ChildItem -Scope Global -Force
}

Set-Alias -Name ping -Value Test-Connection -Scope Global -Force
Set-Alias -Name which -Value Get-Command -Scope Global -Force

# Vim
if (Get-Command vim -ErrorAction SilentlyContinue) {
    Set-Alias -Name vi -Value vim -Scope Global -Force
}

# WSL commands
# Exposes the commands listed in Settings.psd1 (WslCommands) that are only
# available inside the default WSL distribution. Each command gets a global
# wrapper that runs it in an interactive login Bash through WSL, so it resolves
# from the user's own environment, while CustomShell's interactive startup
# output stays suppressed. A command is skipped when a native command or a
# foreign alias already provides it.
if (Get-Command wsl -ErrorAction SilentlyContinue) {
    $wslCommands = @()
    if ($customShellSettings -and $customShellSettings.WslCommands) {
        $wslCommands = @($customShellSettings.WslCommands)
    }

    foreach ($wslCommand in $wslCommands) {
        if (-not $wslCommand) {
            continue
        }

        $pascalName = ($wslCommand -split '[-_.]' | Where-Object { $_ } | ForEach-Object {
                $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1)
            }) -join ''
        $functionName = "Invoke-Wsl$pascalName"

        $existing = Get-Command $wslCommand -ErrorAction SilentlyContinue
        if ($existing -and -not ($existing.CommandType -eq 'Alias' -and $existing.Definition -eq $functionName)) {
            continue
        }

        $bashScript = '{0} "$@"' -f $wslCommand
        $wrapper = {
            <#
            .SYNOPSIS
            Runs a configured command inside the default WSL login shell.

            .DESCRIPTION
            Starts Bash as an interactive login shell through WSL so the
            command resolves from the user's environment, forwards the
            remaining arguments, and suppresses CustomShell's interactive
            startup output.
            #>
            [CmdletBinding()]
            param(
                [Parameter(ValueFromRemainingArguments)]
                [string[]] $ArgumentList
            )

            wsl -e env 'CUSTOMSHELL_SUPPRESS_STARTUP_OUTPUT=true' bash -lic $bashScript _ @ArgumentList
        }.GetNewClosure()

        Set-Item -Path "Function:\global:$functionName" -Value $wrapper -Force
        Set-Alias -Name $wslCommand -Value $functionName -Scope Global -Force
    }
}
