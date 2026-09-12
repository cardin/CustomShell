# Managed PowerShell profile block. The functions read the setup-scope variables
# ($ProfilePath, $entryScript, $markerBegin, $markerEnd, $desiredSource,
# $DryRun) established by the entry point. This file only defines functions and
# is dot-sourced by pwsh/Install.ps1.

# Get-ProfileLines
# Reads the selected profile, returning an empty array when it does not exist.
function Get-ProfileLines {
    if (Test-Path -LiteralPath $ProfilePath) {
        return , @(Get-Content -LiteralPath $ProfilePath)
    }
    return , @()
}

# Get-ProfileBlockBounds
# Locates the managed block markers, using -1 when either marker is absent.
function Get-ProfileBlockBounds {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]] $Lines
    )

    $start = -1
    $end = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($start -lt 0 -and $Lines[$i] -eq $markerBegin) {
            $start = $i
            continue
        }
        if ($start -ge 0 -and $Lines[$i] -eq $markerEnd) {
            $end = $i
            break
        }
    }

    return [pscustomobject]@{ Start = $start; End = $end }
}

# Test-ProfileHasBlock
# Succeeds when the profile contains a complete managed block.
function Test-ProfileHasBlock {
    $bounds = Get-ProfileBlockBounds -Lines (Get-ProfileLines)
    return ($bounds.Start -ge 0 -and $bounds.End -ge 0)
}

# Test-ProfileContentReferencesEntryPoint
# Succeeds when profile text references the entry point, tolerating either path
# separator so manual lines written with forward slashes are still detected.
function Test-ProfileContentReferencesEntryPoint {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Content
    )

    if (-not $Content) {
        return $false
    }

    $normalizedEntry = $entryScript.Replace('\', '/')
    return $Content.Replace('\', '/').Contains($normalizedEntry)
}

# Test-ProfileHasUnmarkedSource
# Succeeds when the entry point is referenced without a managed block.
function Test-ProfileHasUnmarkedSource {
    if (-not (Test-Path -LiteralPath $ProfilePath)) {
        return $false
    }
    if (Test-ProfileHasBlock) {
        return $false
    }

    return (Test-ProfileContentReferencesEntryPoint -Content (
            Get-Content -LiteralPath $ProfilePath -Raw -ErrorAction SilentlyContinue))
}

# Get-ConflictingProfilePaths
# Returns other PowerShell profile files beside the target that also reference
# the entry point. Loading both would run CustomShell startup twice.
function Get-ConflictingProfilePaths {
    $directory = Split-Path -Parent $ProfilePath
    if (-not $directory -or -not (Test-Path -LiteralPath $directory)) {
        return @()
    }

    $target = [IO.Path]::GetFullPath($ProfilePath)
    $conflicts = Get-ChildItem -LiteralPath $directory -Filter '*profile.ps1' -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -ne $target -and
            (Test-ProfileContentReferencesEntryPoint -Content (
                    Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue))
        }

    return @($conflicts | ForEach-Object { $_.FullName })
}

# Get-DesiredProfileLines
# Computes the profile content for a write or remove action.
function Get-DesiredProfileLines {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Write', 'Remove')]
        [string] $Action
    )

    $lines = Get-ProfileLines
    $bounds = Get-ProfileBlockBounds -Lines $lines
    $result = [System.Collections.Generic.List[string]]::new()

    if ($bounds.Start -ge 0 -and $bounds.End -ge 0) {
        $headEnd = $bounds.Start - 1
        if ($Action -eq 'Remove' -and $headEnd -ge 0 -and $lines[$headEnd] -eq '') {
            $headEnd--
        }
        for ($i = 0; $i -le $headEnd; $i++) {
            $result.Add($lines[$i])
        }
        if ($Action -eq 'Write') {
            $result.Add($markerBegin)
            $result.Add($desiredSource)
            $result.Add($markerEnd)
        }
        for ($i = $bounds.End + 1; $i -lt $lines.Count; $i++) {
            $result.Add($lines[$i])
        }
    }
    elseif ($Action -eq 'Write') {
        foreach ($line in $lines) {
            $result.Add($line)
        }
        if ($lines.Count -gt 0) {
            $result.Add('')
        }
        $result.Add($markerBegin)
        $result.Add($desiredSource)
        $result.Add($markerEnd)
    }
    else {
        foreach ($line in $lines) {
            $result.Add($line)
        }
    }

    return , $result.ToArray()
}

# Write-ProfileContent
# Writes the supplied lines atomically, skipping byte-identical content.
function Write-ProfileContent {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]] $Lines
    )

    $newline = [Environment]::NewLine
    $content = (($Lines -join $newline) + $newline)
    $existing = if (Test-Path -LiteralPath $ProfilePath) {
        [IO.File]::ReadAllText($ProfilePath)
    }
    else {
        ''
    }
    if ($existing -eq $content) {
        return $false
    }

    if ($DryRun) {
        Write-Host "Would update profile: $ProfilePath"
        return $false
    }

    $directory = Split-Path -Parent $ProfilePath
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $temporaryPath = Join-Path $directory ('.customshell.' + [guid]::NewGuid() + '.tmp')
    [IO.File]::WriteAllText($temporaryPath, $content)
    Move-Item -LiteralPath $temporaryPath -Destination $ProfilePath -Force
    Write-Host "Updated profile block in $ProfilePath"
    return $true
}

# Install-ProfileBlock
# Adds or refreshes the managed block unless the entry point is already sourced.
function Install-ProfileBlock {
    if (Test-ProfileHasUnmarkedSource) {
        Write-Warning "Skipped profile update: $ProfilePath already sources CustomShell without a managed block."
        return
    }

    foreach ($conflict in Get-ConflictingProfilePaths) {
        Write-Warning "$conflict also sources CustomShell; remove that line to avoid duplicate startup output."
    }

    [void](Write-ProfileContent -Lines (Get-DesiredProfileLines -Action Write))
}

# Uninstall-ProfileBlock
# Removes the managed block when present.
function Uninstall-ProfileBlock {
    if (-not (Test-ProfileHasBlock)) {
        return
    }

    [void](Write-ProfileContent -Lines (Get-DesiredProfileLines -Action Remove))
}
