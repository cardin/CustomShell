# Persistent user environment values managed by CustomShell setup. The entry
# point's -EnvironmentScope selects the target scope; User is the real target
# and Process exists so tests never touch the registry. Managed values always
# win, so an existing conflicting value is overwritten; CONDA_PATH is the
# exception, since a user-provided valid value is respected and left unmanaged.
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
# Returns the file that records the environment values CustomShell set.
function Get-EnvironmentStatePath {
    return Join-Path $StateDir 'environment.txt'
}

# Get-ManagedEnvironmentNames
# Reads the recorded environment variable names.
function Get-ManagedEnvironmentNames {
    $path = Get-EnvironmentStatePath
    if (Test-Path -LiteralPath $path) {
        return @(Get-Content -LiteralPath $path | Where-Object { $_ -ne '' })
    }
    return @()
}

# Save-ManagedEnvironmentNames
# Persists the recorded environment variable names.
function Save-ManagedEnvironmentNames {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]] $Names
    )

    if ($DryRun) {
        return
    }

    $path = Get-EnvironmentStatePath
    if ($Names.Count -eq 0) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force
        }
        return
    }

    if (-not (Test-Path -LiteralPath $StateDir)) {
        New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
    }
    Set-Content -LiteralPath $path -Value @($Names | Sort-Object -Unique)
}

# Install-PersistentEnvironment
# Sets each managed environment value, overwriting conflicting existing values.
function Install-PersistentEnvironment {
    $desiredValues = Get-PersistentEnvironment

    # Register CONDA_PATH only when CustomShell would be the one setting it; a
    # user-provided valid value is respected and left unmanaged.
    if (-not (Test-CondaPathConfigured)) {
        $condaPath = Get-CondaPath
        if ($condaPath) {
            $desiredValues['CONDA_PATH'] = $condaPath
        }
    }

    $desiredNames = @($desiredValues.Keys)
    $managed = [System.Collections.Generic.List[string]]::new()

    # Clear recorded values that are no longer managed, e.g. STARSHIP_CONFIG
    # after switching away from the starship prompt.
    foreach ($name in (Get-ManagedEnvironmentNames)) {
        if ($desiredNames -contains $name) {
            $managed.Add($name)
            continue
        }
        if ($name -eq 'CONDA_PATH' -and (Test-CondaPathConfigured)) {
            $managed.Add($name)
            continue
        }

        $current = [Environment]::GetEnvironmentVariable($name, $EnvironmentScope)
        if ($null -eq $current) {
            continue
        }
        if ($DryRun) {
            Write-Host "Would clear $EnvironmentScope environment variable $name"
        }
        else {
            [Environment]::SetEnvironmentVariable($name, $null, $EnvironmentScope)
            Write-Host "Cleared $EnvironmentScope environment variable $name (no longer managed)"
        }
    }

    foreach ($name in $desiredValues.Keys) {
        $desired = $desiredValues[$name]
        $current = [Environment]::GetEnvironmentVariable($name, $EnvironmentScope)

        if ($current -ne $desired) {
            if ($DryRun) {
                Write-Host "Would set $EnvironmentScope environment variable ${name}=$desired"
            }
            else {
                [Environment]::SetEnvironmentVariable($name, $desired, $EnvironmentScope)
                Write-Host "Set $EnvironmentScope environment variable ${name}=$desired"
            }
        }

        if (-not $managed.Contains($name)) {
            $managed.Add($name)
        }
    }

    Save-ManagedEnvironmentNames -Names $managed.ToArray()
}

# Uninstall-PersistentEnvironment
# Clears managed environment values that still match their desired value.
function Uninstall-PersistentEnvironment {
    $desiredValues = Get-PersistentEnvironment
    $remaining = [System.Collections.Generic.List[string]]::new()

    foreach ($name in (Get-ManagedEnvironmentNames)) {
        $current = [Environment]::GetEnvironmentVariable($name, $EnvironmentScope)
        if ($null -eq $current) {
            continue
        }

        $desired = if ($desiredValues.Contains($name)) { $desiredValues[$name] } else { $null }
        if ($desired -and $current -ne $desired) {
            Write-Warning "Keeping modified environment variable ${name}: '$current'."
            $remaining.Add($name)
            continue
        }

        if ($DryRun) {
            Write-Host "Would clear $EnvironmentScope environment variable $name"
        }
        else {
            [Environment]::SetEnvironmentVariable($name, $null, $EnvironmentScope)
            Write-Host "Cleared $EnvironmentScope environment variable $name"
        }
    }

    Save-ManagedEnvironmentNames -Names $remaining.ToArray()
}
