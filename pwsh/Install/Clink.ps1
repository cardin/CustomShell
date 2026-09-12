# Clink configuration. This file only defines functions and is dot-sourced by
# pwsh/Install.ps1. The functions read the setup-scope variables ($repoDir,
# $configDir, $settings, $StateDir, $DryRun, $ClinkCommand) established by the
# entry point. All changes go through the Clink command line so Clink itself
# owns its settings file and registry; nothing here edits them directly.

# Get-ClinkCommand
# Resolves the Clink command. A provided -ClinkCommand override is used as-is
# and does not fall back to PATH discovery, so tests can simulate Clink being
# absent. Otherwise the command is looked up on PATH.
function Get-ClinkCommand {
    if ($ClinkCommand) {
        if (Test-Path -LiteralPath $ClinkCommand -PathType Leaf) {
            return (Resolve-Path -LiteralPath $ClinkCommand).Path
        }
        $command = Get-Command $ClinkCommand -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($command) {
            return $command.Source
        }
        return $null
    }

    $command = Get-Command clink -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) {
        return $command.Source
    }
    return $null
}

# Get-ClinkScriptsPath
# Returns the repository directory registered as a Clink script path.
function Get-ClinkScriptsPath {
    return Join-Path $configDir 'clink'
}

# Get-ClinkAutostartPath
# Returns the clink.autostart value. Clink executes the value as a typed command
# line, so a path containing spaces is wrapped in double quotes.
function Get-ClinkAutostartPath {
    $path = Join-Path $configDir 'clink/clink_start.cmd'
    if ($path -match '\s') {
        return '"' + $path + '"'
    }
    return $path
}

# Get-ClinkPromptPlan
# Maps the selected CustomShell prompt onto a Clink custom prompt. Clink only
# ever runs inside cmd.exe, which the profile treats as a standalone terminal,
# so the standalone (glyph) themes apply. Returns $null Name when no custom
# prompt should be selected.
function Get-ClinkPromptPlan {
    switch ($settings.Prompt) {
        'ohmyposh' {
            return [pscustomobject]@{
                Name         = 'oh-my-posh'
                Command      = 'oh-my-posh'
                ThemeSetting = 'ohmyposh.theme'
                ThemePath    = (Join-Path $configDir 'omp/catppuccin_gruvbox.json')
            }
        }
        'starship' {
            return [pscustomobject]@{
                Name         = 'starship'
                Command      = 'starship'
                ThemeSetting = $null
                ThemePath    = $null
            }
        }
        'none' {
            return [pscustomobject]@{
                Name         = $null
                Command      = $null
                ThemeSetting = $null
                ThemePath    = $null
            }
        }
        default {
            Write-Warning "Unknown CustomShell prompt selection: $($settings.Prompt)"
            return [pscustomobject]@{
                Name         = $null
                Command      = $null
                ThemeSetting = $null
                ThemePath    = $null
            }
        }
    }
}

# Get-ClinkDesiredSettings
# Returns the Clink settings CustomShell manages for the selected prompt.
function Get-ClinkDesiredSettings {
    $desired = [ordered]@{
        'clink.autostart' = Get-ClinkAutostartPath
    }
    $plan = Get-ClinkPromptPlan
    if ($plan.ThemeSetting) {
        $desired[$plan.ThemeSetting] = $plan.ThemePath
    }
    return $desired
}

# Get-ClinkSettingValue
# Reads a setting's current value via `clink set <name>`. Returns $null when the
# setting is unknown, unset, or Clink reports an error.
function Get-ClinkSettingValue {
    param(
        [Parameter(Mandatory)]
        [string] $Clink,
        [Parameter(Mandatory)]
        [string] $Name
    )

    $output = & $Clink set $Name 2>&1
    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    $text = (@($output) | ForEach-Object { $_.ToString() }) -join "`n"
    $match = [regex]::Match($text, '(?m)^[ \t]*Value:[ \t]*(.*?)[ \t]*$')
    if (-not $match.Success) {
        return $null
    }

    $value = $match.Groups[1].Value
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $null
    }
    return $value
}

# Set-ClinkSettingValue
# Writes a setting via `clink set <name> <value>`.
function Set-ClinkSettingValue {
    param(
        [Parameter(Mandatory)]
        [string] $Clink,
        [Parameter(Mandatory)]
        [string] $Name,
        [Parameter(Mandatory)]
        [string] $Value
    )

    $output = & $Clink set $Name $Value 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = (@($output) | Select-Object -Last 1).ToString()
        Write-Warning "Clink failed to set ${Name}: $message"
        return $false
    }
    return $true
}

