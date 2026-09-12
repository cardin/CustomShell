#Requires -Version 7.0

<#
.SYNOPSIS
Idempotent setup and upgrade helper for CustomShell on Windows.

.DESCRIPTION
Wires the PowerShell profile entry point into the current user's all-hosts
profile, so every PowerShell host (the console and the VS Code PowerShell host)
loads CustomShell exactly once. It sets the persistent user environment values,
installs the shipped Espanso configuration, registers the Clink script path and
settings when Clink is available, and reports missing prerequisites. It is safe
to run repeatedly and never installs packages, creates privileged links, or
touches secrets, SSH data, CA certificates, or Git credentials. Configuration
files are copied rather than linked so no elevation is required.

The work is split across modules under pwsh/Install/: common helpers, the
managed profile block, persistent environment values, Espanso discovery,
configuration files, Clink configuration, and read-only checks.

.PARAMETER Check
Report the current state and exit non-zero when setup is incomplete.

.PARAMETER Help
Print this help and exit.

.PARAMETER DryRun
Print intended actions without changing anything.

.PARAMETER Uninstall
Remove the managed profile block, the managed environment values, the
configuration files recorded in the manifest, and the Clink script path and
settings recorded in the state file.

.PARAMETER Force
Replace conflicting configuration files. Managed environment values always win
and do not require this switch.

.PARAMETER ProfilePath
Override the profile file to edit. Defaults to the current user's all-hosts
profile, which loads in every PowerShell host.

.PARAMETER EspansoRoot
Override the Espanso configuration root (the directory containing the `config`
and `match` subdirectories).

.PARAMETER ClinkCommand
Override the Clink command. Defaults to `clink` on PATH. Providing a value
disables PATH discovery, so a missing command is treated as Clink being absent.

.PARAMETER SettingsPath
Override the settings data file. Defaults to pwsh/Settings.psd1.

.PARAMETER StateDir
Override the directory that holds the install manifest, environment record,
and Clink state.

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
    [string] $ClinkCommand,
    [string] $SettingsPath,
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
if (-not $SettingsPath) {
    $SettingsPath = Join-Path $repoDir 'pwsh/Settings.psd1'
}
$settings = Import-PowerShellDataFile -LiteralPath $SettingsPath

foreach ($moduleName in 'Common', 'Profile', 'Environment', 'Espanso', 'Configs', 'Clink', 'Checks') {
    . (Join-Path $PSScriptRoot "Install/$moduleName.ps1")
}

if (-not $ProfilePath) {
    $ProfilePath = $PROFILE.CurrentUserAllHosts
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
    Uninstall-Clink
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
Install-Clink
Write-CommandReport
if ($DryRun) {
    Write-Host 'Dry run complete; no changes made.'
}
else {
    Write-Host "CustomShell setup complete. Restart your shell or run: . $ProfilePath"
}
exit 0
