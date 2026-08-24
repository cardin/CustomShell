# Implements the paired commands for creating and extracting encrypted tar
# archives with OpenSSL. Temporary files, replacement safety, and extraction
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

function Protect-Tar {
    <#
    .SYNOPSIS
    Compresses a folder and encrypts it using OpenSSL.

    .DESCRIPTION
    Creates a temporary tar.gz archive, then encrypts it with
    AES-256-CBC and PBKDF2. Existing output is replaced only after encryption
    succeeds, and temporary or backup files are removed during cleanup.

    OpenSSL prompts for the password and confirmation.

    .PARAMETER Source
    Folder to archive.

    .PARAMETER Output
    Encrypted output file. Defaults to <folder>_<yyyyMMdd_HHmmss>.tar.gz.enc
    beside the source folder.

    .PARAMETER Force
    Replaces the output file if it already exists.

    .EXAMPLE
    Protect-Tar C:\Projects\MyRepo

    .EXAMPLE
    Protect-Tar C:\Projects\MyRepo D:\Backups\MyRepo.tar.gz.enc

    .EXAMPLE
    Protect-Tar C:\Projects\MyRepo -Force
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Source,

        [Parameter(Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string] $Output,

        [switch] $Force
    )

    $openssl = Get-Command openssl -ErrorAction SilentlyContinue

    if (-not $openssl) {
        throw @"
OpenSSL was not found in PATH.

Install OpenSSL or ensure openssl.exe is available in PATH.
You can verify it with:

    openssl version
"@
    }

    $tar = Get-Command tar.exe -ErrorAction SilentlyContinue

    if (-not $tar) {
        throw 'tar.exe was not found in PATH.'
    }

    $sourceItem = Get-Item -LiteralPath $Source -ErrorAction Stop

    if (-not $sourceItem.PSIsContainer) {
        throw "'$Source' is not a folder."
    }

    if ([string]::IsNullOrWhiteSpace($Output)) {
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $Output = Join-Path `
            $sourceItem.Parent.FullName `
            "$($sourceItem.Name)_$timestamp.tar.gz.enc"
    }

    $outputPath = $ExecutionContext.SessionState.Path.
    GetUnresolvedProviderPathFromPSPath($Output)

    $outputExists = Test-Path -LiteralPath $outputPath

    if ($outputExists -and -not $Force) {
        throw "Output file already exists: $outputPath`nUse -Force to replace it."
    }

    $outputDirectory = Split-Path -Parent $outputPath

    if (
        $outputDirectory -and
        -not (Test-Path -LiteralPath $outputDirectory)
    ) {
        New-Item `
            -ItemType Directory `
            -Path $outputDirectory `
            -Force `
            -ErrorAction Stop |
        Out-Null
    }

    $temporaryTar = Join-Path `
    ([IO.Path]::GetTempPath()) `
        "$([guid]::NewGuid()).tar.gz"

    # Keep the encrypted temporary file on the destination volume so replacing
    # an existing archive can be performed atomically after encryption succeeds.
    $temporaryOutput = Join-Path `
        $outputDirectory `
        ".$([IO.Path]::GetFileName($outputPath)).$([guid]::NewGuid()).tmp"

    $replacementBackup = Join-Path `
        $outputDirectory `
        ".$([IO.Path]::GetFileName($outputPath)).$([guid]::NewGuid()).bak"

    # Once the existing archive is moved aside, this flag prevents cleanup from
    # deleting the only preserved copy unless publishing or restoration succeeds.
    $preserveReplacementBackup = $false

    try {
        Write-Verbose "Creating temporary archive: $temporaryTar"

        & $tar.Source `
            -czf $temporaryTar `
            -C $sourceItem.Parent.FullName `
            $sourceItem.Name

        if ($LASTEXITCODE -ne 0) {
            throw "tar.exe failed with exit code $LASTEXITCODE."
        }

        Write-Verbose "Encrypting archive as: $outputPath"

        # OpenSSL prompts twice:
        # Enter encryption password:
        # Verifying - Enter encryption password:
        & $openssl.Source enc `
            -aes-256-cbc `
            -salt `
            -pbkdf2 `
            -iter 600000 `
            -in $temporaryTar `
            -out $temporaryOutput

        if ($LASTEXITCODE -ne 0) {
            throw "OpenSSL encryption failed with exit code $LASTEXITCODE."
        }

        if ($outputExists) {
            # ReplaceFile/File.Replace can be rejected by some Windows
            # filesystems and sandbox providers. Use same-directory renames so
            # the original can still be restored if publishing the new archive
            # fails.
            Move-CustomShellArchiveFile `
                -SourcePath $outputPath `
                -DestinationPath $replacementBackup
            $preserveReplacementBackup = $true
            try {
                Move-CustomShellArchiveFile `
                    -SourcePath $temporaryOutput `
                    -DestinationPath $outputPath
                $preserveReplacementBackup = $false
            }
            catch {
                $publishError = $_
                try {
                    Move-CustomShellArchiveFile `
                        -SourcePath $replacementBackup `
                        -DestinationPath $outputPath
                    $preserveReplacementBackup = $false
                }
                catch {
                    throw @"
Publishing the replacement archive failed, and the original could not be
restored automatically. The original archive is preserved at:

    $replacementBackup

Publish error: $($publishError.Exception.Message)
Restore error: $($_.Exception.Message)
"@
                }

                throw $publishError
            }
        }
        else {
            Move-CustomShellArchiveFile `
                -SourcePath $temporaryOutput `
                -DestinationPath $outputPath
        }

        Write-Verbose 'Encrypted archive created successfully.'
        Get-Item -LiteralPath $outputPath
    }
    finally {
        Remove-Item `
            -LiteralPath $temporaryTar, $temporaryOutput `
            -Force `
            -ErrorAction SilentlyContinue

        if (-not $preserveReplacementBackup) {
            Remove-Item `
                -LiteralPath $replacementBackup `
                -Force `
                -ErrorAction SilentlyContinue
        }
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

    OpenSSL prompts for the password.

    .PARAMETER Archive
    Encrypted archive created by Protect-Tar.

    .PARAMETER Destination
    Destination folder. Defaults to the current directory. Filesystem roots,
    the home directory, and the CustomShell repository root are refused.

    .EXAMPLE
    Unprotect-Tar C:\Backups\MyRepo.tar.gz.enc

    .EXAMPLE
    Unprotect-Tar C:\Backups\MyRepo.tar.gz.enc C:\Restored
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Archive,

        [Parameter(Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string] $Destination = '.'
    )

    $openssl = Get-Command openssl -ErrorAction SilentlyContinue

    if (-not $openssl) {
        throw @"
OpenSSL was not found in PATH.

Install OpenSSL or ensure openssl.exe is available in PATH.
You can verify it with:

    openssl version
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
        Write-Verbose "Decrypting archive to temporary file: $temporaryTar"

        # OpenSSL prompts:
        # Enter decryption password:
        & $openssl.Source enc `
            -d `
            -aes-256-cbc `
            -pbkdf2 `
            -iter 600000 `
            -in $archiveItem.FullName `
            -out $temporaryTar

        if ($LASTEXITCODE -ne 0) {
            throw @"
OpenSSL decryption failed with exit code $LASTEXITCODE.

The password may be incorrect, the file may be damaged, or the
archive may have been created with different OpenSSL options.
"@
        }

        Write-Verbose 'Validating archive entries.'

        $archiveEntries = @(& $tar.Source -tzf $temporaryTar)

        if ($LASTEXITCODE -ne 0) {
            throw "tar.exe could not read the archive (exit code $LASTEXITCODE)."
        }

        foreach ($entry in $archiveEntries) {
            $normalizedEntry = ([string] $entry).Replace('\', '/')
            $segments = $normalizedEntry -split '/'

            if (
                $normalizedEntry.StartsWith('/') -or
                $normalizedEntry -match '^[A-Za-z]:' -or
                $segments -contains '..'
            ) {
                throw "Unsafe archive entry: $entry"
            }
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
        }

        New-Item `
            -ItemType Directory `
            -Path $stagingDirectory `
            -ErrorAction Stop |
        Out-Null

        Write-Verbose "Extracting archive into staging directory: $stagingDirectory"

        & $tar.Source `
            -xzf $temporaryTar `
            -C $stagingDirectory

        if ($LASTEXITCODE -ne 0) {
            throw "tar.exe extraction failed with exit code $LASTEXITCODE."
        }

        $destinationParent = Split-Path -Parent $destinationPath
        if (-not (Test-Path -LiteralPath $destinationParent -PathType Container)) {
            New-Item `
                -ItemType Directory `
                -Path $destinationParent `
                -Force `
                -ErrorAction Stop |
            Out-Null
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

        Write-Verbose 'Archive extracted successfully.'

        Get-ChildItem -LiteralPath $destinationPath -Force
    }
    finally {
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
