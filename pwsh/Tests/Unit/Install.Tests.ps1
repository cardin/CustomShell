# Exercises the idempotent Windows setup helper in an isolated temporary tree.
# Every invocation runs in a child PowerShell process because the installer is
# an entry script that exits with a status code. The Process environment scope
# is used so tests never modify the real user environment.

Describe 'CustomShell Install.ps1' {
    BeforeAll {
        $script:repoDir = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
        $script:installScript = Join-Path $script:repoDir 'pwsh\Install.ps1'
        $script:entryScript = Join-Path $script:repoDir 'pwsh\main.ps1'
        $script:powerShellPath = (Get-Process -Id $PID).Path

        function Invoke-Installer {
            param(
                [string[]] $Arguments = @()
            )

            $argumentList = @(
                '-NoLogo', '-NoProfile', '-File', $script:installScript
                '-ProfilePath', $script:profilePath
                '-EspansoRoot', $script:espansoRoot
                '-ClinkScriptDir', $script:clinkDir
                '-StateDir', $script:stateDir
                '-EnvironmentScope', 'Process'
            )
            if ($Arguments) {
                $argumentList += $Arguments
            }

            $output = & $script:powerShellPath @argumentList 2>&1
            return [pscustomobject]@{
                Output   = ($output -join "`n")
                ExitCode = $LASTEXITCODE
            }
        }
    }

    BeforeEach {
        $script:testRoot = Join-Path ([IO.Path]::GetTempPath()) "CustomShell.Install-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $testRoot | Out-Null
        $script:profilePath = Join-Path $testRoot 'profile.ps1'
        $script:espansoRoot = Join-Path $testRoot 'espanso'
        $script:espansoMatchDir = Join-Path $espansoRoot 'match'
        $script:espansoConfigDir = Join-Path $espansoRoot 'config'
        $script:clinkDir = Join-Path $testRoot 'clink'
        $script:stateDir = Join-Path $testRoot 'state'
        $script:environmentRecord = Join-Path $stateDir 'environment.txt'

        $script:originalUvCerts = $env:UV_SYSTEM_CERTS
        Remove-Item Env:UV_SYSTEM_CERTS -ErrorAction SilentlyContinue
    }

    AfterEach {
        if ($null -eq $script:originalUvCerts) {
            Remove-Item Env:UV_SYSTEM_CERTS -ErrorAction SilentlyContinue
        }
        else {
            $env:UV_SYSTEM_CERTS = $script:originalUvCerts
        }

        $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
        $resolvedTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if ($resolvedTestRoot.StartsWith($resolvedTempRoot, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'inserts one managed block and preserves existing content' {
        Set-Content -LiteralPath $profilePath -Value @('# user profile', 'Set-Alias foo bar')

        $result = Invoke-Installer

        $result.ExitCode | Should -Be 0
        $content = [IO.File]::ReadAllText($profilePath)
        $content | Should -Match ([regex]::Escape('# >>> CustomShell >>>'))
        $content | Should -Match 'Set-Alias foo bar'
        ([regex]::Matches($content, [regex]::Escape('# >>> CustomShell >>>'))).Count | Should -Be 1
        $content | Should -Match ([regex]::Escape($entryScript))
    }

    It 'is idempotent across repeated runs' {
        Set-Content -LiteralPath $profilePath -Value @('# user profile')
        Invoke-Installer | Out-Null
        $before = (Get-FileHash -LiteralPath $profilePath).Hash

        $result = Invoke-Installer

        $result.ExitCode | Should -Be 0
        (Get-FileHash -LiteralPath $profilePath).Hash | Should -Be $before
    }

    It 'rewrites a stale block in place' {
        Set-Content -LiteralPath $profilePath -Value @(
            '# >>> CustomShell >>>'
            ". 'C:\old\location\pwsh\main.ps1'"
            '# <<< CustomShell <<<'
        )

        $result = Invoke-Installer

        $result.ExitCode | Should -Be 0
        $content = [IO.File]::ReadAllText($profilePath)
        $content | Should -Match ([regex]::Escape($entryScript))
        $content | Should -Not -Match 'C:\\old\\location'
        ([regex]::Matches($content, [regex]::Escape('# >>> CustomShell >>>'))).Count | Should -Be 1
    }

    It 'installs configuration files in the Espanso config and match directories' {
        $result = Invoke-Installer

        $result.ExitCode | Should -Be 0

        $baseSource = Join-Path $repoDir 'config\espanso\_base.yml'
        $baseDestination = Join-Path $espansoMatchDir '_base.yml'
        Test-Path -LiteralPath $baseDestination | Should -Be $true
        (Get-FileHash -LiteralPath $baseDestination).Hash |
            Should -Be (Get-FileHash -LiteralPath $baseSource).Hash

        $whitelistSource = Join-Path $repoDir 'config\espanso\whitelist.yml'
        $whitelistDestination = Join-Path $espansoConfigDir 'whitelist.yml'
        Test-Path -LiteralPath $whitelistDestination | Should -Be $true
        (Get-FileHash -LiteralPath $whitelistDestination).Hash |
            Should -Be (Get-FileHash -LiteralPath $whitelistSource).Hash

        $clinkSources = @(Get-ChildItem -LiteralPath (Join-Path $repoDir 'config\clink') -Filter '*.lua' -File)
        $clinkSources.Count | Should -BeGreaterThan 0
        foreach ($source in $clinkSources) {
            Test-Path -LiteralPath (Join-Path $clinkDir $source.Name) | Should -Be $true
        }

        Test-Path -LiteralPath (Join-Path $stateDir 'installed.txt') | Should -Be $true
    }

    It 'sets and records the persistent environment values' {
        $result = Invoke-Installer

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'Set Process environment variable UV_SYSTEM_CERTS=true'
        $batConfigPath = Join-Path $repoDir 'config\bat.conf'
        $result.Output | Should -Match ([regex]::Escape("Set Process environment variable BAT_CONFIG_PATH=$batConfigPath"))
        Test-Path -LiteralPath $environmentRecord | Should -Be $true
        $recorded = Get-Content -LiteralPath $environmentRecord
        $recorded | Should -Contain 'UV_SYSTEM_CERTS'
        $recorded | Should -Contain 'BAT_CONFIG_PATH'
    }

    It 'overwrites a conflicting environment value' {
        $env:UV_SYSTEM_CERTS = 'false'

        $result = Invoke-Installer

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'Set Process environment variable UV_SYSTEM_CERTS=true'
        Test-Path -LiteralPath $environmentRecord | Should -Be $true
    }

    It 'skips a conflicting file without -Force and backs it up with -Force' {
        New-Item -ItemType Directory -Path $espansoMatchDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $espansoMatchDir '_base.yml') -Value 'user data'

        $first = Invoke-Installer
        $first.ExitCode | Should -Be 0
        (Get-Content -LiteralPath (Join-Path $espansoMatchDir '_base.yml') -Raw).Trim() |
            Should -Be 'user data'

        $second = Invoke-Installer -Arguments @('-Force')
        $second.ExitCode | Should -Be 0

        $baseSource = Join-Path $repoDir 'config\espanso\_base.yml'
        (Get-FileHash -LiteralPath (Join-Path $espansoMatchDir '_base.yml')).Hash |
            Should -Be (Get-FileHash -LiteralPath $baseSource).Hash
        (Get-Content -LiteralPath (Join-Path $espansoMatchDir '_base.yml.customshell.bak') -Raw).Trim() |
            Should -Be 'user data'
    }

    It 'restores the original profile and environment record on uninstall' {
        Set-Content -LiteralPath $profilePath -Value @('# user profile', 'Set-Alias foo bar')
        $before = (Get-FileHash -LiteralPath $profilePath).Hash
        Invoke-Installer | Out-Null

        $result = Invoke-Installer -Arguments @('-Uninstall')

        $result.ExitCode | Should -Be 0
        (Get-FileHash -LiteralPath $profilePath).Hash | Should -Be $before
        Test-Path -LiteralPath (Join-Path $espansoMatchDir '_base.yml') | Should -Be $false
        Test-Path -LiteralPath (Join-Path $espansoConfigDir 'whitelist.yml') | Should -Be $false
        Test-Path -LiteralPath (Join-Path $stateDir 'installed.txt') | Should -Be $false
        Test-Path -LiteralPath $environmentRecord | Should -Be $false
    }

    It 'changes nothing during a dry run' {
        Set-Content -LiteralPath $profilePath -Value @('# user profile')
        $before = (Get-FileHash -LiteralPath $profilePath).Hash

        $result = Invoke-Installer -Arguments @('-DryRun')

        $result.ExitCode | Should -Be 0
        (Get-FileHash -LiteralPath $profilePath).Hash | Should -Be $before
        Test-Path -LiteralPath $espansoRoot | Should -Be $false
        Test-Path -LiteralPath $environmentRecord | Should -Be $false
    }

    It 'reports check failures until the setup is installed' {
        $unconfigured = Invoke-Installer -Arguments @('-Check')
        $unconfigured.ExitCode | Should -Be 1

        Invoke-Installer | Out-Null

        $configured = Invoke-Installer -Arguments @('-Check')
        $configured.ExitCode | Should -Be 0
    }

    It 'reports the required command state during a normal install' {
        $result = Invoke-Installer

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'Commands:'
    }

    It 'prints help and exits without changing anything' {
        Set-Content -LiteralPath $profilePath -Value @('# user profile')
        $before = (Get-FileHash -LiteralPath $profilePath).Hash

        $result = Invoke-Installer -Arguments @('-Help')

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'SYNOPSIS'
        (Get-FileHash -LiteralPath $profilePath).Hash | Should -Be $before
    }

    It 'leaves an unmarked manual source line untouched' {
        Set-Content -LiteralPath $profilePath -Value ". '$entryScript'"
        $before = (Get-FileHash -LiteralPath $profilePath).Hash

        $result = Invoke-Installer

        $result.ExitCode | Should -Be 0
        (Get-FileHash -LiteralPath $profilePath).Hash | Should -Be $before
        $result.Output | Should -Match 'unmarked|already sources'
    }
}
