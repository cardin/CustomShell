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
Get-Command Protect-Tar -ErrorAction Stop | Out-Null
Get-Command Unprotect-Tar -ErrorAction Stop | Out-Null
Get-Command Show-Help -ErrorAction Stop | Out-Null
'PROFILE_OK'
"@

        $powerShellPath = (Get-Process -Id $PID).Path
        $output = & $powerShellPath -NoLogo -NoProfile -Command $command 2>&1

        $LASTEXITCODE | Should Be 0
        @($output)[-1] | Should Be 'PROFILE_OK'
    }

    It 'keeps the zoxide hook active after prompt initialization' {
        @'
@{
    StartTimeoutSeconds = 60
    Prompt = 'ohmyposh'
    RequiredCommands = @()
}
'@ | Set-Content -LiteralPath $settingsPath

        $mainPath = Join-Path $PSScriptRoot '..\..\main.ps1'
        $escapedMainPath = $mainPath.Replace("'", "''")
        $escapedSettingsPath = $settingsPath.Replace("'", "''")
        $command = @"
`$ErrorActionPreference = 'Stop'
function global:oh-my-posh {
    `$global:LASTEXITCODE = 0
    "function global:prompt { 'PROMPT_ENGINE' }"
}
function global:zoxide {
    `$global:LASTEXITCODE = 0
    @'
function global:__zoxide_hook { 'ZOXIDE_HOOK' }
`$global:__zoxide_hooked = Get-Variable __zoxide_hooked -Scope Global -ErrorAction SilentlyContinue -ValueOnly
if (`$global:__zoxide_hooked -ne 1) {
    `$global:__zoxide_hooked = 1
    `$global:__zoxide_prompt_old = `$function:prompt
    function global:prompt {
        & `$global:__zoxide_prompt_old
        __zoxide_hook
    }
}
'@
}
. '$escapedMainPath' -SettingsPath '$escapedSettingsPath'
. '$escapedMainPath' -SettingsPath '$escapedSettingsPath'
`$promptOutput = @(& prompt)
if (`$promptOutput -notcontains 'PROMPT_ENGINE') {
    throw 'The selected prompt engine is not active.'
}
if (`$promptOutput -notcontains 'ZOXIDE_HOOK') {
    throw 'The zoxide prompt hook was replaced.'
}
'ZOXIDE_PROMPT_OK'
"@

        $powerShellPath = (Get-Process -Id $PID).Path
        $output = & $powerShellPath -NoLogo -NoProfile -Command $command 2>&1

        $LASTEXITCODE | Should Be 0
        @($output)[-1] | Should Be 'ZOXIDE_PROMPT_OK'
    }
}
