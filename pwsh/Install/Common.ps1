# Shared helpers for the CustomShell setup entry point. This file only defines
# functions and is dot-sourced by pwsh/Install.ps1. The functions read the
# setup-scope variables ($configDir, $manifestPath, $StateDir, $DryRun, $Force)
# established by the entry point.

# ConvertTo-SingleQuoted
# Quotes a value for safe inclusion in a single-quoted PowerShell literal.
function ConvertTo-SingleQuoted {
    param(
        [Parameter(Mandatory)]
        [string] $Value
    )

    return "'" + $Value.Replace("'", "''") + "'"
}

# Get-ManifestEntries
# Reads the recorded managed destination paths.
function Get-ManifestEntries {
    if (Test-Path -LiteralPath $manifestPath) {
        return @(Get-Content -LiteralPath $manifestPath | Where-Object { $_ -ne '' })
    }
    return @()
}

# Save-ManifestEntries
# Persists the managed destination paths.
function Save-ManifestEntries {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]] $Entries
    )

    if ($DryRun) {
        return
    }
    if (-not (Test-Path -LiteralPath $StateDir)) {
        New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
    }
    Set-Content -LiteralPath $manifestPath -Value @($Entries | Sort-Object -Unique)
}

# Install-ConfigFile
# Copies one source file into its destination directory, tracking the result.
function Install-ConfigFile {
    param(
        [Parameter(Mandatory)]
        [string] $Source,
        [Parameter(Mandatory)]
        [string] $DestinationDir,
        [Parameter(Mandatory)]
        [ref] $Manifest
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "Missing configuration source: $Source"
    }

    $destination = Join-Path $DestinationDir (Split-Path -Leaf $Source)

    if (Test-Path -LiteralPath $destination) {
        $same = (Get-FileHash -Algorithm SHA256 -LiteralPath $Source).Hash -eq
            (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash
        if ($same) {
            $Manifest.Value += $destination
            return
        }

        if ($Manifest.Value -notcontains $destination) {
            if (-not $Force) {
                Write-Warning "Skipped ${destination}: a file already exists (use -Force to replace)."
                return
            }
            $backup = "$destination.customshell.bak"
            if (Test-Path -LiteralPath $backup) {
                throw "Backup already exists: $backup"
            }
            if (-not $DryRun) {
                Copy-Item -LiteralPath $destination -Destination $backup
            }
            Write-Host "Backed up existing file to $backup"
        }
    }

    if ($DryRun) {
        Write-Host "Would install $destination"
    }
    else {
        if (-not (Test-Path -LiteralPath $DestinationDir)) {
            New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
        }
        Copy-Item -LiteralPath $Source -Destination $destination -Force
        Write-Host "Installed $destination"
    }

    $Manifest.Value += $destination
}

# Get-ClinkSources
# Returns the shipped Clink Lua scripts.
function Get-ClinkSources {
    $clinkDir = Join-Path $configDir 'clink'
    if (-not (Test-Path -LiteralPath $clinkDir)) {
        return @()
    }
    return @(Get-ChildItem -LiteralPath $clinkDir -Filter '*.lua' -File)
}
