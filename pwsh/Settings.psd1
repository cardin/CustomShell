# Defines the user-adjustable defaults consumed by the PowerShell profile
# bootstrap. The settings select a prompt, control slow-start diagnostics, and
# identify optional commands reported as missing in standalone terminals.
@{
    StartTimeoutSeconds = 1.0
    Prompt               = 'ohmyposh'
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
