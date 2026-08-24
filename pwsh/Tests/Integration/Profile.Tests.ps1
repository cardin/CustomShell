# Exercises the complete PowerShell profile bootstrap in an isolated child
# process. It verifies that repeated sourcing remains error-free and that the
# reusable commands module is available afterward.

Describe 'PowerShell profile startup' {
    BeforeEach {
        $script:testRoot = Join-Path ([IO.Path]::GetTempPath()) "CustomShell.Tests-$([guid]::NewGuid())"
        $script:settingsPath = Join-Path $testRoot 'Settings.psd1'
        $script:originalPathExt = $env:PATHEXT
        $env:PATHEXT = '.COM;.EXE;.BAT;.CMD'
        New-Item -ItemType Directory -Path $testRoot | Out-Null
        @'
@{
    StartTimeoutSeconds = 60
    Prompt = 'none'
    RequiredCommands = @()
}
'@ | Set-Content -LiteralPath $settingsPath
    }

    AfterEach {
        $env:PATHEXT = $originalPathExt
        $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
        $resolvedTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if ($resolvedTestRoot.StartsWith($resolvedTempRoot, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'loads twice without errors and exports module commands' {
        $mainPath = Join-Path $PSScriptRoot '..\..\main.ps1'
        $escapedMainPath = $mainPath.Replace("'", "''")
        $escapedSettingsPath = $settingsPath.Replace("'", "''")
        $command = @"
`$ErrorActionPreference = 'Stop'
. '$escapedMainPath' -SettingsPath '$escapedSettingsPath'
. '$escapedMainPath' -SettingsPath '$escapedSettingsPath'
Get-Command Encode-Tar -ErrorAction Stop | Out-Null
'PROFILE_OK'
"@

        $powerShellPath = (Get-Process -Id $PID).Path
        $output = & $powerShellPath -NoLogo -NoProfile -Command $command 2>&1

        $LASTEXITCODE | Should Be 0
        @($output)[-1] | Should Be 'PROFILE_OK'
    }
}
