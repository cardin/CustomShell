if (($env:WT_SESSION -or ($env:TERM_PROGRAM -eq 'vscode')) -and -not $env:SKIP_STARSHIP) {
    $elapsed_starship = Measure-Command { . "$PSScriptRoot/starship.ps1" }
    $elapsed_readline = Measure-Command { . "$PSScriptRoot/readline.ps1" }
}

if ($DebugPreference -eq "Continue") {
    $env:STARSHIP_LOG = "trace"
    starship timings
    Remove-Item Env:STARSHIP_LOG
}

if ($DebugPreference -eq "Continue" -or $elapsed_starship.TotalSeconds -gt $StartTimeout) {
    Write-Host "`t[Starship] Elapsed time: $($elapsed_starship.TotalSeconds) seconds"
}
if ($DebugPreference -eq "Continue" -or $elapsed_readline.TotalSeconds -gt $StartTimeout) {
    Write-Host "`t[Readline] Elapsed time: $($elapsed_readline.TotalSeconds) seconds"
}
