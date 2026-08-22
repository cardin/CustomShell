function TarEnc {
    <#
    .SYNOPSIS
    Compresses a folder and encrypts it using OpenSSL.

    .DESCRIPTION
    Creates a temporary tar.gz archive, then encrypts it with
    AES-256-CBC and PBKDF2.

    OpenSSL prompts for the password and confirmation.

    .PARAMETER Source
    Folder to archive.

    .PARAMETER Output
    Encrypted output file. Defaults to <folder>_<yyyyMMdd_HHmmss>.tar.gz.enc
    beside the source folder.

    .PARAMETER Force
    Replaces the output file if it already exists.

    .EXAMPLE
    TarEnc C:\Projects\MyRepo

    .EXAMPLE
    TarEnc C:\Projects\MyRepo D:\Backups\MyRepo.tar.gz.enc

    .EXAMPLE
    TarEnc C:\Projects\MyRepo -Force
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
            [IO.File]::Move($outputPath, $replacementBackup)
            try {
                [IO.File]::Move($temporaryOutput, $outputPath)
            }
            catch {
                [IO.File]::Move($replacementBackup, $outputPath)
                throw
            }
        }
        else {
            [IO.File]::Move($temporaryOutput, $outputPath)
        }

        Write-Verbose 'Encrypted archive created successfully.'
        Get-Item -LiteralPath $outputPath
    }
    finally {
        Remove-Item `
            -LiteralPath $temporaryTar, $temporaryOutput, $replacementBackup `
            -Force `
            -ErrorAction SilentlyContinue
    }
}


function UnTarEnc {
    <#
    .SYNOPSIS
    Decrypts and extracts an archive created by TarEnc.

    .DESCRIPTION
    Uses OpenSSL to decrypt the archive into a temporary tar.gz file,
    then extracts it using tar.exe.

    OpenSSL prompts for the password.

    .PARAMETER Archive
    Encrypted archive created by TarEnc.

    .PARAMETER Destination
    Destination folder. Defaults to the current directory.

    .EXAMPLE
    UnTarEnc C:\Backups\MyRepo.tar.gz.enc

    .EXAMPLE
    UnTarEnc C:\Backups\MyRepo.tar.gz.enc C:\Restored
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

        if (-not $destinationExists) {
            Move-Item `
                -LiteralPath $stagingDirectory `
                -Destination $destinationPath `
                -ErrorAction Stop
        }
        else {
            Get-ChildItem -LiteralPath $stagingDirectory -Force |
            Copy-Item `
                -Destination $destinationPath `
                -Recurse `
                -Force `
                -ErrorAction Stop
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
    }
}
