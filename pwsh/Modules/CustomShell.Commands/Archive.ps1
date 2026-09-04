# Implements the paired commands for creating and extracting encrypted tar
# archives with age. Temporary files, replacement safety, and extraction
# path validation are handled here so callers receive consistent cleanup behavior.

function Move-CustomShellArchiveFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $SourcePath,

        [Parameter(Mandatory)]
        [string] $DestinationPath
    )

    [IO.File]::Move($SourcePath, $DestinationPath)
}

function Move-CustomShellArchiveItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $SourcePath,

        [Parameter(Mandatory)]
        [string] $DestinationPath
    )

    Move-Item `
        -LiteralPath $SourcePath `
        -Destination $DestinationPath `
        -ErrorAction Stop
}

function Confirm-CustomShellArchiveCollision {
    [CmdletBinding()]
    param()

    if ([Console]::IsInputRedirected) {
        return $false
    }
    $response = Read-Host -Prompt 'Extraction target exists. Merge archived content? [y/N]'
    $response -cin @('y', 'yes')
}

function Protect-Tar {
    <#
    .SYNOPSIS
    Compresses a file or folder and encrypts it using OpenSSL.

    .DESCRIPTION
    Creates a temporary tar.gz archive, encrypts it with AES-256-CBC and
    PBKDF2, authenticates the result with HMAC-SHA-256, and publishes a new
    timestamped .enc file only after every prior step succeeds.

    Prompts for the password and confirmation.

    .PARAMETER Source
    File or folder to archive.

    .PARAMETER Output
    Base path for the encrypted output. The command appends
    _<yyyyMMdd_HHmmss>.enc. Defaults to the source path.

    .PARAMETER Exclude
    Glob pattern(s) to omit from the archive, passed through to tar's
    --exclude option. Repeatable.

    .PARAMETER NoIgnore
    Disable the default recursive .tarignore handling, so all files
    including those matched by .tarignore files are archived.

    .PARAMETER Help
    Displays command usage and archive details without creating an archive.

    .EXAMPLE
    Protect-Tar C:\Projects\MyRepo

    .EXAMPLE
    Protect-Tar C:\Projects\MyRepo D:\Backups\MyRepo

    .EXAMPLE
    Protect-Tar C:\Projects\MyRepo -Exclude 'node_modules', '*.log'
    #>

    [CmdletBinding(DefaultParameterSetName = 'Archive')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Archive')]
        [ValidateNotNullOrEmpty()]
        [string] $Source,

        [Parameter(ParameterSetName = 'Archive')]
        [ValidateNotNullOrEmpty()]
        [string] $Output,

        [Parameter(ParameterSetName = 'Archive')]
        [string[]] $Exclude,

        [Parameter(ParameterSetName = 'Archive')]
        [switch] $NoIgnore,

        [Parameter(ValueFromRemainingArguments, ParameterSetName = 'Archive')]
        [object[]] $PortableArguments,

        [Parameter(Mandatory, ParameterSetName = 'Help')]
        [Alias('h')]
        [switch] $Help
    )

    if ($Source -eq '--help' -and $PortableArguments.Count -eq 0) {
        $Help = $true
    }

    if ($Help) {
        @'
Protect-Tar
    Compresses a directory or file and encrypts it with age.

USAGE
    Protect-Tar <source> [output_base] [--exclude <pattern>...] [--no-ignore]
    Protect-Tar --help

PARAMETERS
    source / -Source
        File or directory to archive.

    output_base / -Output
        Base path for the encrypted output. The command appends a datetime
        suffix and .enc extension. Defaults to the source path.

    --exclude <pattern>
        Glob pattern to omit from the archive, passed through to tar's
        --exclude option. Repeatable.

    --no-ignore / -NoIgnore
        Disable the default recursive .tarignore handling, so all files
        including those matched by .tarignore files are archived.

    --help
        Displays this help.

NOTES
    Requires tar.exe and age.exe. Encryption uses age with scrypt key
    derivation and ChaCha20-Poly1305 authenticated encryption.
'@
        return
    }

    for ($index = 0; $index -lt $PortableArguments.Count; $index++) {
        $argument = [string] $PortableArguments[$index]
        if ($argument -eq '--exclude') {
            if ($index + 1 -ge $PortableArguments.Count) {
                throw '--exclude requires a pattern.'
            }
            $index++
            $pattern = [string] $PortableArguments[$index]
            if ([string]::IsNullOrEmpty($pattern)) {
                throw '--exclude requires a pattern.'
            }
            $Exclude += $pattern
        }
        elseif ($argument.StartsWith('--exclude=')) {
            $pattern = $argument.Substring('--exclude='.Length)
            if ([string]::IsNullOrEmpty($pattern)) {
                throw '--exclude requires a pattern.'
            }
            $Exclude += $pattern
        }
        elseif ($argument -eq '--no-ignore') {
            $NoIgnore = $true
        }
        elseif ($argument.StartsWith('-')) {
            throw "Unknown option: $argument"
        }
        elseif ([string]::IsNullOrWhiteSpace($Output)) {
            $Output = $argument
        }
        else {
            throw "Unexpected argument: $argument"
        }
    }

    $age = Get-Command age -ErrorAction SilentlyContinue

    if (-not $age) {
        throw @"
age was not found in PATH.

Install age or ensure age.exe is available in PATH.
"@
    }

    $tar = Get-Command tar.exe -ErrorAction SilentlyContinue

    if (-not $tar) {
        throw 'tar.exe was not found in PATH.'
    }

    Write-Progress -Activity 'Protect-Tar' -Status '[1/4] Validating source paths...' -PercentComplete 5
    $sourceItem = Get-Item -LiteralPath $Source -ErrorAction Stop
    $sourceParentPath = if ($sourceItem.PSIsContainer) {
        $sourceItem.Parent.FullName
    }
    else {
        $sourceItem.Directory.FullName
    }

    if ($sourceItem.FullName -eq [IO.Path]::GetPathRoot($sourceItem.FullName)) {
        throw 'Refusing a filesystem root as source.'
    }

    if ($Exclude.Count -gt 0 -and -not $sourceItem.PSIsContainer) {
        throw '-Exclude can only be used with a directory source.'
    }

    $outputBase = if ([string]::IsNullOrWhiteSpace($Output)) {
        $sourceItem.FullName
    }
    else {
        $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Output)
    }
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $outputPath = "${outputBase}_${timestamp}.enc"

    $outputExists = Test-Path -LiteralPath $outputPath

    if ($outputExists) {
        throw "Output file already exists: $outputPath"
    }

    $outputDirectory = Split-Path -Parent $outputPath

    if (
        $outputDirectory -and
        -not (Test-Path -LiteralPath $outputDirectory -PathType Container)
    ) {
        throw "Output parent directory does not exist: $outputDirectory"
    }

    if (
        $sourceItem.PSIsContainer -and
        $outputPath.StartsWith(
            "$($sourceItem.FullName.TrimEnd('\', '/'))$([IO.Path]::DirectorySeparatorChar)",
            [StringComparison]::OrdinalIgnoreCase
        )
    ) {
        throw 'Output cannot be created inside the source directory.'
    }

    $temporaryTar = Join-Path `
    ([IO.Path]::GetTempPath()) `
        "$([guid]::NewGuid()).tar.gz"

    # Keep the encrypted temporary file on the destination volume so replacing
    # an existing archive can be performed atomically after encryption succeeds.
    $temporaryOutput = Join-Path `
        $outputDirectory `
        ".$([IO.Path]::GetFileName($outputPath)).$([guid]::NewGuid()).tmp"

    try {
        Write-Progress -Activity 'Protect-Tar' -Status '[2/4] Packaging files...' -PercentComplete 25
        Write-Verbose "Creating temporary archive: $temporaryTar"

        $tarignoreExcludes = @(
            if ($sourceItem.PSIsContainer -and -not $NoIgnore) {
                $ignoreFiles = @(Get-ChildItem -LiteralPath $sourceItem.FullName -Filter '.tarignore' -Recurse -Force -File -ErrorAction SilentlyContinue)
                foreach ($ignoreFile in $ignoreFiles) {
                    $dir = $ignoreFile.Directory
                    $relDir = if ($dir.FullName -eq $sourceItem.FullName) {
                        ''
                    }
                    else {
                        $dir.FullName.Substring($sourceItem.FullName.Length + 1).Replace('\', '/')
                    }
                    $lines = @(Get-Content -LiteralPath $ignoreFile.FullName -ErrorAction SilentlyContinue)
                    foreach ($line in $lines) {
                        $trimmed = $line.Trim()
                        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) {
                            continue
                        }
                        if (-not ($trimmed.Contains('/') -or $trimmed.Contains('\'))) {
                            if ([string]::IsNullOrEmpty($relDir)) {
                                "--exclude=$trimmed"
                            }
                            else {
                                "--exclude=*$($sourceItem.Name)/$relDir/$trimmed"
                                "--exclude=*$($sourceItem.Name)/$relDir/$trimmed/*"
                            }
                        }
                        else {
                            $clean = $trimmed.TrimStart('/', '\').Replace('\', '/')
                            if ([string]::IsNullOrEmpty($relDir)) {
                                "--exclude=*$($sourceItem.Name)/$clean"
                                "--exclude=*$($sourceItem.Name)/$clean/*"
                            }
                            else {
                                "--exclude=*$($sourceItem.Name)/$relDir/$clean"
                                "--exclude=*$($sourceItem.Name)/$relDir/$clean/*"
                            }
                        }
                    }
                }
            }
        )

        $excludeArgs = @(
            foreach ($pattern in $Exclude) {
                "--exclude=$pattern"
            }
            $tarignoreExcludes
        )
        Write-Verbose "Archiving '$($sourceItem.Name)' from '$sourceParentPath'."

        $totalItems = if ($sourceItem.PSIsContainer) {
            (Get-ChildItem -LiteralPath $sourceItem.FullName -Recurse -Force | Measure-Object).Count + 1
        }
        else {
            1
        }
        $count = 0

        $tarOutput = & $tar.Source `
            -czvf $temporaryTar `
            @excludeArgs `
            -C $sourceParentPath `
            ".\$($sourceItem.Name)" 2>&1 | ForEach-Object {
            $line = $_.ToString()
            if ($line -match '^a\s') {
                $count++
                if ($totalItems -gt 0) {
                    $pct = [Math]::Min(100, [int](($count / $totalItems) * 100))
                    Write-Progress -Activity 'Protect-Tar' -Status "[2/4] Packaging files: $pct% ($count/$totalItems)" -PercentComplete $pct
                }
            }
            $_
        }

        if ($LASTEXITCODE -ne 0) {
            $tarText = ($tarOutput | ForEach-Object { $_.ToString() }) -join "`n"
            $reparseItems = @(
                if ($sourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                    $sourceItem
                }
                if ($sourceItem.PSIsContainer) {
                    Get-ChildItem -LiteralPath $sourceItem.FullName -Recurse -Force -ErrorAction SilentlyContinue |
                        Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }
                }
            )

            if ($tarText -match 'Cannot stat' -or $tarText -match 'symlink' -or $reparseItems.Count -gt 0) {
                $symlinkDetails = if ($reparseItems.Count -gt 0) {
                    $samplePaths = ($reparseItems | Select-Object -First 3 | ForEach-Object { "  - $($_.FullName)" }) -join "`n"
                    "Found $($reparseItems.Count) symbolic link(s) or reparse point(s), including:`n$samplePaths"
                }
                else {
                    "tar.exe error output indicated symbolic link or stat issue(s)."
                }

                $outputMessage = if (-not [string]::IsNullOrWhiteSpace($tarText)) {
                    "`n`ntar.exe output:`n$tarText"
                }
                else {
                    ""
                }

                throw @"
tar.exe failed because symbolic links or WSL reparse points in '$($sourceItem.FullName)' could not be processed by native tar.exe.

$symlinkDetails$outputMessage

To resolve this issue:
- Remove or resolve symbolic links in Windows before archiving.
- Exclude build directories or virtual environments containing symlinks (e.g. .venv, node_modules).
- Run Protect-Tar from inside WSL (Linux) if symbolic links must be preserved.
"@
            }

            if (-not [string]::IsNullOrWhiteSpace($tarText)) {
                throw "tar.exe failed with exit code ${LASTEXITCODE}:`n$tarText"
            }

            throw "tar.exe failed with exit code $LASTEXITCODE."
        }

        $createdArchiveDetails = @(& $tar.Source -tvzf $temporaryTar)
        if ($LASTEXITCODE -ne 0) {
            throw "tar.exe could not inspect the created archive (exit code $LASTEXITCODE)."
        }
        foreach ($detail in $createdArchiveDetails) {
            $detailText = [string] $detail
            if (
                $detailText -match '^[lh]' -or
                $detailText -match '\s->\s' -or
                $detailText -match '\slink to\s'
            ) {
                throw "Symbolic and hard links are not supported on Windows: $detailText"
            }
        }

        Write-Progress -Activity 'Protect-Tar' -Status '[3/4] Encrypting archive with age...' -PercentComplete 75
        Write-Verbose "Encrypting archive as: $outputPath"

        $ageOutput = & $age.Source -p -o $temporaryOutput $temporaryTar 2>&1

        if ($LASTEXITCODE -ne 0) {
            $ageText = ($ageOutput | ForEach-Object { $_.ToString() }) -join "`n"
            throw "Encryption failed with exit code ${LASTEXITCODE}: $ageText"
        }

        Write-Progress -Activity 'Protect-Tar' -Status '[4/4] Publishing archive...' -PercentComplete 95
        Move-CustomShellArchiveFile `
            -SourcePath $temporaryOutput `
            -DestinationPath $outputPath

        try {
            Remove-Item -LiteralPath $temporaryTar -Force -ErrorAction Stop
        }
        catch {
            throw "Archive was published, but temporary file cleanup failed: $($_.Exception.Message)"
        }

        Write-Verbose 'Encrypted archive created successfully.'
        Get-Item -LiteralPath $outputPath
    }
    finally {
        Write-Progress -Activity 'Protect-Tar' -Completed
        Remove-Item `
            -LiteralPath $temporaryTar, $temporaryOutput `
            -Force `
            -ErrorAction SilentlyContinue
    }
}


function Unprotect-Tar {
    <#
    .SYNOPSIS
    Decrypts and extracts an archive created by Protect-Tar.

    .DESCRIPTION
    Uses OpenSSL to decrypt the archive into a temporary tar.gz file,
    then validates its entries before extracting it using tar.exe. Extraction
    is staged separately and published transactionally so unsafe paths and
    failed operations do not leave partial destination changes. Symbolic-link
    and hard-link archive entries are rejected.

    Prompts for the password.

    .PARAMETER Archive
    Encrypted archive created by Protect-Tar.

    .PARAMETER Destination
    Destination folder. Defaults to the current directory. Filesystem roots,
    the home directory, and the CustomShell repository root are refused.

    .PARAMETER Help
    Displays command usage and archive details without extracting an archive.

    .EXAMPLE
    Unprotect-Tar C:\Backups\MyRepo_20260904_120000.enc

    .EXAMPLE
    Unprotect-Tar C:\Backups\MyRepo_20260904_120000.enc C:\Restored
    #>

    [CmdletBinding(DefaultParameterSetName = 'Extract')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Extract')]
        [ValidateNotNullOrEmpty()]
        [string] $Archive,

        [Parameter(ParameterSetName = 'Extract')]
        [ValidateNotNullOrEmpty()]
        [string] $Destination = '.',

        [Parameter(ValueFromRemainingArguments, ParameterSetName = 'Extract')]
        [object[]] $PortableArguments,

        [Parameter(Mandatory, ParameterSetName = 'Help')]
        [Alias('h')]
        [switch] $Help
    )

    if ($Archive -eq '--help' -and $PortableArguments.Count -eq 0) {
        $Help = $true
    }

    if ($Help) {
        @'
Unprotect-Tar
    Decrypts and safely extracts an archive created by Protect-Tar.

USAGE
    Unprotect-Tar <archive.enc> [destination_directory]
    Unprotect-Tar -Archive <file> [-Destination <directory>]
    Unprotect-Tar --help

PARAMETERS
    archive / -Archive
        Encrypted archive created by Protect-Tar.

    destination_directory / -Destination
        Directory into which the archive is extracted. Defaults to the current
        directory. Filesystem roots, the home directory, and the CustomShell
        repository root are refused.

    --help
        Displays this help.

NOTES
    Requires tar.exe and age.exe. Archives are decrypted and authenticated with
    age before archive paths and link entries are validated and transactionally
    extracted.
'@
        return
    }

    foreach ($argument in $PortableArguments) {
        $argumentText = [string] $argument
        if ($argumentText.StartsWith('-')) {
            throw "Unknown option: $argumentText"
        }
        if ($Destination -ne '.') {
            throw "Unexpected argument: $argumentText"
        }
        $Destination = $argumentText
    }

    $age = Get-Command age -ErrorAction SilentlyContinue

    if (-not $age) {
        throw @"
age was not found in PATH.

Install age or ensure age.exe is available in PATH.
"@
    }

    $tar = Get-Command tar.exe -ErrorAction SilentlyContinue

    if (-not $tar) {
        throw 'tar.exe was not found in PATH.'
    }

    $archiveItem = Get-Item -LiteralPath $Archive -ErrorAction Stop

    if ($archiveItem.PSIsContainer) {
        throw "'$Archive' is a folder, not an encrypted archive."
    }

    $destinationPath = $ExecutionContext.SessionState.Path.
    GetUnresolvedProviderPathFromPSPath($Destination)

    $repositoryRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
    $normalizedDestination = [IO.Path]::GetFullPath($destinationPath).TrimEnd('\', '/')
    $destinationRoot = [IO.Path]::GetPathRoot($normalizedDestination).TrimEnd('\', '/')
    $protectedDestinations = @(
        [IO.Path]::GetFullPath($HOME).TrimEnd('\', '/')
        [IO.Path]::GetFullPath($repositoryRoot).TrimEnd('\', '/')
    )

    if (
        [string]::IsNullOrWhiteSpace($normalizedDestination) -or
        $normalizedDestination -eq $destinationRoot -or
        $normalizedDestination -in $protectedDestinations
    ) {
        throw "Refusing to extract into protected destination: $normalizedDestination"
    }

    $destinationExists = Test-Path -LiteralPath $destinationPath

    if ($destinationExists -and -not (Test-Path -LiteralPath $destinationPath -PathType Container)) {
        throw "'$destinationPath' is not a folder."
    }

    $temporaryTar = Join-Path `
    ([IO.Path]::GetTempPath()) `
        "$([guid]::NewGuid()).tar.gz"

    $stagingDirectory = Join-Path `
    ([IO.Path]::GetTempPath()) `
        "$([guid]::NewGuid())"

    $transactionDirectory = $null
    $preserveTransactionDirectory = $false

    try {
        Write-Progress -Activity 'Unprotect-Tar' -Status '[1/4] Decrypting archive with age...' -PercentComplete 10
        Write-Verbose "Decrypting archive to temporary file: $temporaryTar"

        $ageOutput = & $age.Source -d -o $temporaryTar $archiveItem.FullName 2>&1

        if ($LASTEXITCODE -ne 0) {
            $ageText = ($ageOutput | ForEach-Object { $_.ToString() }) -join "`n"
            throw @"
Decryption failed with exit code $LASTEXITCODE.

The password may be incorrect, the file may be damaged, or the
archive may have been created with different options.
$ageText
"@
        }

        Write-Progress -Activity 'Unprotect-Tar' -Status '[2/4] Validating archive contents...' -PercentComplete 35
        Write-Verbose 'Validating archive entries.'

        $archiveEntries = @(& $tar.Source -tzf $temporaryTar)

        if ($LASTEXITCODE -ne 0) {
            throw "tar.exe could not read the archive (exit code $LASTEXITCODE)."
        }

        $seenEntries = [Collections.Generic.HashSet[string]]::new(
            [StringComparer]::OrdinalIgnoreCase
        )
        $topLevelEntries = [Collections.Generic.HashSet[string]]::new(
            [StringComparer]::OrdinalIgnoreCase
        )
        foreach ($entry in $archiveEntries) {
            $normalizedEntry = ([string] $entry).Replace('\', '/')
            while ($normalizedEntry.StartsWith('./')) {
                $normalizedEntry = $normalizedEntry.Substring(2)
            }
            $normalizedEntry = $normalizedEntry.TrimEnd('/')
            $segments = $normalizedEntry -split '/'

            if (
                [string]::IsNullOrWhiteSpace($normalizedEntry) -or
                $normalizedEntry.StartsWith('/') -or
                $normalizedEntry -match '^[A-Za-z]:' -or
                $segments -contains '..'
            ) {
                throw "Unsafe archive entry: $entry"
            }

            foreach ($segment in $segments) {
                $baseName = ($segment -split '\.', 2)[0]
                if (
                    $segment -match '[\x00-\x1f<>:"|?*]' -or
                    $segment.EndsWith(' ') -or
                    $segment.EndsWith('.') -or
                    $baseName -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$'
                ) {
                    throw "Archive entry cannot be recreated on Windows: $entry"
                }
            }

            if (-not $seenEntries.Add($normalizedEntry)) {
                throw "Archive contains duplicate or case-colliding entry: $entry"
            }
            $null = $topLevelEntries.Add($segments[0])
        }

        if ($topLevelEntries.Count -ne 1) {
            throw 'Archive must contain exactly one top-level item.'
        }

        # Member names alone do not reveal where symbolic and hard links point.
        # Reject link entries rather than depending on tar.exe's version-specific
        # extraction policy to keep their targets inside the staging directory.
        $archiveDetails = @(& $tar.Source -tvzf $temporaryTar)

        if ($LASTEXITCODE -ne 0) {
            throw "tar.exe could not inspect the archive (exit code $LASTEXITCODE)."
        }

        foreach ($detail in $archiveDetails) {
            $detailText = [string] $detail
            if (
                $detailText -match '^[lh]' -or
                $detailText -match '\s->\s' -or
                $detailText -match '\slink to\s'
            ) {
                throw "Archive links are not supported: $detailText"
            }
            if ($detailText -notmatch '^[-d]') {
                throw "Archive member type is not supported: $detailText"
            }
        }

        New-Item `
            -ItemType Directory `
            -Path $stagingDirectory `
            -ErrorAction Stop |
        Out-Null

        Write-Progress -Activity 'Unprotect-Tar' -Status '[3/4] Extracting files...' -PercentComplete 50
        Write-Verbose "Extracting archive into staging directory: $stagingDirectory"

        $totalEntries = $archiveEntries.Count
        $extractCount = 0

        $tarExtractOutput = & $tar.Source `
            -xzvf $temporaryTar `
            -C $stagingDirectory 2>&1 | ForEach-Object {
            $line = $_.ToString()
            if ($line -match '^x\s') {
                $extractCount++
                if ($totalEntries -gt 0) {
                    $pct = [Math]::Min(100, [int](($extractCount / $totalEntries) * 100))
                    Write-Progress -Activity 'Unprotect-Tar' -Status "[3/4] Extracting files: $pct% ($extractCount/$totalEntries)" -PercentComplete $pct
                }
            }
            $_
        }

        if ($LASTEXITCODE -ne 0) {
            $tarExtractText = ($tarExtractOutput | ForEach-Object { $_.ToString() }) -join "`n"
            if (-not [string]::IsNullOrWhiteSpace($tarExtractText)) {
                throw "tar.exe extraction failed with exit code ${LASTEXITCODE}:`n$tarExtractText"
            }
            throw "tar.exe extraction failed with exit code $LASTEXITCODE."
        }

        Write-Progress -Activity 'Unprotect-Tar' -Status '[4/4] Merging and finalizing destination...' -PercentComplete 90

        $destinationParent = Split-Path -Parent $destinationPath
        if (-not (Test-Path -LiteralPath $destinationParent -PathType Container)) {
            throw "Destination parent directory does not exist: $destinationParent"
        }

        # Prepare every item on the destination volume before changing the
        # destination. Existing directories are copied first so extraction keeps
        # its historical merge behavior without exposing a partially copied tree.
        $transactionDirectory = Join-Path `
            $destinationParent `
            ".customshell-decode-$([guid]::NewGuid())"
        $candidateRoot = Join-Path $transactionDirectory 'candidate'
        $backupRoot = Join-Path $transactionDirectory 'backup'
        New-Item -ItemType Directory -Path $candidateRoot, $backupRoot -ErrorAction Stop |
            Out-Null

        $stagedItems = @(Get-ChildItem -LiteralPath $stagingDirectory -Force)
        if ($stagedItems.Count -ne 1) {
            throw 'Archive must contain exactly one top-level item.'
        }

        if (-not $destinationExists) {
            $candidateDestination = Join-Path $transactionDirectory 'destination'
            New-Item -ItemType Directory -Path $candidateDestination -ErrorAction Stop |
                Out-Null
            $stagedItems |
                Copy-Item `
                    -Destination $candidateDestination `
                    -Recurse `
                    -Force `
                    -ErrorAction Stop

            [IO.Directory]::Move($candidateDestination, $destinationPath)
        }
        else {
            $collisions = @(
                foreach ($stagedItem in $stagedItems) {
                    $targetPath = Join-Path $destinationPath $stagedItem.Name
                    Get-Item -LiteralPath $targetPath -Force -ErrorAction SilentlyContinue
                }
            )
            if ($collisions.Count -gt 0 -and -not (Confirm-CustomShellArchiveCollision)) {
                if ([Console]::IsInputRedirected) {
                    throw 'Extraction target exists and confirmation requires an interactive terminal.'
                }
                throw 'Extraction cancelled; destination was not changed.'
            }

            foreach ($stagedItem in $stagedItems) {
                $targetPath = Join-Path $destinationPath $stagedItem.Name
                $targetItem = Get-Item -LiteralPath $targetPath -Force -ErrorAction SilentlyContinue

                if (
                    $targetItem -and
                    $targetItem.PSIsContainer -and
                    $stagedItem.PSIsContainer -and
                    -not ($targetItem.Attributes -band [IO.FileAttributes]::ReparsePoint)
                ) {
                    Copy-Item `
                        -LiteralPath $targetItem.FullName `
                        -Destination $candidateRoot `
                        -Recurse `
                        -Force `
                        -ErrorAction Stop

                    Get-ChildItem -LiteralPath $stagedItem.FullName -Force |
                        Copy-Item `
                            -Destination (Join-Path $candidateRoot $stagedItem.Name) `
                            -Recurse `
                            -Force `
                            -ErrorAction Stop
                }
                else {
                    Copy-Item `
                        -LiteralPath $stagedItem.FullName `
                        -Destination $candidateRoot `
                        -Recurse `
                        -Force `
                        -ErrorAction Stop
                }
            }

            $publishStates = [Collections.Generic.List[object]]::new()

            try {
                foreach ($stagedItem in $stagedItems) {
                    $targetPath = Join-Path $destinationPath $stagedItem.Name
                    $candidatePath = Join-Path $candidateRoot $stagedItem.Name
                    $backupPath = Join-Path $backupRoot $stagedItem.Name
                    $state = [pscustomobject]@{
                        TargetPath = $targetPath
                        BackupPath = $backupPath
                        BackedUp   = $false
                        Published  = $false
                    }
                    $publishStates.Add($state)

                    if (Test-Path -LiteralPath $targetPath) {
                        Move-CustomShellArchiveItem `
                            -SourcePath $targetPath `
                            -DestinationPath $backupPath
                        $state.BackedUp = $true
                    }

                    Move-CustomShellArchiveItem `
                        -SourcePath $candidatePath `
                        -DestinationPath $targetPath
                    $state.Published = $true
                }
            }
            catch {
                $publishError = $_
                $rollbackFailures = [Collections.Generic.List[string]]::new()

                for ($index = $publishStates.Count - 1; $index -ge 0; $index--) {
                    $state = $publishStates[$index]

                    if ($state.Published -and (Test-Path -LiteralPath $state.TargetPath)) {
                        try {
                            Remove-Item `
                                -LiteralPath $state.TargetPath `
                                -Recurse `
                                -Force `
                                -ErrorAction Stop
                            $state.Published = $false
                        }
                        catch {
                            $rollbackFailures.Add($_.Exception.Message)
                        }
                    }

                    if ($state.BackedUp -and -not (Test-Path -LiteralPath $state.TargetPath)) {
                        try {
                            Move-CustomShellArchiveItem `
                                -SourcePath $state.BackupPath `
                                -DestinationPath $state.TargetPath
                            $state.BackedUp = $false
                        }
                        catch {
                            $rollbackFailures.Add($_.Exception.Message)
                        }
                    }
                }

                if ($rollbackFailures.Count -gt 0) {
                    $preserveTransactionDirectory = $true
                    throw @"
Publishing extracted files failed, and rollback was incomplete. Preserved
backup data can be recovered from:

    $backupRoot

Publish error: $($publishError.Exception.Message)
Rollback errors: $($rollbackFailures -join '; ')
"@
                }

                throw $publishError
            }
        }

        if ($transactionDirectory) {
            try {
                Remove-Item -LiteralPath $transactionDirectory -Recurse -Force -ErrorAction Stop
                $transactionDirectory = $null
            }
            catch {
                $preserveTransactionDirectory = $true
                throw "Extracted content was published, but transaction cleanup failed: $transactionDirectory"
            }
        }

        try {
            Remove-Item `
                -LiteralPath $temporaryTar, $stagingDirectory `
                -Recurse `
                -Force `
                -ErrorAction Stop
        }
        catch {
            throw "Extracted content was published, but temporary file cleanup failed: $($_.Exception.Message)"
        }

        Write-Verbose 'Archive extracted successfully.'
        Get-ChildItem -LiteralPath $destinationPath -Force
    }
    finally {
        Write-Progress -Activity 'Unprotect-Tar' -Completed
        Remove-Item `
            -LiteralPath $temporaryTar, $stagingDirectory `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue

        if ($transactionDirectory -and -not $preserveTransactionDirectory) {
            Remove-Item `
                -LiteralPath $transactionDirectory `
                -Recurse `
                -Force `
                -ErrorAction SilentlyContinue
        }
    }
}
