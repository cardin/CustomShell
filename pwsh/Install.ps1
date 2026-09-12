#Requires -Version 7.0

<#
.SYNOPSIS
Idempotent setup and upgrade helper for CustomShell on Windows.

.DESCRIPTION
Wires the PowerShell profile entry point into the selected profile, sets the
persistent user environment values, installs the shipped Espanso and Clink
configuration files, and reports missing prerequisites. It is safe to run
repeatedly and never installs packages, creates privileged links, or touches
secrets, SSH data, CA certificates, or Git credentials. Configuration files are
copied rather than linked so no elevation is required.

The work is split across modules under pwsh/Install/: common helpers, the
managed profile block, persistent environment values, Espanso discovery,
configuration files, and read-only checks.

.PARAMETER Check
Report the current state and exit non-zero when setup is incomplete.

.PARAMETER Help
Print this help and exit.

.PARAMETER DryRun
Print intended actions without changing anything.

.PARAMETER Uninstall
Remove the managed profile block, the managed environment values, and the
configuration files recorded in the manifest.

.PARAMETER Force
Replace conflicting configuration files. Managed environment values always win
and do not require this switch.

.PARAMETER ProfilePath
Override the profile file to edit. Defaults to the current user's profile.

.PARAMETER EspansoRoot
Override the Espanso configuration root (the directory containing the `config`
and `match` subdirectories).

.PARAMETER ClinkScriptDir
Override the Clink scripts directory.

.PARAMETER StateDir
Override the directory that holds the install manifest and environment record.

.PARAMETER EnvironmentScope
Override the target scope for persistent environment values. Defaults to User;
Process is intended for testing and never touches the registry.
#>
[CmdletBinding()]
param(
    [switch] $Check,
    [switch] $DryRun,
    [switch] $Uninstall,
    [switch] $Force,
    [switch] $Help,
    [string] $ProfilePath,
    [string] $EspansoRoot,
    [string] $ClinkScriptDir,
    [string] $StateDir,
    [ValidateSet('User', 'Process')]
    [string] $EnvironmentScope = 'User'
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Get-Help -Name $PSCommandPath -Detailed | Out-String | Write-Host
    exit 0
}

$markerBegin = '# >>> CustomShell >>>'
$markerEnd = '# <<< CustomShell <<<'

$repoDir = Split-Path -Parent $PSScriptRoot
$entryScript = Join-Path $repoDir 'pwsh/main.ps1'
$configDir = Join-Path $repoDir 'config'
$settings = Import-PowerShellDataFile -LiteralPath (Join-Path $repoDir 'pwsh/Settings.psd1')

foreach ($moduleName in 'Common', 'Profile', 'Environment', 'Espanso', 'Configs', 'Checks') {
    . (Join-Path $PSScriptRoot "Install/$moduleName.ps1")
}

if (-not $ProfilePath) {
    $ProfilePath = $PROFILE
}
if (-not $StateDir) {
    $StateDir = if ($env:LOCALAPPDATA) {
        Join-Path $env:LOCALAPPDATA 'CustomShell'
    }
    else {
        Join-Path $HOME '.local/share/customshell'
    }
}
if (-not $EspansoRoot) {
    $EspansoRoot = Get-DefaultEspansoRoot
}
$EspansoMatchDir = Join-Path $EspansoRoot 'match'
$EspansoConfigDir = Join-Path $EspansoRoot 'config'
if (-not $ClinkScriptDir) {
    if (-not $env:LOCALAPPDATA) {
        throw 'ClinkScriptDir was not provided and LOCALAPPDATA is not set.'
    }
    $ClinkScriptDir = Join-Path $env:LOCALAPPDATA 'clink'
}

$manifestPath = Join-Path $StateDir 'installed.txt'
$desiredSource = ". $(ConvertTo-SingleQuoted $entryScript)"

if ($Check) {
    if ((Invoke-Checks) -gt 0) {
        exit 1
    }
    exit 0
}

if ($Uninstall) {
    Uninstall-ProfileBlock
    Uninstall-PersistentEnvironment
    Uninstall-Configs
    if ($DryRun) {
        Write-Host 'Dry run complete; no changes made.'
    }
    else {
        Write-Host 'CustomShell profile block, environment, and managed configuration removed.'
    }
    exit 0
}

Install-ProfileBlock
Install-PersistentEnvironment
Install-Configs
Write-CommandReport
if ($DryRun) {
    Write-Host 'Dry run complete; no changes made.'
}
else {
    Write-Host "CustomShell setup complete. Restart your shell or run: . $ProfilePath"
}
exit 0