# Clear-ClinkSettingValue
# Resets a setting to its default via `clink set <name> clear`.
function Clear-ClinkSettingValue {
    param(
        [Parameter(Mandatory)]
        [string] $Clink,
        [Parameter(Mandatory)]
        [string] $Name
    )

    $output = & $Clink set $Name clear 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = (@($output) | Select-Object -Last 1).ToString()
        Write-Warning "Clink failed to clear ${Name}: $message"
        return $false
    }
    return $true
}

# Get-ClinkInstalledScriptPaths
# Lists the script paths registered with `clink installscripts`.
function Get-ClinkInstalledScriptPaths {
    param(
        [Parameter(Mandatory)]
        [string] $Clink
    )

    $output = & $Clink installscripts --list 2>&1
    if ($LASTEXITCODE -ne 0) {
        return @()
    }
    return @($output | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ })
}

# Test-ClinkScriptPathRegistered
# Returns true when the given directory is registered as a Clink script path.
function Test-ClinkScriptPathRegistered {
    param(
        [Parameter(Mandatory)]
        [string] $Clink,
        [Parameter(Mandatory)]
        [string] $Path
    )

    $normalized = $Path.TrimEnd('\')
    foreach ($installed in (Get-ClinkInstalledScriptPaths -Clink $Clink)) {
        if ($installed.TrimEnd('\') -ieq $normalized) {
            return $true
        }
    }
    return $false
}

# Register-ClinkScriptPath
# Registers a script path with `clink installscripts`.
function Register-ClinkScriptPath {
    param(
        [Parameter(Mandatory)]
        [string] $Clink,
        [Parameter(Mandatory)]
        [string] $Path
    )

    $output = & $Clink installscripts $Path 2>&1
    $text = (@($output) | ForEach-Object { $_.ToString() }) -join ' '
    if ($text -match 'already installed') {
        return
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Clink failed to register script path ${Path}: $text"
        return
    }
    Write-Host "Registered Clink script path $Path"
}

# Unregister-ClinkScriptPath
# Removes a script path with `clink uninstallscripts`.
function Unregister-ClinkScriptPath {
    param(
        [Parameter(Mandatory)]
        [string] $Clink,
        [Parameter(Mandatory)]
        [string] $Path
    )

    $output = & $Clink uninstallscripts $Path 2>&1
    $text = (@($output) | ForEach-Object { $_.ToString() }) -join ' '
    if ($text -match 'not installed') {
        return
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Clink failed to unregister script path ${Path}: $text"
        return
    }
    Write-Host "Unregistered Clink script path $Path"
}

# Get-ClinkStatePath
# Returns the file that records the Clink script path and managed settings.
function Get-ClinkStatePath {
    return Join-Path $StateDir 'clink.json'
}

# Get-ClinkState
# Reads the recorded Clink state, tolerating a missing or unreadable file.
function Get-ClinkState {
    $scriptsPath = $null
    $settingsList = [System.Collections.Generic.List[object]]::new()

    $path = Get-ClinkStatePath
    if (Test-Path -LiteralPath $path) {
        try {
            $state = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            if ($state.PSObject.Properties['scriptsPath']) {
                $scriptsPath = $state.scriptsPath
            }
            if ($state.PSObject.Properties['settings'] -and $state.settings) {
                foreach ($entry in @($state.settings)) {
                    if ($entry.name) {
                        $settingsList.Add([pscustomobject]@{
                                name     = $entry.name
                                desired  = $entry.desired
                                previous = $entry.previous
                            })
                    }
                }
            }
        }
        catch {
            Write-Warning "Ignoring unreadable Clink state file: $path"
        }
    }

    return [pscustomobject]@{
        scriptsPath = $scriptsPath
        settings    = $settingsList
    }
}

# Save-ClinkState
# Persists the Clink state, or removes it when nothing remains managed.
function Save-ClinkState {
    param(
        [Parameter(Mandatory)]
        $State
    )

    if ($DryRun) {
        return
    }

    $path = Get-ClinkStatePath
    if (-not $State.scriptsPath -and $State.settings.Count -eq 0) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force
        }
        return
    }

    if (-not (Test-Path -LiteralPath $StateDir)) {
        New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
    }
    $State | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path
}

# Get-ClinkSettingEntry
# Returns the recorded entry for a setting name, or $null.
function Get-ClinkSettingEntry {
    param(
        $State,
        [Parameter(Mandatory)]
        [string] $Name
    )

    foreach ($entry in $State.settings) {
        if ($entry.name -ieq $Name) {
            return $entry
        }
    }
    return $null
}

# Set-ClinkStateSetting
# Records or updates a managed setting, preserving the first previous value.
function Set-ClinkStateSetting {
    param(
        $State,
        [Parameter(Mandatory)]
        [string] $Name,
        [string] $Desired,
        [string] $Previous
    )

    $entry = Get-ClinkSettingEntry -State $State -Name $Name
    if ($entry) {
        $entry.desired = $Desired
        return
    }
    $State.settings.Add([pscustomobject]@{
            name     = $Name
            desired  = $Desired
            previous = $Previous
        })
}

