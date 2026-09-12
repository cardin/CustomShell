# Espanso configuration discovery. This file only defines functions and is
# dot-sourced by pwsh/Install.ps1.

# Get-EspansoReportedConfigDir
# Asks Espanso itself for its config directory. The daemon binary is tried as a
# fallback because some launcher shims do not forward its output.
function Get-EspansoReportedConfigDir {
    foreach ($name in @('espanso', 'espansod')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if (-not $command) {
            continue
        }

        $output = $null
        try {
            $output = & $command.Source path config 2>$null
        }
        catch {
            $output = $null
        }
        if (-not @($output | Where-Object { $_ -and $_.ToString().Trim() })) {
            # Console-subsystem launchers can swallow the daemon's output when
            # invoked directly; routing through cmd.exe captures it reliably.
            try {
                $output = & cmd.exe /c $command.Source path config 2>$null
            }
            catch {
                $output = $null
            }
        }
        if ($LASTEXITCODE -ne 0) {
            continue
        }

        $line = $output | Where-Object { $_ -and $_.ToString().Trim() } | Select-Object -First 1
        if (-not $line) {
            continue
        }

        $path = $line.ToString().Trim()
        if (Test-Path -LiteralPath $path -PathType Container) {
            return $path
        }
    }

    return $null
}

# Get-DefaultEspansoRoot
# Resolves the Espanso configuration root, preferring the tool's own report and
# otherwise falling back to Espanso's documented Windows default.
function Get-DefaultEspansoRoot {
    $reported = Get-EspansoReportedConfigDir
    if ($reported) {
        return $reported
    }

    if ($env:APPDATA) {
        return Join-Path $env:APPDATA 'espanso'
    }
    throw 'EspansoRoot was not provided and no Espanso configuration directory could be located.'
}
