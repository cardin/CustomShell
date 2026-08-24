# Initializes optional environment managers and shell integrations when their
# commands or configured executables are available. Generated initialization
# code is evaluated only after the provider succeeds and returns non-empty text.

if ($env:CONDA_PATH -and (Test-Path -LiteralPath "$env:CONDA_PATH\conda.exe" -PathType Leaf)) {
    function global:Invoke-LazyConda {
        <#
        .SYNOPSIS
        Loads Conda's PowerShell hook on first use and forwards arguments.

        .DESCRIPTION
        Replaces the temporary conda wrapper with Conda's generated PowerShell
        integration, then invokes the requested Conda command. Initialization
        failures are surfaced without evaluating empty or unsuccessful output.
        #>
        [CmdletBinding()]
        param(
            [Parameter(ValueFromRemainingArguments)]
            [object[]] $ArgumentList
        )

        Remove-Item Function:\global:conda -ErrorAction SilentlyContinue
        $condaInitialization = & "$env:CONDA_PATH\conda.exe" shell.powershell hook 2>$null |
            Out-String

        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($condaInitialization)) {
            throw 'Conda did not return valid PowerShell initialization code.'
        }

        Invoke-Expression $condaInitialization
        conda @ArgumentList
    }

    function global:conda {
        <#
        .SYNOPSIS
        Lazily initializes Conda and forwards the requested command.

        .DESCRIPTION
        Acts as the initial global conda command so profile startup does not
        pay Conda's initialization cost. The first invocation delegates to
        Invoke-LazyConda, which installs the real integration before forwarding.
        #>
        Invoke-LazyConda @args
    }
}

if (Get-Command fnm -ErrorAction SilentlyContinue) {
    $fnmInitialization = fnm env --use-on-cd --shell powershell 2>$null | Out-String
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($fnmInitialization)) {
        Invoke-Expression $fnmInitialization
    }
}

if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    $zoxideInitialization = zoxide init powershell 2>$null | Out-String
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($zoxideInitialization)) {
        Invoke-Expression $zoxideInitialization
    }
}

if ($env:TERM_PROGRAM -eq 'vscode' -and (Get-Command code -ErrorAction SilentlyContinue)) {
    $vscodeIntegrationPath = code --locate-shell-integration-path pwsh 2>$null | Select-Object -First 1
    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $vscodeIntegrationPath -PathType Leaf)) {
        . $vscodeIntegrationPath
    }
}