# Set-ClinkManagedSetting
# Sets a single setting when it differs from the desired value.
function Set-ClinkManagedSetting {
    param(
        [Parameter(Mandatory)]
        [string] $Clink,
        $State,
        [Parameter(Mandatory)]
        [string] $Name,
        [Parameter(Mandatory)]
        [string] $Desired
    )

    $current = Get-ClinkSettingValue -Clink $Clink -Name $Name
    if ($current -ieq $Desired) {
        return
    }

    if (Set-ClinkSettingValue -Clink $Clink -Name $Name -Value $Desired) {
        Write-Host "Set Clink setting ${Name}=$Desired"
        $entry = Get-ClinkSettingEntry -State $State -Name $Name
        $previous = if ($entry) { $entry.previous } else { $current }
        Set-ClinkStateSetting -State $State -Name $Name -Desired $Desired -Previous $previous
    }
}

# Set-ClinkManagedPrompt
# Selects the CustomShell prompt in Clink via `clink config prompt use`.
function Set-ClinkManagedPrompt {
    param(
        [Parameter(Mandatory)]
        [string] $Clink,
        $State,
        [Parameter(Mandatory)]
        $Plan
    )

    if (-not $Plan.Name) {
        return
    }

    if (-not (Get-Command $Plan.Command -ErrorAction SilentlyContinue)) {
        Write-Warning "Clink prompt '$($Plan.Name)' was selected but '$($Plan.Command)' was not found; skipping."
        return
    }

    $current = Get-ClinkSettingValue -Clink $Clink -Name 'clink.customprompt'
    if ($current -and (Split-Path -Leaf $current) -ieq "$($Plan.Name).clinkprompt") {
        return
    }

    $output = & $Clink config prompt use $Plan.Name 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = (@($output) | Select-Object -Last 1).ToString()
        Write-Warning "Clink failed to select prompt '$($Plan.Name)': $message"
        return
    }
    Write-Host "Selected Clink prompt $($Plan.Name)"

    $desired = Get-ClinkSettingValue -Clink $Clink -Name 'clink.customprompt'
    if ($desired) {
        $entry = Get-ClinkSettingEntry -State $State -Name 'clink.customprompt'
        $previous = if ($entry) { $entry.previous } else { $current }
        Set-ClinkStateSetting -State $State -Name 'clink.customprompt' -Desired $desired -Previous $previous
    }
}

# Restore-ClinkSetting
# Restores one recorded setting to its previous value, or clears it. Returns
# true when the record can be dropped.
function Restore-ClinkSetting {
    param(
        [Parameter(Mandatory)]
        [string] $Clink,
        $Entry
    )

    $current = Get-ClinkSettingValue -Clink $Clink -Name $Entry.name
    if ($null -eq $current -or $current -ine $Entry.desired) {
        $shown = if ($null -eq $current) { 'unset' } else { $current }
        Write-Warning "Keeping modified Clink setting $($Entry.name): '$shown'."
        return $false
    }

    if ($Entry.previous) {
        if (Set-ClinkSettingValue -Clink $Clink -Name $Entry.name -Value $Entry.previous) {
            Write-Host "Restored Clink setting $($Entry.name)=$($Entry.previous)"
        }
    }
    elseif (Clear-ClinkSettingValue -Clink $Clink -Name $Entry.name) {
        Write-Host "Cleared Clink setting $($Entry.name)"
    }
    return $true
}

# Remove-ClinkUndesiredSettings
# Reverts and drops records that are no longer managed for the current prompt.
function Remove-ClinkUndesiredSettings {
    param(
        [Parameter(Mandatory)]
        [string] $Clink,
        $State,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $DesiredNames
    )

    $remaining = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $State.settings) {
        if ($DesiredNames -contains $entry.name) {
            $remaining.Add($entry)
            continue
        }

        if (Restore-ClinkSetting -Clink $Clink -Entry $entry) {
            continue
        }
        $remaining.Add($entry)
    }
    $State.settings = $remaining
}

