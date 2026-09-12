# Verifies that the Starship prompt integration points at the repository theme
# instead of the default user configuration path, selecting the theme that suits
# the detected terminal.

Describe 'Starship prompt configuration' {
    BeforeAll {
        $script:promptScript = (Resolve-Path (Join-Path $PSScriptRoot '..\..\Startup\Initialize-Prompt.ps1')).Path
        $script:starshipConfigDir = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\config\starship')).Path
    }

    BeforeEach {
        $script:originalStarshipConfig = $env:STARSHIP_CONFIG
        $script:originalSettings = $global:CustomShellSettings
        $script:originalState = $global:customShellState

        $global:CustomShellSettings = @{ Prompt = 'starship' }
        function global:starship {
            $global:LASTEXITCODE = 0
        }
    }

    AfterEach {
        $env:STARSHIP_CONFIG = $script:originalStarshipConfig
        $global:CustomShellSettings = $script:originalSettings
        $global:customShellState = $script:originalState
        Remove-Item Function:\global:starship -ErrorAction SilentlyContinue
    }

    It 'selects the plain-text theme outside a standalone terminal' {
        $global:customShellState = [pscustomobject]@{ IsStandaloneTerminal = $false }

        . $script:promptScript

        $env:STARSHIP_CONFIG |
            Should -Be (Join-Path $starshipConfigDir 'plain-text-symbols.toml')
    }

    It 'selects the powerline theme in a standalone terminal' {
        $global:customShellState = [pscustomobject]@{ IsStandaloneTerminal = $true }

        . $script:promptScript

        $env:STARSHIP_CONFIG |
            Should -Be (Join-Path $starshipConfigDir 'catppuccin-powerline.toml')
    }
}
