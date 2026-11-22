# Persistent user environment values managed by CustomShell setup. The entry
# point's -EnvironmentScope selects the target scope; User is the real target
# and Process exists so tests never touch the registry. Managed values always
# win where required; portable defaults never replace nonempty values, and a
# user-provided valid CONDA_PATH is respected and left unmanaged.
# A managed value that is no longer desired is cleared, so switching the
# selected prompt away from starship removes STARSHIP_CONFIG. This file only
# defines functions and is dot-sourced by pwsh/Install.ps1. The functions read
# the setup-scope variables ($StateDir, $configDir, $settings, $DryRun,
# $EnvironmentScope).

# Get-PersistentEnvironment
# Returns the environment values CustomShell keeps set for the user. BAT_CONFIG_PATH
# points bat at the repository's shared configuration file so plain bat picks up
# the header/grid style without a shell alias. WSLENV shares USERPROFILE with WSL
# processes, translating the path and applying only in the Windows-to-WSL direction.
# STARSHIP_CONFIG points Starship at the repository's standalone theme when the
# starship prompt is selected; Clink inherits it to theme its starship prompt.
function Get-PersistentEnvironment {
    $values = [ordered]@{
        'UV_SYSTEM_CERTS' = 'true'
        'BAT_CONFIG_PATH' = (Join-Path $configDir 'bat.conf')
        'WSLENV'          = 'USERPROFILE/up'
    }

    if ($settings.Prompt -eq 'starship') {
        $values['STARSHIP_CONFIG'] = Join-Path $configDir 'starship/catppuccin-powerline.toml'
    }

    return $values
}

function Get-PortableEnvironmentNames {
    'TMPDIR', 'USER', 'HOME', 'PROJECTS_W', 'PROJECTS_L'
}

# Resolve the default WSL projects path as a Windows UNC path. The distribution
# and Linux user come from WSL itself, so no machine-specific name is stored.
function Get-WslProjectsPath {
    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if (-not $wsl) {
        return $null
    }
    $path = & $wsl.Source -e sh -c 'wslpath -w "$HOME/projects_l"' 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $path) {
        return $null
    }
    return ([string] $path).Trim()
}

# Resolve a default only when setup needs to fill a missing value.
function Get-PortableEnvironmentDefault($Name) {
    switch ($Name) {
        'TMPDIR' { [IO.Path]::GetTempPath() }
        'USER'   { [Environment]::UserName }
        'HOME'   { if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME } }
        'PROJECTS_W' {
            $profileDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
            Join-Path $profileDir 'projects_w'
        }
        'PROJECTS_L' { Get-WslProjectsPath }
    }
}

function Get-ScopedEnvironmentValue($Name, $Scope) {
    [Environment]::GetEnvironmentVariable($Name, $Scope)
}

function Set-ScopedEnvironmentValue($Name, $Value, $Scope) {
    [Environment]::SetEnvironmentVariable($Name, $Value, $Scope)
}

# Match Windows precedence for durable values. A process-only override still
# blocks a setup write, but is not considered persistent by -Check.
function Get-PortableEnvironmentValue($Name) {
    $scopes = if ($EnvironmentScope -eq 'User') { 'User', 'Machine', 'Process' } else { 'Process' }
    foreach ($scope in $scopes) {
        $value = Get-ScopedEnvironmentValue $Name $scope
        if (-not [string]::IsNullOrEmpty($value)) {
            return [pscustomobject]@{ Scope = $scope; Value = $value }
        }
    }
}

# Test-CondaPathConfigured
# Returns true when CONDA_PATH names an existing conda.exe. The value is the
# directory that directly contains conda.exe (typically <root>\Scripts), which
# is what pwsh/Startup/Initialize-Integrations.ps1 consumes.
function Test-CondaPathConfigured {
    return [bool] ($env:CONDA_PATH -and
        (Test-Path -LiteralPath (Join-Path $env:CONDA_PATH 'conda.exe') -PathType Leaf))
}

