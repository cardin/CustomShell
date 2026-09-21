# Shipped configuration-file installation. This file only defines functions and
# is dot-sourced by pwsh/Install.ps1. The functions read the setup-scope
# variables ($configDir, $EspansoMatchDir, $EspansoConfigDir, $manifestPath,
# $DryRun) established by the entry point.

# Install-Configs
# Installs every shipped configuration file and records the manifest.
function Install-Configs {
    $manifest = @(Get-ManifestEntries)

    foreach ($entry in (Get-ExpectedConfigEntries)) {
        Install-ConfigFile -Source $entry.Source `
            -DestinationDir (Split-Path -Parent $entry.Destination) `
            -Manifest ([ref]$manifest)
    }

    Save-ManifestEntries -Entries $manifest
}

# Uninstall-Configs
# Removes managed files that still match their shipped source.
function Uninstall-Configs {
    $entries = @(Get-ManifestEntries)
    $sourcesByName = @{}
    foreach ($source in @(Get-ExpectedConfigEntries | ForEach-Object { $_.Source })) {
        $sourcesByName[(Split-Path -Leaf $source)] = $source
    }

    foreach ($entry in $entries) {
        if (-not (Test-Path -LiteralPath $entry)) {
            continue
        }

        $source = $sourcesByName[(Split-Path -Leaf $entry)]
        if ($source -and (Test-Path -LiteralPath $source -PathType Leaf)) {
            $same = (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash -eq
                (Get-FileHash -Algorithm SHA256 -LiteralPath $entry).Hash
            if (-not $same) {
                Write-Warning "Keeping modified file: $entry"
                continue
            }
        }

        if ($DryRun) {
            Write-Host "Would remove $entry"
        }
        else {
            Remove-Item -LiteralPath $entry -Force
            Write-Host "Removed $entry"
        }
    }

    if (Test-Path -LiteralPath $manifestPath) {
        if ($DryRun) {
            Write-Host "Would remove $manifestPath"
        }
        else {
            Remove-Item -LiteralPath $manifestPath -Force
        }
    }
}

# Get-ExpectedConfigPaths
# Lists the destination paths the setup manages.
function Get-ExpectedConfigPaths {
    return @(Get-ExpectedConfigEntries | ForEach-Object { $_.Destination })
}

# Get-ExpectedConfigEntries
# Pairs each shipped source with the destination that setup keeps current.
function Get-ExpectedConfigEntries {
    return @(
        [pscustomobject]@{
            Source      = Join-Path $configDir 'espanso/_base.yml'
            Destination = Join-Path $EspansoMatchDir '_base.yml'
        }
        [pscustomobject]@{
            Source      = Join-Path $configDir 'espanso/whitelist.yml'
            Destination = Join-Path $EspansoConfigDir 'whitelist.yml'
        }
    )
}
