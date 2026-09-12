# Verifies that configured WSL commands are exposed as interactive wrappers and
# that existing native commands are not shadowed.

Describe 'WSL command exposure' {
    BeforeAll {
        $script:aliasScript = Join-Path $PSScriptRoot '..\..\Startup\Set-InteractiveAliases.ps1'
        $script:testCommand = 'customshell-wsl-probe'
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
        Remove-Variable -Name customShellSettings -Scope Global -ErrorAction SilentlyContinue
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
}