# Get-CondaPath
# Resolves the directory containing conda.exe: an existing valid CONDA_PATH is
# preferred, then conda.exe located on PATH. Returns $null when unavailable so
# the caller can skip registering it.
function Get-CondaPath {
    if (Test-CondaPathConfigured) {
        return $env:CONDA_PATH
    }

    $command = Get-Command conda.exe -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $command) {
        return $null
    }

    $directory = Split-Path -Parent $command.Source
    if (Test-Path -LiteralPath (Join-Path $directory 'conda.exe') -PathType Leaf) {
        return $directory
    }
    return $null
}

# Get-EnvironmentStatePath
# Returns the JSON file that records the environment values CustomShell set.
function Get-EnvironmentStatePath {
    return Join-Path $StateDir 'environment.json'
}

# Get-LegacyEnvironmentStatePath
# Returns the name-only state file used before managed values were recorded.
function Get-LegacyEnvironmentStatePath {
    return Join-Path $StateDir 'environment.txt'
}

# Get-ManagedEnvironmentState
# Reads managed names and the exact values CustomShell applied. Legacy name-only
# records are retained with an unknown desired value so they are never cleared
# without proof that CustomShell still owns the current value.
function Get-ManagedEnvironmentState {
    $path = Get-EnvironmentStatePath
    if (Test-Path -LiteralPath $path) {
        try {
            $state = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            return @($state.entries | Where-Object { $_.name } | ForEach-Object {
                    [pscustomobject]@{
                        name    = [string] $_.name
                        desired = if ($null -eq $_.desired) { $null } else { [string] $_.desired }
                    }
                })
        }
        catch {
            throw "Could not read environment state file ${path}: $($_.Exception.Message)"
        }
    }

    $legacyPath = Get-LegacyEnvironmentStatePath
    if (Test-Path -LiteralPath $legacyPath) {
        return @(Get-Content -LiteralPath $legacyPath | Where-Object { $_ -ne '' } | ForEach-Object {
                [pscustomobject]@{ name = [string] $_; desired = $null }
            })
    }

    return @()
}

# Save-ManagedEnvironmentState
# Persists managed names and values, replacing the legacy name-only record.
function Save-ManagedEnvironmentState {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Entries
    )

    if ($DryRun) {
        return
    }

    $path = Get-EnvironmentStatePath
    $legacyPath = Get-LegacyEnvironmentStatePath
    if ($Entries.Count -eq 0) {
        foreach ($statePath in @($path, $legacyPath)) {
            if (Test-Path -LiteralPath $statePath) {
                Remove-Item -LiteralPath $statePath -Force
            }
        }
        return
    }

    if (-not (Test-Path -LiteralPath $StateDir)) {
        New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
    }
    $state = [ordered]@{
        version = 1
        entries = @($Entries | Sort-Object name | ForEach-Object {
                [ordered]@{ name = $_.name; desired = $_.desired }
            })
    }
    $temporaryPath = Join-Path $StateDir ('.environment.' + [guid]::NewGuid() + '.tmp')
    try {
        $state | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $temporaryPath
        Move-Item -LiteralPath $temporaryPath -Destination $path -Force
    }
    finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $legacyPath) {
        Remove-Item -LiteralPath $legacyPath -Force
    }
}

