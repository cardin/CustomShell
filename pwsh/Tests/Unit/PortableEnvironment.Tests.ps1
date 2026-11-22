# Tests fill-only Windows defaults without writing to the registry.
Describe 'Portable Windows environment defaults' {
    BeforeAll {
        foreach ($module in 'Profile', 'Environment', 'Configs', 'Clink', 'Checks') {
            . (Join-Path $PSScriptRoot "../../Install/$module.ps1")
        }
    }

    BeforeEach {
        $StateDir = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $configDir = $TestDrive
        $settings = @{ Prompt = 'none'; RequiredCommands = @() }
        $DryRun = $false
        Mock Test-CondaPathConfigured { $true }
        Mock Get-WslProjectsPath { '\\wsl.localhost\TestDistro\home\tester\projects_l' }
    }

    Context 'Process scope' {
        It 'fills the Windows defaults, keeps them across a rerun, and removes owned values' {
            $EnvironmentScope = 'Process'
            $original = @{}
            $names = 'TMPDIR', 'USER', 'HOME', 'PROJECTS_W', 'PROJECTS_L', 'TMP', 'TEMP', 'USERPROFILE', 'UV_SYSTEM_CERTS', 'BAT_CONFIG_PATH', 'WSLENV'
            foreach ($name in $names) {
                $original[$name] = [Environment]::GetEnvironmentVariable($name)
            }

            try {
                foreach ($name in 'TMPDIR', 'USER', 'HOME', 'PROJECTS_W', 'PROJECTS_L') {
                    [Environment]::SetEnvironmentVariable($name, $null)
                }
                $tempPath = Join-Path $TestDrive 'Windows temp'
                $profilePath = Join-Path $TestDrive 'Windows profile'
                New-Item -ItemType Directory -Path $tempPath | Out-Null
                $env:TMP = $env:TEMP = $tempPath
                $env:USERPROFILE = $profilePath
                $userName = [Environment]::UserName

                Install-PersistentEnvironment

                [IO.Path]::TrimEndingDirectorySeparator($env:TMPDIR) | Should -BeExactly $tempPath
                $env:USER | Should -BeExactly $userName
                $env:HOME | Should -BeExactly $profilePath
                $env:PROJECTS_W | Should -BeExactly (Join-Path $profilePath 'projects_w')
                $env:PROJECTS_L | Should -BeExactly '\\wsl.localhost\TestDistro\home\tester\projects_l'
                $env:TMP | Should -BeExactly $tempPath
                $env:TEMP | Should -BeExactly $tempPath
                $env:USERPROFILE | Should -BeExactly $profilePath

                $env:USERPROFILE = Join-Path $TestDrive 'New profile location'
                Install-PersistentEnvironment
                $env:HOME | Should -BeExactly $profilePath
                $env:PROJECTS_W | Should -BeExactly (Join-Path $profilePath 'projects_w')
                $entries = @(Get-ManagedEnvironmentState)
                ($entries | Where-Object name -eq 'HOME').desired | Should -BeExactly $profilePath

                Uninstall-PersistentEnvironment
                foreach ($name in 'TMPDIR', 'USER', 'HOME', 'PROJECTS_W', 'PROJECTS_L') {
                    [Environment]::GetEnvironmentVariable($name) | Should -BeNullOrEmpty
                }
            }
            finally {
                foreach ($name in $names) {
                    [Environment]::SetEnvironmentVariable($name, $original[$name])
                }
            }
        }
    }

    Context 'User scope (mocked)' {
        BeforeEach {
            $EnvironmentScope = 'User'
            $script:fakeValues = @{ User = @{}; Machine = @{}; Process = @{} }
            Mock Get-ScopedEnvironmentValue { $script:fakeValues[$Scope][$Name] }
            Mock Set-ScopedEnvironmentValue {
                if ($Scope -ne 'User') { throw "Unexpected environment write to $Scope" }
                $script:fakeValues[$Scope][$Name] = $Value
            }
            Mock Test-ProfileHasBlock { $false }
            Mock Test-ProfileHasUnmarkedSource { $true }
            Mock Get-ConflictingProfilePaths {}
            Mock Get-ExpectedConfigEntries {}
            Mock Invoke-ClinkCheck { 0 }
        }

        It 'leaves preexisting values unowned in all scopes, even when one matches the default' {
            $portableNames = Get-PortableEnvironmentNames
            $defaultTempDir = Get-PortableEnvironmentDefault TMPDIR
            $script:fakeValues.User.TMPDIR = $defaultTempDir
            $script:fakeValues.Machine.USER = 'machine-account'
            $script:fakeValues.Process.HOME = 'C:\Process profile'
            $script:fakeValues.User.PROJECTS_W = 'D:\Preexisting projects'
            $script:fakeValues.Machine.PROJECTS_L = '\\server\share\projects_l'
            $Force = $true

            $output = Install-PersistentEnvironment 6>&1

            ($output -join "`n") | Should -Match 'Keeping Process environment variable HOME \(not persistent\)'
            Should -Invoke Set-ScopedEnvironmentValue -Times 0 -Exactly -ParameterFilter {
                $Name -in 'TMPDIR', 'USER', 'HOME', 'PROJECTS_W', 'PROJECTS_L'
            }
            @(Get-ManagedEnvironmentState | Where-Object name -in $portableNames) | Should -BeNullOrEmpty

            $check = @(Invoke-Checks 6>&1)
            $check[-1] | Should -Be 1
            ($check -join "`n") | Should -Match 'HOME=Process only \(not persistent\)'
            ($check -join "`n") | Should -Match 'USER=machine-account \(Machine\)'

            $script:fakeValues.Process.HOME = $null
            $check = @(Invoke-Checks 6>&1)
            $check[-1] | Should -Be 1
            ($check -join "`n") | Should -Match 'HOME=unset - run Install.ps1'

            $script:fakeValues.User.HOME = 'C:\User-selected home'
            $check = @(Invoke-Checks 6>&1)
            $check[-1] | Should -Be 0

            Uninstall-PersistentEnvironment
            $script:fakeValues.User.TMPDIR | Should -BeExactly $defaultTempDir
            $script:fakeValues.User.HOME | Should -BeExactly 'C:\User-selected home'
            $script:fakeValues.User.PROJECTS_W | Should -BeExactly 'D:\Preexisting projects'
            $script:fakeValues.Machine.PROJECTS_L | Should -BeExactly '\\server\share\projects_l'
        }

        It 'writes missing or empty defaults to User scope and drops ownership of an edit on rerun' {
            $script:fakeValues.User.USER = ''
            Install-PersistentEnvironment
            foreach ($name in (Get-PortableEnvironmentNames)) {
                $script:fakeValues.User[$name] | Should -BeExactly (Get-PortableEnvironmentDefault $name)
            }
            $script:fakeValues.User.HOME = 'C:\Local home'

            Install-PersistentEnvironment
            @(Get-ManagedEnvironmentState).name | Should -Not -Contain 'HOME'
            $script:fakeValues.User.HOME | Should -BeExactly 'C:\Local home'

            # A case-only edit is also preserved even without an install rerun.
            $defaultTempDir = Get-PortableEnvironmentDefault TMPDIR
            $editedTempDir = $defaultTempDir.ToUpperInvariant()
            if ($editedTempDir -ceq $defaultTempDir) {
                $editedTempDir = $defaultTempDir.ToLowerInvariant()
            }
            $editedTempDir | Should -Not -BeExactly $defaultTempDir
            $script:fakeValues.User.TMPDIR = $editedTempDir
            Uninstall-PersistentEnvironment
            $script:fakeValues.User.HOME | Should -BeExactly 'C:\Local home'
            $script:fakeValues.User.TMPDIR | Should -BeExactly $editedTempDir
            $script:fakeValues.User.USER | Should -BeNullOrEmpty
        }

        It 'reports proposed writes during a dry run without writing values or state' {
            $DryRun = $true
            $script:fakeValues.Machine.USER = 'machine-account'

            $output = (Install-PersistentEnvironment 6>&1) -join "`n"

            $output | Should -Match 'Would set User environment variable TMPDIR='
            $output | Should -Match 'Would set User environment variable HOME='
            $output | Should -Match ([regex]::Escape((Join-Path $env:USERPROFILE 'projects_w')))
            $output | Should -Not -Match 'Would set User environment variable USER='
            Should -Invoke Set-ScopedEnvironmentValue -Times 0 -Exactly
            Test-Path -LiteralPath $StateDir | Should -BeFalse
        }
    }
}
