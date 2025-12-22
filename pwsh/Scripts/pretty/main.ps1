if ($env:WT_SESSION -or ($env:TERM_PROGRAM -eq 'vscode')) {
    $elapsed_starship = Measure-Command { . "$PSScriptRoot/starship.ps1" }
    $elapsed_readline = Measure-Command { . "$PSScriptRoot/readline.ps1" }
}

if ($DebugPreference -eq "Continue") {
    $env:STARSHIP_LOG = "trace"
    starship timings
    Remove-Item Env:STARSHIP_LOG
}

Write-Debug "`t[Starship] Elapsed time: $($elapsed_starship.TotalSeconds) seconds"
Write-Debug "`t[Readline] Elapsed time: $($elapsed_readline.TotalSeconds) seconds"