# Install-PersistentEnvironment
# Sets required values and fills portable defaults without claiming existing values.
function Install-PersistentEnvironment {
    $desiredValues = Get-PersistentEnvironment
    $portableNames = Get-PortableEnvironmentNames

    # Register CONDA_PATH only when CustomShell would be the one setting it; a
    # user-provided valid value is respected and left unmanaged.
    if (-not (Test-CondaPathConfigured)) {
        $condaPath = Get-CondaPath
        if ($condaPath) {
            $desiredValues['CONDA_PATH'] = $condaPath
        }
    }

    $desiredNames = @($desiredValues.Keys) + $portableNames
    $existingByName = @{}
    foreach ($entry in (Get-ManagedEnvironmentState)) {
        $existingByName[$entry.name] = $entry
    }
    $managed = [System.Collections.Generic.List[object]]::new()

    # Clear recorded values that are no longer managed, e.g. STARSHIP_CONFIG
    # after switching away from the starship prompt.
    foreach ($entry in $existingByName.Values) {
        $name = $entry.name
        if ($desiredNames -contains $name) {
            continue
        }
        if ($name -eq 'CONDA_PATH' -and (Test-CondaPathConfigured)) {
            $managed.Add($entry)
            continue
        }

        $current = Get-ScopedEnvironmentValue $name $EnvironmentScope
        if ($null -eq $current) {
            continue
        }
        if ($null -eq $entry.desired -or $current -ne $entry.desired) {
            Write-Warning "Keeping modified environment variable ${name}: '$current'."
            $managed.Add($entry)
            continue
        }
        if ($DryRun) {
            Write-Host "Would clear $EnvironmentScope environment variable $name"
        }
        else {
            Set-ScopedEnvironmentValue $name $null $EnvironmentScope
            Write-Host "Cleared $EnvironmentScope environment variable $name (no longer managed)"
        }
    }

    foreach ($name in $desiredNames) {
        if ($name -in $portableNames) {
            $configured = Get-PortableEnvironmentValue $name
            if ($configured) {
                $entry = $existingByName[$name]
                if ($configured.Scope -eq $EnvironmentScope -and $entry -and
                    [string]::Equals($configured.Value, $entry.desired, [StringComparison]::Ordinal)) {
                    $managed.Add($entry)
                }
                if ($EnvironmentScope -eq 'User' -and $configured.Scope -eq 'Process') {
                    Write-Host "Keeping Process environment variable ${name} (not persistent)"
                }
                continue
            }
            $desired = Get-PortableEnvironmentDefault $name
            if ([string]::IsNullOrEmpty($desired)) {
                Write-Warning "No default available for environment variable ${name}."
                continue
            }
            $current = $null
        }
        else {
            $desired = $desiredValues[$name]
            $current = Get-ScopedEnvironmentValue $name $EnvironmentScope
        }

        if ($current -ne $desired) {
            if ($DryRun) {
                Write-Host "Would set $EnvironmentScope environment variable ${name}=$desired"
            }
            else {
                Set-ScopedEnvironmentValue $name $desired $EnvironmentScope
                Write-Host "Set $EnvironmentScope environment variable ${name}=$desired"
            }
        }

        $managed.Add([pscustomobject]@{ name = $name; desired = $desired })
    }

    Save-ManagedEnvironmentState -Entries $managed.ToArray()
}

# Uninstall-PersistentEnvironment
# Clears managed environment values that still match their desired value.
function Uninstall-PersistentEnvironment {
    $remaining = [System.Collections.Generic.List[object]]::new()
    $portableNames = Get-PortableEnvironmentNames

    foreach ($entry in (Get-ManagedEnvironmentState)) {
        $name = $entry.name
        $current = Get-ScopedEnvironmentValue $name $EnvironmentScope
        if ($null -eq $current) {
            continue
        }

        $isPortable = $name -in $portableNames
        $isModified = if ($isPortable) {
            -not [string]::Equals($current, $entry.desired, [StringComparison]::Ordinal)
        }
        else {
            $current -ne $entry.desired
        }
        if ($null -eq $entry.desired -or $isModified) {
            Write-Warning "Keeping modified environment variable ${name}: '$current'."
            if (-not $isPortable) {
                $remaining.Add($entry)
            }
            continue
        }

        if ($DryRun) {
            Write-Host "Would clear $EnvironmentScope environment variable $name"
        }
        else {
            Set-ScopedEnvironmentValue $name $null $EnvironmentScope
            Write-Host "Cleared $EnvironmentScope environment variable $name"
        }
    }

    Save-ManagedEnvironmentState -Entries $remaining.ToArray()
}
