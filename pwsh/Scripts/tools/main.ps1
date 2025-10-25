$elapsed_clitools = Measure-Command { . "$PSScriptRoot/cli_tools.ps1" }
Write-Debug "`t[CliTools] Elapsed time: $($elapsed_clitools.TotalSeconds) seconds"

# This must be AFTER the Command Existence Check
$elapsed_env_activators = Measure-Command { . "$PSScriptRoot/env_activators.ps1" }
Write-Debug "`t[EnvActivators] Elapsed time: $($elapsed_env_activators.TotalSeconds) seconds"
