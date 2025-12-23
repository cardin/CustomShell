$elapsed_clitools = Measure-Command { . "$PSScriptRoot/cli_tools.ps1" }
if ($DebugPreference -eq "Continue" -or $elapsed_clitools.TotalSeconds -gt $StartTimeout) {
    Write-Host "`t[CliTools] Elapsed time: $($elapsed_clitools.TotalSeconds) seconds"
}

# This must be AFTER the Command Existence Check
$elapsed_env_activators = Measure-Command { . "$PSScriptRoot/env_activators.ps1" }
if ($DebugPreference -eq "Continue" -or $elapsed_env_activators.TotalSeconds -gt $StartTimeout) {
    Write-Host "`t[EnvActivators] Elapsed time: $($elapsed_env_activators.TotalSeconds) seconds"
}
