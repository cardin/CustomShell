# Verifies that startup status output is limited to the command reference and
# no longer performs required-command discovery.

Describe 'Show-StartupStatus' {
    BeforeAll {
        $script:statusScript = (Resolve-Path (Join-Path $PSScriptRoot '..\..\Startup\Show-StartupStatus.ps1')).Path
        $script:originalSettings = $global:CustomShellSettings
        $script:originalState = $global:customShellState
    }

    AfterAll {
        $global:CustomShellSettings = $script:originalSettings
        $global:customShellState = $script:originalState
        Remove-Item Function:\global:Show-Help -ErrorAction SilentlyContinue
    }

    It 'defines Show-Help but no longer defines Show-MissingShellCommand' {
        $global:customShellState = [pscustomobject]@{ IsStandaloneTerminal = $false }

        . $script:statusScript

        Get-Command Show-Help -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        Get-Command Show-MissingShellCommand -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }

    It 'does not warn about configured commands during startup' {
        $global:CustomShellSettings = @{ RequiredCommands = @('definitely-not-a-real-command-xyz') }
        $global:customShellState = [pscustomobject]@{ IsStandaloneTerminal = $true }

        $output = & { . $script:statusScript } *>&1 | Out-String

        $output | Should -Not -Match 'Missing commands'
        $output | Should -Match 'Show-Help'
    }
}
