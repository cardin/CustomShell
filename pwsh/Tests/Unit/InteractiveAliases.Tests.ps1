# Verifies that configured WSL commands are exposed as interactive wrappers and
# that existing native commands are not shadowed.

Describe 'WSL command exposure' {
    BeforeAll {
        $script:aliasScript = Join-Path $PSScriptRoot '..\..\Startup\Set-InteractiveAliases.ps1'
        $script:testCommand = 'customshell-wsl-probe'
        $script:testAlias = "$testCommand-wsl"
        $script:testFunction = 'Invoke-WslCustomshellWslProbe'
    }

    BeforeEach {
        function global:wsl {
            $script:receivedWslArguments = @($args)
        }
        $global:customShellSettings = @{ WslCommands = @($testCommand) }

        . $script:aliasScript
    }

    AfterEach {
        Remove-Item -Path Function:\global:wsl -ErrorAction SilentlyContinue
        Remove-Item -Path "Function:\global:$testFunction" -ErrorAction SilentlyContinue
        Remove-Item -Path "Alias:\$testCommand" -ErrorAction SilentlyContinue
        Remove-Item -Path "Alias:\$testAlias" -ErrorAction SilentlyContinue
        Remove-Variable -Name customShellSettings -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name CustomShellManagedWslCommands -Scope Global -ErrorAction SilentlyContinue
        $script:receivedWslArguments = $null
    }

    It 'routes a configured command through a suppressed WSL login shell' {
        & $testCommand 'sub' '--flag' 'two words'

        $expected = @(
            '-e'
            'env'
            'CUSTOMSHELL_SUPPRESS_STARTUP_OUTPUT=true'
            'bash'
            '-lic'
            ('{0} "$@"' -f $testCommand)
            '_'
            'sub'
            '--flag'
            'two words'
        )
        ($script:receivedWslArguments -join '|') | Should -Be ($expected -join '|')
    }

    It 'does not shadow a command already provided natively' {
        $nativeName = 'customshell-wsl-native-probe'
        Set-Item -Path "Function:\global:$nativeName" -Value { 'native' }
        try {
            $global:customShellSettings = @{ WslCommands = @($nativeName) }

            . $script:aliasScript

            (Get-Command $nativeName).CommandType | Should -Be 'Function'
            Get-Alias -Name $nativeName -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        }
        finally {
            Remove-Item -Path "Function:\global:$nativeName" -ErrorAction SilentlyContinue
            Remove-Item -Path "Alias:\$nativeName" -ErrorAction SilentlyContinue
        }
    }

    It 'replaces the old alias with the configured Windows name and forwards to the original WSL command' {
        $global:customShellSettings = @{ WslCommands = @(@{ Command = $testCommand; Alias = $testAlias }) }

        . $script:aliasScript

        Get-Alias -Name $testCommand -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        & $testAlias '--flag' 'two words'
        $script:receivedWslArguments[5] | Should -Be ('{0} "$@"' -f $testCommand)
        ($script:receivedWslArguments[7..8] -join '|') | Should -Be '--flag|two words'
    }

    It 'allows a native command to coexist but does not shadow a native command at the configured alias' {
        $global:customShellSettings = @{ WslCommands = @(@{ Command = $testCommand; Alias = $testAlias }) }
        Set-Item -Path "Function:\global:$testCommand" -Value { 'native' }
        try {
            . $script:aliasScript

            (& $testCommand) | Should -Be 'native'
            (Get-Alias -Name $testAlias).Definition | Should -Be $testFunction

            Set-Item -Path "Function:\global:$testAlias" -Value { 'native alias name' }
            . $script:aliasScript

            (& $testAlias) | Should -Be 'native alias name'
            Get-Alias -Name $testAlias -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        }
        finally {
            Remove-Item -Path "Function:\global:$testCommand", "Function:\global:$testAlias" -ErrorAction SilentlyContinue
        }
    }

    It 'removes a previously managed wrapper when settings change' {
        $global:customShellSettings = @{ WslCommands = @() }

        . $script:aliasScript

        Get-Alias -Name $testCommand -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Item -Path "Function:\global:$testFunction" -ErrorAction SilentlyContinue |
            Should -BeNullOrEmpty
    }
}
