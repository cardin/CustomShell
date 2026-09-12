# Shipped configuration-file installation. This file only defines functions and
# is dot-sourced by pwsh/Install.ps1. The functions read the setup-scope
# variables ($configDir, $EspansoMatchDir, $EspansoConfigDir, $ClinkScriptDir,
# $manifestPath, $DryRun) established by the entry point.

# Install-Configs
# Installs every shipped configuration file and records the manifest.
function Install-Configs {
    $manifest = @(Get-ManifestEntries)

    Install-ConfigFile -Source (Join-Path $configDir 'espanso/_base.yml') `
        -DestinationDir $EspansoMatchDir -Manifest ([ref]$manifest)
    Install-ConfigFile -Source (Join-Path $configDir 'espanso/whitelist.yml') `
        -DestinationDir $EspansoConfigDir -Manifest ([ref]$manifest)
    foreach ($source in (Get-ClinkSources)) {
        Install-ConfigFile -Source $source.FullName `
            -DestinationDir $ClinkScriptDir -Manifest ([ref]$manifest)
    }

    Save-ManifestEntries -Entries $manifest
}

# Uninstall-Configs
# Removes managed files that still match their shipped source.
function Uninstall-Configs {
    $entries = @(Get-ManifestEntries)
    $sourcesByName = @{}
    foreach ($source in @(
            (Join-Path $configDir 'espanso/_base.yml')
            (Join-Path $configDir 'espanso/whitelist.yml')
        )) {
        $sourcesByName[(Split-Path -Leaf $source)] = $source
    }
    foreach ($source in (Get-ClinkSources)) {
        $sourcesByName[$source.Name] = $source.FullName
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
    $paths = @(
        (Join-Path $EspansoMatchDir '_base.yml')
        (Join-Path $EspansoConfigDir 'whitelist.yml')
    )
    foreach ($source in (Get-ClinkSources)) {
        $paths += Join-Path $ClinkScriptDir $source.Name
    }
    return $paths
}
