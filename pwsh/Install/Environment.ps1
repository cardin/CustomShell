# Persistent user environment values managed by CustomShell setup. The entry
# point's -EnvironmentScope selects the target scope; User is the real target
# and Process exists so tests never touch the registry. Managed values always
# win, so an existing conflicting value is overwritten. This file only defines
# functions and is dot-sourced by pwsh/Install.ps1. The functions read the
# setup-scope variables ($StateDir, $configDir, $DryRun, $EnvironmentScope).

# Get-PersistentEnvironment
# Returns the environment values CustomShell keeps set for the user. BAT_CONFIG_PATH
# points bat at the repository's shared configuration file so plain bat picks up
# the header/grid style without a shell alias.
function Get-PersistentEnvironment {
    return [ordered]@{
        'UV_SYSTEM_CERTS' = 'true'
        'BAT_CONFIG_PATH' = (Join-Path $configDir 'bat.conf')
    }
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
    $managed = [System.Collections.Generic.List[string]]::new()
    foreach ($name in (Get-ManagedEnvironmentNames)) {
        $managed.Add($name)
    }

    $desiredValues = Get-PersistentEnvironment
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
