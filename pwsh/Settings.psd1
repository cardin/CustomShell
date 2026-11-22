# Defines the user-adjustable defaults consumed by the PowerShell profile
# bootstrap. The settings select a prompt, control slow-start diagnostics,
# identify optional commands reported as missing in standalone terminals, and
# list the commands and optional PowerShell alias names exposed from WSL.
@{
    StartTimeoutSeconds = 1.0
    Prompt               = 'ohmyposh'
    WslCommands          = @(
        @{ Command = 'opencode'; Alias = 'opencode-wsl' }
    )
    RequiredCommands     = @(
        'age'
        'bat'
        'conda'
        'delta'
        'fd'
        'fzf'
        'jq'
        'less'
        'node'
        'nvitop'
        'pipx'
        'python'
        'rg'
        'vim'
        'zoxide'
    )
}
