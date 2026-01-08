# === CONFIGURATIONS ===
# $DebugPreference = "Continue"
$StartTimeout = 1 # seconds
$env:PrettyPromptSelection = 'ohmyposh' # 'ohmyposh' | 'starship'
# =======================

$elapsed_pretty = Measure-Command { . "$PSScriptRoot/Scripts/pretty/main.ps1" }
if ($DebugPreference -eq "Continue" -or $elapsed_pretty.TotalSeconds -gt $StartTimeout) {
    Write-Host "[Pretty] Elapsed time: $($elapsed_pretty.TotalSeconds) seconds"
}

$elapsed_tools = Measure-Command { . "$PSScriptRoot/Scripts/tools/main.ps1" }
if ($DebugPreference -eq "Continue" -or $elapsed_tools.TotalSeconds -gt $StartTimeout) {
    Write-Host "[Tools] Elapsed time: $($elapsed_tools.TotalSeconds) seconds"
}

function existCheck {
    # Iterate through an array of command names, checking if the command exists
    $commandNames = "bat", "conda", "delta", "fd", "less", "node", "nvitop", "rg", "vim", "uv", "zoxide"
    $missing = $false
    foreach ($name in $commandNames) {
        if (!(Get-Command $name -ErrorAction SilentlyContinue)) {
            $missing = $true
            Write-Host -ForegroundColor Red -NoNewline "󰬅$name "
        }
    }
    if ($missing) {
        Write-Host ""
    }
}


function manShell {
    Write-Host -ForegroundColor Blue '󰗉󰗉󰗉  manShell()  󰗉󰗉󰗉'
    Write-Host -ForegroundColor Green @'
• conda 󰇙 pipx 󰇙 uv 󰇙 node
• z[i] 󰇙 bat[diff] 󰇙 nvitop 󰇙 vim
• rg <regex> [--glob ..] [--type <py>] [--no-ignore] [--hidden] [--max-depth ..] 
    [-l] [-B|A|C <int>] [<path> ...]
• fd <regex> [--glob ..] [--type d|f] [--no-ignore] [--hidden] [--max|min-depth ..] 
    [--full-path] [-e <py>] [<targetDir>] [--exec <cmd> {} /;]
• ssh [-p <port>] [-NT] [-L [<local>:]<port>:<remote>:<port>] [-J <user>@<hop1>] <user>@<hop2>
• $env:USERPROFILE
'@
}
existCheck
manShell
