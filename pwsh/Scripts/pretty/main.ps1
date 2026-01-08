$elapsed_readline = Measure-Command { . "$PSScriptRoot/readline.ps1" }
if (($env:WT_SESSION -or ($env:TERM_PROGRAM -eq 'vscode')) -and -not $env:SKIP_STARSHIP) {
    $elapsed_prompt = Measure-Command { . "$PSScriptRoot/starship.ps1" }
        
    if ($DebugPreference -eq "Continue") {
        $env:STARSHIP_LOG = "trace"
        starship timings
        Remove-Item Env:STARSHIP_LOG
    }
} else {
    $elapsed_prompt = Measure-Command { . "$PSScriptRoot/ohmyposh.ps1" }
}

if ($DebugPreference -eq "Continue" -or $elapsed_prompt.TotalSeconds -gt $StartTimeout) {
    Write-Host "`t[Prompt] Elapsed time: $($elapsed_prompt.TotalSeconds) seconds"
}
if ($DebugPreference -eq "Continue" -or $elapsed_readline.TotalSeconds -gt $StartTimeout) {
    Write-Host "`t[Readline] Elapsed time: $($elapsed_readline.TotalSeconds) seconds"
}
