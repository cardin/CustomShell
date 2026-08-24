# Bootstraps the CustomShell PowerShell profile by loading settings, determining
# the host context, and dot-sourcing each focused startup component in order.
# It also imports the reusable commands module globally and removes temporary
# bootstrap variables so repeated profile loads remain predictable.
[CmdletBinding()]
param(
    # Allows tests or alternate profiles to supply a different settings data file.
    [ValidateNotNullOrEmpty()]
    [string] $SettingsPath = (Join-Path $PSScriptRoot 'Settings.psd1')
)

$customShellSettings = Import-PowerShellDataFile -LiteralPath $SettingsPath
$global:CustomShellSettings = $customShellSettings
$customShellStartupRoot = Join-Path $PSScriptRoot 'Startup'
$customShellProcessNames = @()
$customShellProcessId = $PID

while ($customShellProcessId -ne 0) {
    $customShellProcess = Get-CimInstance `
        -ClassName Win32_Process `
        -Filter "ProcessId=$customShellProcessId" `
        -ErrorAction SilentlyContinue

    if (-not $customShellProcess) {
        break
    }

    $customShellProcessNames += $customShellProcess.Name
    $customShellProcessId = $customShellProcess.ParentProcessId
}

$customShellState = [pscustomobject]@{
    IsStandaloneTerminal = [bool] ($customShellProcessNames | Where-Object {
        $_ -in @('WindowsTerminal.exe', 'cmd.exe')
    })
}

$customShellStartupFiles = @(
    'Initialize-Environment.ps1'
    'Set-InteractiveAliases.ps1'
    'Initialize-Integrations.ps1'
    'Initialize-PSReadLine.ps1'
    'Initialize-Prompt.ps1'
    'Show-StartupStatus.ps1'
)

foreach ($customShellStartupFile in $customShellStartupFiles) {
    $customShellStartupPath = Join-Path $customShellStartupRoot $customShellStartupFile
    $customShellElapsed = Measure-Command { . $customShellStartupPath }

    if (
        $DebugPreference -eq 'Continue' -or
        $customShellElapsed.TotalSeconds -gt $customShellSettings.StartTimeoutSeconds
    ) {
        Write-Host "[CustomShell:$customShellStartupFile] Elapsed time: $($customShellElapsed.TotalSeconds) seconds"
    }
}

$customShellModulePath = Join-Path `
    $PSScriptRoot `
    'Modules/CustomShell.Commands/CustomShell.Commands.psd1'
Import-Module -Name $customShellModulePath -Global -Force

Remove-Variable -Name @(
    'customShellElapsed'
    'customShellModulePath'
    'customShellProcess'
    'customShellProcessId'
    'customShellProcessNames'
    'customShellSettings'
    'customShellState'
    'customShellStartupFile'
    'customShellStartupFiles'
    'customShellStartupPath'
    'customShellStartupRoot'
    'SettingsPath'
) -ErrorAction SilentlyContinue
