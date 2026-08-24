# Verifies structured SSH configuration parsing through the public commands
# module. Tests use temporary configuration files to cover multi-alias host
# blocks, wildcard filtering, parsed fields, and missing-file behavior.
$modulePath = Join-Path $PSScriptRoot '..\..\Modules\CustomShell.Commands\CustomShell.Commands.psd1'

Describe 'Get-SSHConfig' {
    BeforeAll {
        Import-Module -Name $modulePath -Force
    }

    BeforeEach {
        $script:testRoot = Join-Path ([IO.Path]::GetTempPath()) "CustomShell.Tests-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $testRoot | Out-Null
        $script:configPath = Join-Path $testRoot 'config'
    }

    AfterEach {
        $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
        $resolvedTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if ($resolvedTestRoot.StartsWith($resolvedTempRoot, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'applies a Host block to every alias declared on the Host line' {
        @'
Host alpha beta
    HostName example.test
    User deploy
    Port 2222
Host *
    User fallback
'@ | Set-Content -LiteralPath $configPath

        $result = @(Get-SSHConfig -ConfigPath $configPath)

        $result.Count | Should Be 2
        $result[0].Alias | Should Be 'alpha'
        $result[1].Alias | Should Be 'beta'
        foreach ($entry in $result) {
            $entry.HostName | Should Be 'example.test'
            $entry.User | Should Be 'deploy'
            $entry.Port | Should Be 2222
        }
    }

    It 'returns no entries when the SSH config is missing' {
        $result = @(Get-SSHConfig -ConfigPath $configPath 3>$null)

        $result.Count | Should Be 0
    }
}
