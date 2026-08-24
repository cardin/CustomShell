# Loads the reusable CustomShell archive and SSH commands from their focused
# implementation files. The module exports only its documented public surface
# and deliberately avoids profile startup or external configuration side effects.
. "$PSScriptRoot/Archive.ps1"
. "$PSScriptRoot/Ssh.ps1"

Export-ModuleMember -Function @(
    'Get-SSHConfig'
    'Decode-Tar'
    'Encode-Tar'
)
