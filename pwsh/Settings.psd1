# Defines the user-adjustable defaults consumed by the PowerShell profile
# bootstrap. The settings select a prompt, control slow-start diagnostics,
# identify optional commands reported as missing in standalone terminals, and
# list the commands exposed from WSL when they are not available natively.
@{
    StartTimeoutSeconds = 1.0
    Prompt               = 'ohmyposh'
    WslCommands          = @(
        'opencode'
        'agent-deck'
    )
    RequiredCommands     = @(
        'age'
        'bat'
        'conda'
        'delta'
        'fd'
        'fzf'
        'less'
        'node'
        'nvitop'
        'pipx'
        'rg'
        'vim'
        'zoxide'
    )
}
