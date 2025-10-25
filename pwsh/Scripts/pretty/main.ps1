$elapsed_starship = Measure-Command { . "$PSScriptRoot/starship.ps1" }
$elapsed_readline = Measure-Command { . "$PSScriptRoot/readline.ps1" }

Write-Debug "`t[Starship] Elapsed time: $($elapsed_starship.TotalSeconds) seconds"
Write-Debug "`t[Readline] Elapsed time: $($elapsed_readline.TotalSeconds) seconds"
