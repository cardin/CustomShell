$env:STARSHIP_UPDATE_CHECK = "false"

function Invoke-Starship-PreCommand {
    $host.ui.RawUI.WindowTitle = [System.IO.Path]::GetFileName($pwd)
}
# https://github.com/starship/starship/issues/5917#issuecomment-2080401050
&starship init powershell --print-full-init | Out-String | Invoke-Expression
