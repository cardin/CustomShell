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
                [string[]] $Arguments = @(),
                [string] $ProfilePath = $script:profilePath,
                [string] $ClinkCommand = $script:clinkCommand,
                [string] $SettingsPath = $script:settingsPath
            )

            $argumentList = @(
                '-NoLogo', '-NoProfile', '-File', $script:installScript
                '-ProfilePath', $ProfilePath
                '-EspansoRoot', $script:espansoRoot
                '-ClinkCommand', $ClinkCommand
                '-SettingsPath', $SettingsPath
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

        function Get-FakeClinkState {
            if (-not (Test-Path -LiteralPath $script:fakeClinkState)) {
                return $null
            }
            return Get-Content -LiteralPath $script:fakeClinkState -Raw | ConvertFrom-Json
        }

        function Get-FakeClinkCalls {
            if (-not (Test-Path -LiteralPath $script:fakeClinkLog)) {
                return @()
            }
            return @(Get-Content -LiteralPath $script:fakeClinkLog)
        }

        function New-TestSettings {
            param([string] $Prompt)

            $source = Import-PowerShellDataFile -LiteralPath (Join-Path $script:repoDir 'pwsh\Settings.psd1')
            $source.Prompt = $Prompt
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add('@{')
            foreach ($key in $source.Keys) {
                $value = $source[$key]
                if ($value -is [System.Array]) {
                    $lines.Add("    $key = @(")
                    foreach ($item in $value) {
                        $lines.Add("        '" + $item.ToString().Replace("'", "''") + "'")
                    }
                    $lines.Add('    )')
                }
                elseif ($value -is [string]) {
                    $lines.Add("    $key = '" + $value.Replace("'", "''") + "'")
                }
                else {
                    $lines.Add("    $key = $($value.ToString([System.Globalization.CultureInfo]::InvariantCulture))")
                }
            }
            $lines.Add('}')

            $path = Join-Path $script:testRoot "Settings-$Prompt.psd1"
            Set-Content -LiteralPath $path -Value $lines
            return $path
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
        $script:originalWslenv = $env:WSLENV
        Remove-Item Env:WSLENV -ErrorAction SilentlyContinue
        $script:originalBatConfigPath = $env:BAT_CONFIG_PATH
        Remove-Item Env:BAT_CONFIG_PATH -ErrorAction SilentlyContinue

        # Provide a fake conda.exe on PATH so discovery is deterministic and
        # never depends on the host's conda installation.
        $script:originalCondaPath = $env:CONDA_PATH
        Remove-Item Env:CONDA_PATH -ErrorAction SilentlyContinue
        $script:originalPath = $env:PATH
        $script:condaDir = Join-Path $testRoot 'conda'
        New-Item -ItemType Directory -Path $condaDir | Out-Null
        New-Item -ItemType File -Path (Join-Path $condaDir 'conda.exe') | Out-Null

        $script:settingsPath = Join-Path $script:repoDir 'pwsh\Settings.psd1'
        $script:clinkCommand = Join-Path $testRoot 'fake-clink.ps1'
        $script:fakeClinkState = Join-Path $testRoot 'fake-clink-state.json'
        $script:fakeClinkLog = Join-Path $testRoot 'fake-clink-calls.log'

        # Deterministic stand-ins for the prompt engines so the selected prompt
        # is always considered present, regardless of what the host has.
        New-Item -ItemType File -Path (Join-Path $condaDir 'oh-my-posh.cmd') -Value '@exit /b 0' | Out-Null
        New-Item -ItemType File -Path (Join-Path $condaDir 'starship.cmd') -Value '@exit /b 0' | Out-Null

        # A minimal Clink stand-in that persists settings, registered script
        # paths, and a call log alongside itself.
        $fakeClink = @'
$stateFile = Join-Path $PSScriptRoot 'fake-clink-state.json'
$logFile = Join-Path $PSScriptRoot 'fake-clink-calls.log'
Add-Content -LiteralPath $logFile -Value ($args -join ' ')

$state = [ordered]@{ settings = [ordered]@{}; scriptPaths = @() }
if (Test-Path -LiteralPath $stateFile) {
    $loaded = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
    if ($loaded.settings) {
        foreach ($property in $loaded.settings.PSObject.Properties) {
            $state.settings[$property.Name] = $property.Value
        }
    }
    if ($loaded.scriptPaths) {
        $state.scriptPaths = @($loaded.scriptPaths)
    }
}

function Save-FakeState {
    $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $stateFile
}

function Get-KnownSettings {
    $known = @('clink.customprompt', 'clink.autostart')
    foreach ($key in $state.settings.Keys) {
        if ($known -notcontains $key) { $known += $key }
    }
    if ($state.settings['clink.customprompt'] -match 'oh-my-posh') {
        if ($known -notcontains 'ohmyposh.theme') { $known += 'ohmyposh.theme' }
    }
    return $known
}

$command = $args[0]
switch ($command) {
    'set' {
        $name = $args[1]
        $known = Get-KnownSettings
        if ($args.Count -ge 3) {
            if ($known -notcontains $name) {
                Write-Output "ERROR: Setting '$name' not found."
                exit 1
            }
            if ($args[2] -eq 'clear') {
                $state.settings.Remove($name)
            }
            else {
                $state.settings[$name] = $args[2]
            }
            Save-FakeState
            Write-Output "Set $name"
            exit 0
        }
        if ($known -notcontains $name) {
            Write-Output "ERROR: Setting '$name' not found."
            exit 1
        }
        $value = if ($state.settings.Contains($name)) { $state.settings[$name] } else { '' }
        Write-Output ("        Name: " + $name)
        Write-Output ' Description: fake setting'
        Write-Output ("       Value: " + $value)
        Write-Output '     Default:'
        exit 0
    }
    'config' {
        $name = $args[3]
        $themesDir = Join-Path $PSScriptRoot 'themes'
        if (-not (Test-Path -LiteralPath $themesDir)) {
            New-Item -ItemType Directory -Path $themesDir | Out-Null
        }
        $promptFile = Join-Path $themesDir "$name.clinkprompt"
        Set-Content -LiteralPath $promptFile -Value ''
        $state.settings['clink.customprompt'] = $promptFile
        Save-FakeState
        Write-Output "Applied custom prompt from '$promptFile'."
        exit 0
    }
    'installscripts' {
        if ($args[1] -eq '--list') {
            foreach ($path in $state.scriptPaths) { Write-Output $path }
            exit 0
        }
        $path = $args[1]
        if ($state.scriptPaths -contains $path) {
            Write-Output "Script path '$path' is already installed."
            exit 1
        }
        $state.scriptPaths = @($state.scriptPaths) + $path
        Save-FakeState
        Write-Output "Script path '$path' installed."
        exit 0
    }
    'uninstallscripts' {
        $path = $args[1]
        if ($state.scriptPaths -notcontains $path) {
            Write-Output "Script path '$path' is not installed."
            exit 1
        }
        $state.scriptPaths = @($state.scriptPaths | Where-Object { $_ -ne $path })
        Save-FakeState
        Write-Output "Script path '$path' uninstalled."
        exit 0
    }
    default {
        Write-Output 'unknown command'
        exit 1
    }
}
'@
        Set-Content -LiteralPath $script:clinkCommand -Value $fakeClink

        $env:PATH = "$condaDir$([IO.Path]::PathSeparator)$env:PATH"
    }

    AfterEach {
        if ($null -eq $script:originalUvCerts) {
            Remove-Item Env:UV_SYSTEM_CERTS -ErrorAction SilentlyContinue
        }
        else {
            $env:UV_SYSTEM_CERTS = $script:originalUvCerts
        }
        if ($null -eq $script:originalWslenv) {
            Remove-Item Env:WSLENV -ErrorAction SilentlyContinue
        }
        else {
            $env:WSLENV = $script:originalWslenv
        }
        if ($null -eq $script:originalCondaPath) {
            Remove-Item Env:CONDA_PATH -ErrorAction SilentlyContinue
        }
        else {
            $env:CONDA_PATH = $script:originalCondaPath
        }
        if ($null -eq $script:originalBatConfigPath) {
            Remove-Item Env:BAT_CONFIG_PATH -ErrorAction SilentlyContinue
        }
        else {
            $env:BAT_CONFIG_PATH = $script:originalBatConfigPath
        }
        $env:PATH = $script:originalPath

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

        # Clink scripts are registered from the repository, not copied.
        Test-Path -LiteralPath $clinkDir | Should -Be $false

        $clinkState = Get-FakeClinkState
        @($clinkState.scriptPaths) | Should -Contain (Join-Path $repoDir 'config\clink')
        $clinkState.settings.'clink.autostart' |
            Should -Be (Join-Path $repoDir 'config\clink\clink_start.cmd')
        $clinkState.settings.'ohmyposh.theme' |
            Should -Be (Join-Path $repoDir 'config\omp\catppuccin_gruvbox.json')

        Test-Path -LiteralPath (Join-Path $stateDir 'installed.txt') | Should -Be $true
    }

    It 'sets and records the persistent environment values' {
        $result = Invoke-Installer

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'Set Process environment variable UV_SYSTEM_CERTS=true'
        $batConfigPath = Join-Path $repoDir 'config\bat.conf'
        $result.Output | Should -Match ([regex]::Escape("Set Process environment variable BAT_CONFIG_PATH=$batConfigPath"))
        $result.Output | Should -Match 'Set Process environment variable WSLENV=USERPROFILE/up'
        $result.Output | Should -Match ([regex]::Escape("Set Process environment variable CONDA_PATH=$condaDir"))
        Test-Path -LiteralPath $environmentRecord | Should -Be $true
        $recorded = Get-Content -LiteralPath $environmentRecord
        $recorded | Should -Contain 'UV_SYSTEM_CERTS'
        $recorded | Should -Contain 'BAT_CONFIG_PATH'
        $recorded | Should -Contain 'WSLENV'
        $recorded | Should -Contain 'CONDA_PATH'
    }

    It 'respects an existing valid CONDA_PATH without managing it' {
        $env:CONDA_PATH = $condaDir

        $result = Invoke-Installer

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Not -Match 'environment variable CONDA_PATH'
        if (Test-Path -LiteralPath $environmentRecord) {
            (Get-Content -LiteralPath $environmentRecord) | Should -Not -Contain 'CONDA_PATH'
        }

        $uninstall = Invoke-Installer -Arguments @('-Uninstall')
        $uninstall.Output | Should -Not -Match 'Cleared Process environment variable CONDA_PATH'
    }

    It 'reports conda as advisory during a check' {
        Invoke-Installer | Out-Null

        $result = Invoke-Installer -Arguments @('-Check')

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'conda:'
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
        Test-Path -LiteralPath (Join-Path $stateDir 'clink.json') | Should -Be $false

        $clinkState = Get-FakeClinkState
        @($clinkState.scriptPaths).Count | Should -Be 0
        $settingNames = @($clinkState.settings.PSObject.Properties.Name)
        $settingNames | Should -Not -Contain 'clink.autostart'
        $settingNames | Should -Not -Contain 'ohmyposh.theme'
        $settingNames | Should -Not -Contain 'clink.customprompt'
    }

    It 'changes nothing during a dry run' {
        Set-Content -LiteralPath $profilePath -Value @('# user profile')
        $before = (Get-FileHash -LiteralPath $profilePath).Hash

        $result = Invoke-Installer -Arguments @('-DryRun')

        $result.ExitCode | Should -Be 0
        (Get-FileHash -LiteralPath $profilePath).Hash | Should -Be $before
        Test-Path -LiteralPath $espansoRoot | Should -Be $false
        Test-Path -LiteralPath $environmentRecord | Should -Be $false
        Test-Path -LiteralPath $script:fakeClinkLog | Should -Be $false
        Test-Path -LiteralPath (Join-Path $stateDir 'clink.json') | Should -Be $false
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

    It 'flags another profile that also sources the entry point' {
        $hostProfile = Join-Path $testRoot 'Microsoft.PowerShell_profile.ps1'
        Set-Content -LiteralPath (Join-Path $testRoot 'profile.ps1') -Value ". '$entryScript'"

        $result = Invoke-Installer -ProfilePath $hostProfile

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'also sources CustomShell'
        Test-Path -LiteralPath $hostProfile | Should -Be $true

        $check = Invoke-Installer -ProfilePath $hostProfile -Arguments @('-Check')

        $check.ExitCode | Should -Be 1
        $check.Output | Should -Match 'also sourced by'
    }

    It 'registers Clink scripts and selects the oh-my-posh prompt in order' {
        $result = Invoke-Installer

        $result.ExitCode | Should -Be 0
        $calls = Get-FakeClinkCalls

        $installIndex = -1
        $promptIndex = -1
        $themeIndex = -1
        $autostartIndex = -1
        for ($i = 0; $i -lt $calls.Count; $i++) {
            $line = $calls[$i]
            if ($line -like 'installscripts *' -and $line -notlike '*--list*') { $installIndex = $i }
            elseif ($line -eq 'config prompt use oh-my-posh') { $promptIndex = $i }
            elseif ($line -like 'set ohmyposh.theme *') { $themeIndex = $i }
            elseif ($line -like 'set clink.autostart *') { $autostartIndex = $i }
        }

        $installIndex | Should -BeGreaterOrEqual 0
        $promptIndex | Should -BeGreaterOrEqual 0
        $themeIndex | Should -BeGreaterOrEqual 0
        $autostartIndex | Should -BeGreaterOrEqual 0
        $promptIndex | Should -BeLessThan $themeIndex
    }

    It 'mirrors the starship prompt and manages STARSHIP_CONFIG' {
        $settings = New-TestSettings -Prompt 'starship'

        $result = Invoke-Installer -SettingsPath $settings

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'Set Process environment variable STARSHIP_CONFIG='
        $result.Output | Should -Match ([regex]::Escape((Join-Path $repoDir 'config\starship\catppuccin-powerline.toml')))

        $calls = Get-FakeClinkCalls
        $calls | Should -Contain 'config prompt use starship'
        @($calls | Where-Object { $_ -like 'set ohmyposh.theme *' }).Count | Should -Be 0

        $clinkState = Get-FakeClinkState
        @($clinkState.settings.PSObject.Properties.Name) | Should -Not -Contain 'ohmyposh.theme'
        (Get-Content -LiteralPath $environmentRecord) | Should -Contain 'STARSHIP_CONFIG'
    }

    It 'selects no Clink prompt when the CustomShell prompt is none' {
        $settings = New-TestSettings -Prompt 'none'

        $result = Invoke-Installer -SettingsPath $settings

        $result.ExitCode | Should -Be 0
        $calls = Get-FakeClinkCalls
        @($calls | Where-Object { $_ -like 'config prompt use*' }).Count | Should -Be 0
        @($calls | Where-Object { $_ -like 'set ohmyposh.theme *' }).Count | Should -Be 0
        @($calls | Where-Object { $_ -like 'installscripts *' -and $_ -notlike '*--list*' }).Count | Should -Be 1
        $result.Output | Should -Not -Match 'STARSHIP_CONFIG'
    }

    It 'reverts a managed omp theme when switching to the starship prompt' {
        Invoke-Installer | Out-Null

        $settings = New-TestSettings -Prompt 'starship'
        $result = Invoke-Installer -SettingsPath $settings

        $result.ExitCode | Should -Be 0
        $clinkState = Get-FakeClinkState
        @($clinkState.settings.PSObject.Properties.Name) | Should -Not -Contain 'ohmyposh.theme'

        $state = Get-Content -LiteralPath (Join-Path $stateDir 'clink.json') -Raw | ConvertFrom-Json
        @($state.settings.name) | Should -Not -Contain 'ohmyposh.theme'
    }

    It 'reports stale Clink configuration during a check' {
        Invoke-Installer | Out-Null

        $fake = Get-Content -LiteralPath $script:fakeClinkState -Raw | ConvertFrom-Json
        $fake.settings.'clink.autostart' = 'wrong'
        $fake | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:fakeClinkState

        $result = Invoke-Installer -Arguments @('-Check')

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'clink:.*stale'
    }

    It 'treats Clink as optional when the command is unavailable' {
        $missing = Join-Path $testRoot 'missing-clink.ps1'

        $result = Invoke-Installer -ClinkCommand $missing

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'Clink not found'
        Test-Path -LiteralPath (Join-Path $stateDir 'clink.json') | Should -Be $false

        $check = Invoke-Installer -ClinkCommand $missing -Arguments @('-Check')
        $check.ExitCode | Should -Be 0
        $check.Output | Should -Match 'clink:.*not found'
    }

    It 'restores previous Clink settings on uninstall' {
        @{
            settings    = @{
                'clink.customprompt' = 'C:\fake\themes\pure.clinkprompt'
                'ohmyposh.theme'     = 'previous-theme'
                'clink.autostart'    = 'previous-autostart'
            }
            scriptPaths = @()
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:fakeClinkState

        Invoke-Installer | Out-Null
        $result = Invoke-Installer -Arguments @('-Uninstall')

        $result.ExitCode | Should -Be 0
        $clinkState = Get-FakeClinkState
        $clinkState.settings.'clink.customprompt' | Should -Be 'C:\fake\themes\pure.clinkprompt'
        $clinkState.settings.'ohmyposh.theme' | Should -Be 'previous-theme'
        $clinkState.settings.'clink.autostart' | Should -Be 'previous-autostart'
    }

    It 'keeps a Clink setting modified after install on uninstall' {
        Invoke-Installer | Out-Null

        $fake = Get-Content -LiteralPath $script:fakeClinkState -Raw | ConvertFrom-Json
        $fake.settings.'clink.autostart' = 'user-change'
        $fake | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:fakeClinkState

        $result = Invoke-Installer -Arguments @('-Uninstall')

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'Keeping modified Clink setting clink.autostart'
        $clinkState = Get-FakeClinkState
        $clinkState.settings.'clink.autostart' | Should -Be 'user-change'

        $state = Get-Content -LiteralPath (Join-Path $stateDir 'clink.json') -Raw | ConvertFrom-Json
        @($state.settings.name) | Should -Contain 'clink.autostart'
    }

    It 'leaves Clink state unchanged across repeated runs' {
        Invoke-Installer | Out-Null
        Remove-Item -LiteralPath $script:fakeClinkLog -Force

        $result = Invoke-Installer

        $result.ExitCode | Should -Be 0
        $calls = Get-FakeClinkCalls
        @($calls | Where-Object { $_ -like 'config prompt use*' }).Count | Should -Be 0
        @($calls | Where-Object { $_ -like '*catppuccin_gruvbox.json*' }).Count | Should -Be 0
        @($calls | Where-Object { $_ -like 'installscripts *' -and $_ -notlike '*--list*' }).Count | Should -Be 0
    }
}
