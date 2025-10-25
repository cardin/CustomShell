# $DebugPreference = "Continue"

$elapsed_pretty = Measure-Command { . "$PSScriptRoot/Scripts/pretty/main.ps1" }
Write-Debug "[Pretty] Elapsed time: $($elapsed_pretty.TotalSeconds) seconds"

$elapsed_tools = Measure-Command { . "$PSScriptRoot/Scripts/tools/main.ps1" }
Write-Debug "[Tools] Elapsed time: $($elapsed_tools.TotalSeconds) seconds"

function existCheck {
    # Iterate through an array of command names, checking if the command exists
    $commandNames = "bat", "conda", "delta", "fd", "fnm", "less", "node", "nvitop", "rg", "vim", "uv", "zoxide"
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


function helpMe {
    Write-Host -ForegroundColor Blue '󰗉󰗉󰗉  helpMe  󰗉󰗉󰗉'
    Write-Host -ForegroundColor DarkCyan @'
• helpMe
• conda, fnm, z[i], bat[diff], nvitop, vim
• rg <regex> [--glob <str>] [--type <py>] [--no-ignore] [-B|A|C <int>] [-l] [<path> ...]
• fd <regex> [--glob <str>] [-e <py>] [--type d|f] [--no-ignore] [--hidden] [<dir>] [--full-path] [--exec <cmd> {} /;]
• ssh [-p <port>] [-N] [-L <localPort>:localhost:<remotePort>] [-J <user>@<hop1>] <user>@<remoteServer>
• $env:USERPROFILE

'@
}
existCheck
helpMe
