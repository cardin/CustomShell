# Verifies protected archive replacement, cleanup, round trips, and traversal
# rejection. The suite uses unique temporary directories and a local age
# shim so it never prompts for credentials or contacts external services.
$modulePath = Join-Path $PSScriptRoot '..\..\Modules\CustomShell.Commands\CustomShell.Commands.psd1'

function New-MockAge {
    <#
    .SYNOPSIS
    Creates a controllable age command shim for archive tests.

    .DESCRIPTION
    Writes a local command that wraps and unwraps the payload with an age header
    and checksum, emulating the file flow and authentication expected by the
    archive commands.
    #>
    param(
        [Parameter(Mandatory)]
        [string] $Directory
    )

    $psScript = Join-Path $Directory 'mock_age.ps1'
    @'
param()
$output = $null
$mode = 'encrypt'
$inputFile = $null
$i = 0
while ($i -lt $args.Count) {
    if ($args[$i] -eq '-o') {
        $output = $args[$i+1]
        $i += 2
    }
    elseif ($args[$i] -eq '-p') {
        $mode = 'encrypt'
        $i++
    }
    elseif ($args[$i] -eq '-d') {
        $mode = 'decrypt'
        $i++
    }
    else {
        $inputFile = $args[$i]
        $i++
    }
}
if ($env:MOCK_AGE_FAIL -eq '1') {
    exit 9
}
if ($mode -eq 'encrypt') {
    $bytes = [IO.File]::ReadAllBytes($inputFile)
    $hasher = [Security.Cryptography.SHA256]::Create()
    $hash = [BitConverter]::ToString($hasher.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
    $header = [Text.Encoding]::ASCII.GetBytes("age-encryption.org/v1`n$hash`n")
    $outBytes = New-Object byte[] ($header.Length + $bytes.Length)
    [Buffer]::BlockCopy($header, 0, $outBytes, 0, $header.Length)
    [Buffer]::BlockCopy($bytes, 0, $outBytes, $header.Length, $bytes.Length)
    [IO.File]::WriteAllBytes($output, $outBytes)
    exit 0
}
elseif ($mode -eq 'decrypt') {
    $data = [IO.File]::ReadAllBytes($inputFile)
    $headerPrefix = [Text.Encoding]::ASCII.GetString($data, 0, [Math]::Min(22, $data.Length))
    if ($headerPrefix -ne "age-encryption.org/v1`n") {
        exit 1
    }
    if ($data.Length -lt 87) {
        exit 1
    }
    $expHash = [Text.Encoding]::ASCII.GetString($data, 22, 64)
    $body = New-Object byte[] ($data.Length - 87)
    [Buffer]::BlockCopy($data, 87, $body, 0, $body.Length)
    $hasher = [Security.Cryptography.SHA256]::Create()
    $actHash = [BitConverter]::ToString($hasher.ComputeHash($body)).Replace('-', '').ToLowerInvariant()
    if ($expHash -ne $actHash) {
        exit 1
    }
    [IO.File]::WriteAllBytes($output, $body)
    exit 0
}
'@ | Set-Content -LiteralPath $psScript -Encoding Ascii

    $mockPath = Join-Path $Directory 'age.cmd'
    @'
@echo off
if "%MOCK_AGE_FAIL%"=="1" exit /b 9
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0mock_age.ps1" %*
exit /b %ERRORLEVEL%
'@ | Set-Content -LiteralPath $mockPath -Encoding Ascii
}

function Set-TarOctalField {
    <#
    .SYNOPSIS
    Writes an octal value into a fixed-width tar header field.

    .DESCRIPTION
    Formats a numeric value using the null-terminated octal representation used
    by tar headers. The resulting ASCII bytes are copied into the requested
    offset and field width of the supplied header buffer.
    #>
    param(
        [byte[]] $Header,
        [int] $Offset,
        [int] $Length,
        [long] $Value
    )

    $text = [Convert]::ToString($Value, 8).PadLeft($Length - 1, '0') + "`0"
    [Text.Encoding]::ASCII.GetBytes($text).CopyTo($Header, $Offset)
}

function New-TestTarGzip {
    <#
    .SYNOPSIS
    Creates a minimal gzip-compressed tar with a chosen entry name.

    .DESCRIPTION
    Constructs a tar header and payload directly, calculates its checksum, and
    wraps the result in gzip compression. Tests use the chosen entry name to
    exercise extraction validation without relying on an unsafe filesystem tree.
    #>
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $EntryName,

        [string] $Content = 'test payload',

        [ValidateSet('0', '1', '2')]
        [string] $EntryType = '0',

        [string] $LinkName
    )

    $header = New-Object byte[] 512
    [Text.Encoding]::ASCII.GetBytes($EntryName).CopyTo($header, 0)
    Set-TarOctalField $header 100 8 420
    Set-TarOctalField $header 108 8 0
    Set-TarOctalField $header 116 8 0
    [byte[]] $contentBytes = @()
    if ($EntryType -eq '0') {
        $contentBytes = [Text.Encoding]::UTF8.GetBytes($Content)
    }
    Set-TarOctalField $header 124 12 $contentBytes.Length
    Set-TarOctalField $header 136 12 0

    for ($index = 148; $index -lt 156; $index++) {
        $header[$index] = 32
    }

    $header[156] = [byte][char]$EntryType
    if ($LinkName) {
        [Text.Encoding]::ASCII.GetBytes($LinkName).CopyTo($header, 157)
    }
    [Text.Encoding]::ASCII.GetBytes("ustar`0").CopyTo($header, 257)
    [Text.Encoding]::ASCII.GetBytes('00').CopyTo($header, 263)

    $checksum = 0
    foreach ($value in $header) {
        $checksum += $value
    }
    $checksumText = [Convert]::ToString($checksum, 8).PadLeft(6, '0') + "`0 "
    [Text.Encoding]::ASCII.GetBytes($checksumText).CopyTo($header, 148)

    $tarStream = New-Object IO.MemoryStream
    try {
        $tarStream.Write($header, 0, $header.Length)
        $tarStream.Write($contentBytes, 0, $contentBytes.Length)

        $paddingLength = (512 - ($contentBytes.Length % 512)) % 512
        if ($paddingLength -gt 0) {
            $tarStream.Write((New-Object byte[] $paddingLength), 0, $paddingLength)
        }
        $tarStream.Write((New-Object byte[] 1024), 0, 1024)
        $tarStream.Position = 0

        $gzipMemStream = New-Object IO.MemoryStream
        try {
            $gzipStream = New-Object IO.Compression.GZipStream(
                $gzipMemStream,
                [IO.Compression.CompressionMode]::Compress
            )
            try {
                $tarStream.CopyTo($gzipStream)
            }
            finally {
                $gzipStream.Dispose()
            }

            $bytes = $gzipMemStream.ToArray()
            $hasher = [Security.Cryptography.SHA256]::Create()
            $hash = [BitConverter]::ToString($hasher.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
            $header = [Text.Encoding]::ASCII.GetBytes("age-encryption.org/v1`n$hash`n")
            $outBytes = New-Object byte[] ($header.Length + $bytes.Length)
            [Buffer]::BlockCopy($header, 0, $outBytes, 0, $header.Length)
            [Buffer]::BlockCopy($bytes, 0, $outBytes, $header.Length, $bytes.Length)
            [IO.File]::WriteAllBytes($Path, $outBytes)
        }
        finally {
            $gzipMemStream.Dispose()
        }
    }
    finally {
        $tarStream.Dispose()
    }
}

Describe 'protected tar archives' {
    BeforeAll {
        Import-Module -Name $modulePath -Force
    }

    It 'exports only commands with approved PowerShell verbs' {
        $approvedVerbs = (Get-Verb).Verb
        $unapprovedCommands = @(
            Get-Command -Module CustomShell.Commands |
                Where-Object Verb -NotIn $approvedVerbs
        )

        $unapprovedCommands.Count | Should Be 0
    }

    It 'shows Protect-Tar help with --help without requiring a source' {
        $helpText = Protect-Tar --help | Out-String

        $helpText | Should Match 'USAGE'
        $helpText | Should Match 'Protect-Tar <source>'
        $helpText | Should Match 'ChaCha20-Poly1305'
        $helpText | Should Match '--exclude'
    }

    It 'shows Unprotect-Tar help with --help without requiring an archive' {
        $helpText = Unprotect-Tar --help | Out-String

        $helpText | Should Match 'USAGE'
        $helpText | Should Match 'Unprotect-Tar <archive.enc>'
        $helpText | Should Match 'transactionally'
    }

    BeforeEach {
        $script:testRoot = Join-Path ([IO.Path]::GetTempPath()) "CustomShell.Tests-$([guid]::NewGuid())"
        $script:source = Join-Path $testRoot 'source'
        $script:mockBin = Join-Path $testRoot 'bin'
        $script:archiveBase = Join-Path $testRoot 'archive'
        $script:archive = $null
        $script:originalPath = $env:PATH
        $script:originalPathExt = $env:PATHEXT

        New-Item -ItemType Directory -Path $source, $mockBin | Out-Null
        Set-Content -LiteralPath (Join-Path $source 'data.txt') -Value 'round trip payload'
        New-MockAge -Directory $mockBin
        $env:PATHEXT = '.COM;.EXE;.BAT;.CMD'
        $env:PATH = "$mockBin;$originalPath"
        Remove-Item Env:MOCK_AGE_FAIL -ErrorAction SilentlyContinue
        Mock Confirm-CustomShellArchiveCollision {
            [bool] $global:CustomShellCollisionResponse
        } -ModuleName CustomShell.Commands
    }

    AfterEach {
        $env:PATH = $originalPath
        $env:PATHEXT = $originalPathExt
        Remove-Item Env:MOCK_AGE_FAIL -ErrorAction SilentlyContinue
        Remove-Variable `
            -Name CustomShellMoveCall, CustomShellPublishFailed, CustomShellFailFinalMove, CustomShellCollisionResponse `
            -Scope Global `
            -ErrorAction SilentlyContinue

        $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
        $resolvedTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if ($resolvedTestRoot.StartsWith($resolvedTempRoot, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'does not publish an archive when encryption fails' {
        $env:MOCK_AGE_FAIL = '1'

        $didThrow = $false
        try {
            Protect-Tar -Source $source -Output $archiveBase | Out-Null
        }
        catch {
            $didThrow = $true
        }

        $didThrow | Should Be $true
        @(Get-ChildItem -LiteralPath $testRoot -Filter 'archive_*.enc').Count | Should Be 0
    }

    It 'creates a timestamped authenticated archive' {
        $archive = (Protect-Tar -Source $source -Output $archiveBase).FullName

        [IO.Path]::GetFileName($archive) | Should Match '^archive_\d{8}_\d{6}\.enc$'
        $magic = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($archive), 0, 21)
        $magic | Should Be 'age-encryption.org/v1'
    }

    It 'uses the source path as the default output base' {
        $archive = (Protect-Tar -Source $source).FullName

        [IO.Path]::GetFileName($archive) | Should Match '^source_\d{8}_\d{6}\.enc$'
        Split-Path -Parent $archive | Should Be $testRoot
    }

    It 'omits patterns passed to -Exclude from the archive' {
        New-Item -ItemType Directory -Path (Join-Path $source 'node_modules') -Force |
            Out-Null
        Set-Content -LiteralPath (Join-Path $source 'node_modules/dep.txt') -Value 'dependency'
        Set-Content -LiteralPath (Join-Path $source 'drop.log') -Value 'drop me'
        $destination = Join-Path $testRoot 'restored'

        $archive = (Protect-Tar `
            $source `
            $archiveBase `
            --exclude node_modules `
            --exclude '*.log').FullName
        Unprotect-Tar -Archive $archive -Destination $destination | Out-Null

        Test-Path -LiteralPath (Join-Path $destination 'source\data.txt') | Should Be $true
        Test-Path -LiteralPath (Join-Path $destination 'source\node_modules') | Should Be $false
        Test-Path -LiteralPath (Join-Path $destination 'source\drop.log') | Should Be $false
    }

    It 'recursively honors .tarignore files in the source tree' {
        New-Item -ItemType Directory -Path (Join-Path $source 'nested') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $source '.tarignore') -Value "*.tmp`nignored_dir`n# comment"
        Set-Content -LiteralPath (Join-Path $source 'nested\.tarignore') -Value 'sub_ignored.txt'
        Set-Content -LiteralPath (Join-Path $source 'keep.txt') -Value 'keep me'
        Set-Content -LiteralPath (Join-Path $source 'test.tmp') -Value 'ignore me'
        Set-Content -LiteralPath (Join-Path $source 'nested\sub_keep.txt') -Value 'nested keep'
        Set-Content -LiteralPath (Join-Path $source 'nested\sub_ignored.txt') -Value 'nested ignore'
        New-Item -ItemType Directory -Path (Join-Path $source 'ignored_dir') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $source 'ignored_dir\data.txt') -Value 'deep ignore'
        $destination = Join-Path $testRoot 'tarignore-restored'

        $archive = (Protect-Tar $source $archiveBase).FullName
        Unprotect-Tar -Archive $archive -Destination $destination | Out-Null

        Test-Path -LiteralPath (Join-Path $destination 'source\keep.txt') | Should Be $true
        Test-Path -LiteralPath (Join-Path $destination 'source\test.tmp') | Should Be $false
        Test-Path -LiteralPath (Join-Path $destination 'source\nested\sub_keep.txt') | Should Be $true
        Test-Path -LiteralPath (Join-Path $destination 'source\nested\sub_ignored.txt') | Should Be $false
        Test-Path -LiteralPath (Join-Path $destination 'source\ignored_dir') | Should Be $false
    }

    It 'includes .tarignore-matched files when --no-ignore is passed' {
        New-Item -ItemType Directory -Path (Join-Path $source 'nested') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $source '.tarignore') -Value "*.tmp`nignored_dir`n# comment"
        Set-Content -LiteralPath (Join-Path $source 'nested\.tarignore') -Value 'sub_ignored.txt'
        Set-Content -LiteralPath (Join-Path $source 'keep.txt') -Value 'keep me'
        Set-Content -LiteralPath (Join-Path $source 'test.tmp') -Value 'ignore me'
        Set-Content -LiteralPath (Join-Path $source 'nested\sub_keep.txt') -Value 'nested keep'
        Set-Content -LiteralPath (Join-Path $source 'nested\sub_ignored.txt') -Value 'nested ignore'
        New-Item -ItemType Directory -Path (Join-Path $source 'ignored_dir') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $source 'ignored_dir\data.txt') -Value 'deep ignore'
        $destination = Join-Path $testRoot 'noignore-restored'

        $archive = (Protect-Tar $source $archiveBase --no-ignore).FullName
        Unprotect-Tar -Archive $archive -Destination $destination | Out-Null

        Test-Path -LiteralPath (Join-Path $destination 'source\keep.txt') | Should Be $true
        Test-Path -LiteralPath (Join-Path $destination 'source\test.tmp') | Should Be $true
        Test-Path -LiteralPath (Join-Path $destination 'source\nested\sub_keep.txt') | Should Be $true
        Test-Path -LiteralPath (Join-Path $destination 'source\nested\sub_ignored.txt') | Should Be $true
        Test-Path -LiteralPath (Join-Path $destination 'source\ignored_dir\data.txt') | Should Be $true
    }

    It 'does not publish when the final move fails' {
        $global:CustomShellFailFinalMove = $true
        Mock Move-CustomShellArchiveFile {
            param($SourcePath, $DestinationPath)

            if ($global:CustomShellFailFinalMove) {
                throw 'simulated move failure'
            }
            [IO.File]::Move($SourcePath, $DestinationPath)
        } -ModuleName CustomShell.Commands

        $didThrow = $false
        try {
            Protect-Tar -Source $source -Output $archiveBase | Out-Null
        }
        catch {
            $didThrow = $true
        }

        $didThrow | Should Be $true
        @(Get-ChildItem -LiteralPath $testRoot -Filter 'archive_*.enc').Count | Should Be 0
        @(Get-ChildItem -LiteralPath $testRoot -Force -File |
            Where-Object Name -Match '\.tmp$').Count | Should Be 0
    }

    It 'round-trips an archive into a new destination' {
        $destination = Join-Path $testRoot 'restored'

        $archive = (Protect-Tar -Source $source -Output $archiveBase).FullName
        $result = @(Unprotect-Tar -Archive $archive -Destination $destination)

        $restoredFile = Join-Path $destination 'source\data.txt'
        (Get-Content -LiteralPath $restoredFile -Raw).Trim() | Should Be 'round trip payload'
        $result.Count | Should Be 1
        $result[0].Name | Should Be 'source'
    }

    It 'round-trips a file input with its original name and type' {
        $fileSource = Join-Path $testRoot 'input.txt'
        $destination = Join-Path $testRoot 'file-restored'
        Set-Content -LiteralPath $fileSource -Value 'file payload'

        $archive = (Protect-Tar -Source $fileSource -Output $archiveBase).FullName
        Unprotect-Tar -Archive $archive -Destination $destination | Out-Null

        Test-Path -LiteralPath (Join-Path $destination 'input.txt') -PathType Leaf |
            Should Be $true
        (Get-Content -LiteralPath (Join-Path $destination 'input.txt') -Raw).Trim() |
            Should Be 'file payload'
    }

    It 'rejects a modified authenticated archive before extraction' {
        $destination = Join-Path $testRoot 'tampered-restored'
        $archive = (Protect-Tar -Source $source -Output $archiveBase).FullName
        $archiveBytes = [IO.File]::ReadAllBytes($archive)
        $archiveBytes[80] = $archiveBytes[80] -bxor 1
        [IO.File]::WriteAllBytes($archive, $archiveBytes)

        $didThrow = $false
        try {
            Unprotect-Tar -Archive $archive -Destination $destination | Out-Null
        }
        catch {
            $didThrow = $true
        }

        $didThrow | Should Be $true
        Test-Path -LiteralPath $destination | Should Be $false
    }

    It 'rejects an invalid or non-age archive' {
        $invalidArchive = Join-Path $testRoot 'invalid.enc'
        $destination = Join-Path $testRoot 'invalid-restored'
        Set-Content -LiteralPath $invalidArchive -Value 'not an age archive'

        $didThrow = $false
        try {
            Unprotect-Tar `
                -Archive $invalidArchive `
                -Destination $destination |
                Out-Null
        }
        catch {
            $didThrow = $true
        }

        $didThrow | Should Be $true
        Test-Path -LiteralPath $destination | Should Be $false
    }

    It 'enumerates the current destination after extraction' {
        $destination = Join-Path $testRoot 'restored'
        New-Item -ItemType Directory -Path $destination | Out-Null

        $archive = (Protect-Tar -Source $source -Output $archiveBase).FullName

        Push-Location $destination
        try {
            $result = @(Unprotect-Tar -Archive $archive)
        }
        finally {
            Pop-Location
        }

        $result.Count | Should Be 1
        $result[0].Name | Should Be 'source'
        $result[0].Parent.FullName | Should Be $destination
    }

    It 'merges into an existing directory while preserving unrelated files' {
        $destination = Join-Path $testRoot 'restored'
        $existingSource = Join-Path $destination 'source'
        New-Item -ItemType Directory -Path $existingSource | Out-Null
        Set-Content -LiteralPath (Join-Path $existingSource 'data.txt') -Value 'old payload'
        Set-Content -LiteralPath (Join-Path $existingSource 'keep.txt') -Value 'keep me'

        $archive = (Protect-Tar -Source $source -Output $archiveBase).FullName
        $global:CustomShellCollisionResponse = $true
        Unprotect-Tar -Archive $archive -Destination $destination | Out-Null

        (Get-Content -LiteralPath (Join-Path $existingSource 'data.txt') -Raw).Trim() |
            Should Be 'round trip payload'
        (Get-Content -LiteralPath (Join-Path $existingSource 'keep.txt') -Raw).Trim() |
            Should Be 'keep me'
    }

    It 'leaves a colliding destination unchanged when confirmation is declined' {
        $destination = Join-Path $testRoot 'declined'
        $existingSource = Join-Path $destination 'source'
        New-Item -ItemType Directory -Path $existingSource | Out-Null
        Set-Content -LiteralPath (Join-Path $existingSource 'data.txt') -Value 'existing payload'
        $archive = (Protect-Tar -Source $source -Output $archiveBase).FullName
        $global:CustomShellCollisionResponse = $false

        $didThrow = $false
        try {
            Unprotect-Tar -Archive $archive -Destination $destination | Out-Null
        }
        catch {
            $didThrow = $true
        }

        $didThrow | Should Be $true
        (Get-Content -LiteralPath (Join-Path $existingSource 'data.txt') -Raw).Trim() |
            Should Be 'existing payload'
    }

    It 'rolls back an existing destination when publication fails' {
        $destination = Join-Path $testRoot 'restored'
        $existingSource = Join-Path $destination 'source'
        New-Item -ItemType Directory -Path $existingSource | Out-Null
        Set-Content -LiteralPath (Join-Path $existingSource 'data.txt') -Value 'existing payload'
        Set-Content -LiteralPath (Join-Path $existingSource 'keep.txt') -Value 'keep me'
        $archive = (Protect-Tar -Source $source -Output $archiveBase).FullName
        $global:CustomShellPublishFailed = $false
        $global:CustomShellCollisionResponse = $true

        Mock Move-CustomShellArchiveItem {
            param($SourcePath, $DestinationPath)

            if (
                -not $global:CustomShellPublishFailed -and
                $SourcePath -match '[\\/]candidate[\\/]'
            ) {
                $global:CustomShellPublishFailed = $true
                throw 'simulated publication failure'
            }

            Move-Item `
                -LiteralPath $SourcePath `
                -Destination $DestinationPath `
                -ErrorAction Stop
        } -ModuleName CustomShell.Commands

        $didThrow = $false
        try {
            Unprotect-Tar -Archive $archive -Destination $destination | Out-Null
        }
        catch {
            $didThrow = $true
        }

        $didThrow | Should Be $true
        (Get-Content -LiteralPath (Join-Path $existingSource 'data.txt') -Raw).Trim() |
            Should Be 'existing payload'
        (Get-Content -LiteralPath (Join-Path $existingSource 'keep.txt') -Raw).Trim() |
            Should Be 'keep me'
        @(Get-ChildItem -LiteralPath $testRoot -Force -Directory |
            Where-Object Name -Match '^\.customshell-decode-').Count | Should Be 0
    }

    It 'rejects archive entries that escape the destination' {
        $destination = Join-Path $testRoot 'restored'
        $archive = Join-Path $testRoot 'unsafe.enc'
        New-TestTarGzip -Path $archive -EntryName '../escape.txt'

        $didThrow = $false
        try {
            Unprotect-Tar -Archive $archive -Destination $destination | Out-Null
        }
        catch {
            $didThrow = $true
        }

        $didThrow | Should Be $true
        Test-Path -LiteralPath (Join-Path $testRoot 'escape.txt') | Should Be $false
        Test-Path -LiteralPath $destination | Should Be $false
    }

    It 'rejects archive entries with external symbolic-link targets' {
        $destination = Join-Path $testRoot 'restored'
        $archive = Join-Path $testRoot 'unsafe-link.enc'
        New-TestTarGzip `
            -Path $archive `
            -EntryName 'unsafe-link' `
            -EntryType '2' `
            -LinkName '../escape.txt'

        $didThrow = $false
        try {
            Unprotect-Tar -Archive $archive -Destination $destination | Out-Null
        }
        catch {
            $didThrow = $true
        }

        $didThrow | Should Be $true
        Test-Path -LiteralPath $destination | Should Be $false
        Test-Path -LiteralPath (Join-Path $testRoot 'escape.txt') | Should Be $false
    }

    It 'rejects archive hard-link entries' {
        $destination = Join-Path $testRoot 'restored'
        $archive = Join-Path $testRoot 'unsafe-hard-link.enc'
        New-TestTarGzip `
            -Path $archive `
            -EntryName 'unsafe-hard-link' `
            -EntryType '1' `
            -LinkName '../escape.txt'

        $didThrow = $false
        try {
            Unprotect-Tar -Archive $archive -Destination $destination | Out-Null
        }
        catch {
            $didThrow = $true
        }

        $didThrow | Should Be $true
        Test-Path -LiteralPath $destination | Should Be $false
        Test-Path -LiteralPath (Join-Path $testRoot 'escape.txt') | Should Be $false
    }

    It 'refuses a filesystem root as the extraction destination' {
        $archive = (Protect-Tar -Source $source -Output $archiveBase).FullName
        $rootPath = [IO.Path]::GetPathRoot($testRoot)

        $didThrow = $false
        try {
            Unprotect-Tar -Archive $archive -Destination $rootPath | Out-Null
        }
        catch {
            $didThrow = $true
        }

        $didThrow | Should Be $true
    }
}
