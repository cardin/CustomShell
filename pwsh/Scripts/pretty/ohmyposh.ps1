$theme = if ($env:IsBareTerminal -ne "True") {
    "ascii.json"
}
else {
    "catppuccin_gruvbox.json"
}

oh-my-posh init pwsh --config "$PSScriptRoot/../../../config/omp/$theme" | Invoke-Expression