# Install-Clink
# Registers the repository script path and applies the managed Clink settings.
function Install-Clink {
    $clink = Get-ClinkCommand
    if (-not $clink) {
        Write-Warning 'Clink not found; skipping Clink configuration (optional).'
        return
    }

    $plan = Get-ClinkPromptPlan
    $scriptsPath = Get-ClinkScriptsPath
    $desired = Get-ClinkDesiredSettings
    $desiredNames = @($desired.Keys)
    if ($plan.Name) {
        $desiredNames += 'clink.customprompt'
    }

    $autostartSource = Join-Path $configDir 'clink/clink_start.cmd'
    if (-not (Test-Path -LiteralPath $autostartSource -PathType Leaf)) {
        Write-Warning "Missing Clink autostart source: $autostartSource"
    }
    if ($plan.ThemePath -and -not (Test-Path -LiteralPath $plan.ThemePath -PathType Leaf)) {
        Write-Warning "Missing Clink theme source: $($plan.ThemePath)"
    }

    $state = Get-ClinkState

    if ($DryRun) {
        Write-Host "Would register Clink script path $scriptsPath"
        if ($plan.Name) {
            Write-Host "Would select Clink prompt $($plan.Name)"
        }
        foreach ($name in $desired.Keys) {
            Write-Host "Would set Clink setting ${name}=$($desired[$name])"
        }
        foreach ($entry in $state.settings) {
            if ($desiredNames -notcontains $entry.name) {
                Write-Host "Would restore Clink setting $($entry.name)"
            }
        }
        return
    }

    if ($state.scriptsPath -and ($state.scriptsPath.TrimEnd('\') -ine $scriptsPath.TrimEnd('\'))) {
        if (Test-ClinkScriptPathRegistered -Clink $clink -Path $state.scriptsPath) {
            Unregister-ClinkScriptPath -Clink $clink -Path $state.scriptsPath
        }
    }
    if (-not (Test-ClinkScriptPathRegistered -Clink $clink -Path $scriptsPath)) {
        Register-ClinkScriptPath -Clink $clink -Path $scriptsPath
    }
    $state.scriptsPath = $scriptsPath

    Remove-ClinkUndesiredSettings -Clink $clink -State $state -DesiredNames $desiredNames
    Set-ClinkManagedPrompt -Clink $clink -State $state -Plan $plan
    foreach ($name in $desired.Keys) {
        Set-ClinkManagedSetting -Clink $clink -State $state -Name $name -Desired $desired[$name]
    }

    Save-ClinkState -State $state
}

# Uninstall-Clink
# Unregisters the recorded script path and restores managed settings that still
# match the values CustomShell set.
function Uninstall-Clink {
    $clink = Get-ClinkCommand
    if (-not $clink) {
        Write-Warning 'Clink not found; leaving Clink configuration in place (optional).'
        return
    }

    $state = Get-ClinkState

    if ($DryRun) {
        if ($state.scriptsPath) {
            Write-Host "Would unregister Clink script path $($state.scriptsPath)"
        }
        foreach ($entry in $state.settings) {
            Write-Host "Would restore Clink setting $($entry.name)"
        }
        return
    }

    if ($state.scriptsPath -and (Test-ClinkScriptPathRegistered -Clink $clink -Path $state.scriptsPath)) {
        Unregister-ClinkScriptPath -Clink $clink -Path $state.scriptsPath
    }

    $remaining = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $state.settings) {
        if (-not (Restore-ClinkSetting -Clink $clink -Entry $entry)) {
            $remaining.Add($entry)
        }
    }

    $state.scriptsPath = $null
    $state.settings = $remaining
    Save-ClinkState -State $state
}

# Invoke-ClinkCheck
# Reports the Clink setup state and returns the number of incomplete
# requirements. Clink is optional, so its absence is advisory.
function Invoke-ClinkCheck {
    $clink = Get-ClinkCommand
    if (-not $clink) {
        Write-Host '  clink:      not found (optional)'
        return 0
    }

    $problems = [System.Collections.Generic.List[string]]::new()
    if (-not (Test-ClinkScriptPathRegistered -Clink $clink -Path (Get-ClinkScriptsPath))) {
        $problems.Add('scripts path not registered')
    }

    $plan = Get-ClinkPromptPlan
    if ($plan.Name) {
        $prompt = Get-ClinkSettingValue -Clink $clink -Name 'clink.customprompt'
        if (-not $prompt -or
            (Split-Path -Leaf $prompt) -ine "$($plan.Name).clinkprompt" -or
            -not (Test-Path -LiteralPath $prompt -PathType Leaf)) {
            $problems.Add("prompt is not $($plan.Name)")
        }
    }

    if ((Get-ClinkSettingValue -Clink $clink -Name 'clink.autostart') -ine (Get-ClinkAutostartPath)) {
        $problems.Add('autostart')
    }

    if ($plan.ThemeSetting) {
        if ((Get-ClinkSettingValue -Clink $clink -Name $plan.ThemeSetting) -ine $plan.ThemePath) {
            $problems.Add('theme')
        }
    }

    if ($problems.Count -gt 0) {
        Write-Host "  clink:      stale - run Install.ps1 ($($problems -join ', '))"
        return 1
    }

    Write-Host '  clink:      configured'
    return 0
}
