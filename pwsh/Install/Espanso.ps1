# Espanso configuration discovery. This file only defines functions and is
# dot-sourced by pwsh/Install.ps1.

# Get-EspansoReportedConfigDir
# Asks Espanso itself for its config directory. Espanso's GUI launcher does not
# emit its output to a plain `&` call, so the command is routed through cmd.exe.
# The daemon binary is tried first, with the launcher command as a fallback for
# installs that expose only `espanso`.
function Get-EspansoReportedConfigDir {
    foreach ($name in @('espansod', 'espanso')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if (-not $command) {
            continue
        }

        $output = $null
        try {
            $output = & cmd.exe /c $command.Source path config 2>$null
        }
        catch {
            $output = $null
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
