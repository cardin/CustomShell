# Read-only setup checks. This file only defines functions and is dot-sourced by
# pwsh/Install.ps1. The functions read the setup-scope variables ($repoDir,
# $settings, $ProfilePath, $EnvironmentScope).

# Get-MissingRequiredCommand
# Returns the configured required command names that are not currently
# available. The list lives in pwsh/Settings.psd1.
function Get-MissingRequiredCommand {
    @($settings.RequiredCommands | Where-Object {
            -not (Get-Command $_ -ErrorAction SilentlyContinue)
        })
}

# Write-CommandReport
# Prints the state of the required commands as a single advisory line. It never
# fails the run; missing optional tools are reported, not enforced.
function Write-CommandReport {
    $missingCommands = Get-MissingRequiredCommand
    if ($missingCommands.Count -eq 0) {
        Write-Host 'Commands: all expected commands found'
    }
    else {
        Write-Host "Commands: missing: $($missingCommands -join ', ')"
    }
}

# Invoke-Checks
# Prints the setup state and returns the number of incomplete requirements.
function Invoke-Checks {
    $failures = 0
    Write-Host 'CustomShell setup check'
    Write-Host "  repository: $repoDir"

    if (Test-ProfileHasBlock) {
        $newline = [Environment]::NewLine
        $desired = ((Get-DesiredProfileLines -Action Write) -join $newline) + $newline
        $existing = [IO.File]::ReadAllText($ProfilePath)
        if ($existing -eq $desired) {
            Write-Host "  profile:    current ($ProfilePath)"
        }
        else {
            Write-Host "  profile:    stale ($ProfilePath) - run Install.ps1"
            $failures++
        }
    }
    elseif (Test-ProfileHasUnmarkedSource) {
        Write-Host "  profile:    manually sourced and unmanaged ($ProfilePath)"
    }
    else {
        Write-Host "  profile:    not configured ($ProfilePath) - run Install.ps1"
        $failures++
    }

    $missing = @(Get-ExpectedConfigPaths | Where-Object { -not (Test-Path -LiteralPath $_) })
    if ($missing.Count -eq 0) {
        Write-Host '  configs:    installed'
    }
    else {
        Write-Host "  configs:    $($missing.Count) missing - run Install.ps1"
        $failures++
    }

    $environmentValues = Get-PersistentEnvironment
    foreach ($name in $environmentValues.Keys) {
        $desired = $environmentValues[$name]
        $current = [Environment]::GetEnvironmentVariable($name, $EnvironmentScope)
        if ($current -eq $desired) {
            Write-Host "  env:        ${name}=$current ($EnvironmentScope)"
            continue
        }

        $shown = if ($null -eq $current) { 'unset' } else { $current }
        if ($EnvironmentScope -eq 'User') {
            # Process scope is a test affordance and cannot persist, so only a
            # real User-scope mismatch is treated as a failure.
            Write-Host "  env:        ${name}=$shown ($EnvironmentScope) - run Install.ps1"
            $failures++
        }
        else {
            Write-Host "  env:        ${name}=$shown ($EnvironmentScope)"
        }
    }

    if ($env:CONDA_PATH) {
        if (Test-Path -LiteralPath (Join-Path $env:CONDA_PATH 'conda.exe') -PathType Leaf) {
            Write-Host '  conda:      configured'
        }
        else {
            Write-Host "  conda:      CONDA_PATH set but conda.exe missing: $env:CONDA_PATH"
        }
    }
    else {
        Write-Host '  conda:      CONDA_PATH not set (optional)'
    }

    Write-Host "  prompt:     $($settings.Prompt)"

    $missingCommands = Get-MissingRequiredCommand
    if ($missingCommands.Count -eq 0) {
        Write-Host '  commands:   all expected commands found'
    }
    else {
        Write-Host "  commands:   missing: $($missingCommands -join ', ')"
    }

    return $failures
}
