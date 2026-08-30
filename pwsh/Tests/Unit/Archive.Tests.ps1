# Verifies protected archive replacement, cleanup, round trips, and traversal
# rejection. The suite uses unique temporary directories and a local OpenSSL
# shim so it never prompts for credentials or contacts external services.
$modulePath = Join-Path $PSScriptRoot '..\..\Modules\CustomShell.Commands\CustomShell.Commands.psd1'

function New-MockOpenSsl {
    <#
    .SYNOPSIS
    Creates a controllable OpenSSL command shim for archive tests.

    .DESCRIPTION
    Writes a local command that copies the requested input to output, emulating
    the file flow expected by the archive commands. An environment flag can
    force a nonzero exit code for failure and preservation tests.
    #>
    param(
        [Parameter(Mandatory)]
        [string] $Directory
    )

    $mockPath = Join-Path $Directory 'openssl.cmd'
    @'
@echo off
if "%MOCK_OPENSSL_FAIL%"=="1" exit /b 9
set "input="
set "output="
:parse
if "%~1"=="" goto copy
if /I "%~1"=="-in" (
  set "input=%~2"
  shift
  shift
  goto parse
)
if /I "%~1"=="-out" (
  set "output=%~2"
  shift
  shift
  goto parse
)
shift
goto parse
:copy
copy /y "%input%" "%output%" >nul
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

        $fileStream = [IO.File]::Create($Path)
        try {
            $gzipStream = New-Object IO.Compression.GZipStream(
                $fileStream,
                [IO.Compression.CompressionMode]::Compress
            )
            try {
                $tarStream.CopyTo($gzipStream)
            }
            finally {
                $gzipStream.Dispose()
            }
        }
        finally {
            $fileStream.Dispose()
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

    It 'shows Protect-Tar help with -h without requiring a source' {
        $helpText = Protect-Tar -h | Out-String

        $helpText | Should Match 'USAGE'
        $helpText | Should Match 'Protect-Tar <source_directory>'
        $helpText | Should Match '600,000 iterations'
    }

    It 'shows Unprotect-Tar help with -h without requiring an archive' {
        $helpText = Unprotect-Tar -h | Out-String

        $helpText | Should Match 'USAGE'
        $helpText | Should Match 'Unprotect-Tar <archive.tar.gz.enc>'
        $helpText | Should Match 'transactional extraction'
    }

    BeforeEach {
        $script:testRoot = Join-Path ([IO.Path]::GetTempPath()) "CustomShell.Tests-$([guid]::NewGuid())"
        $script:source = Join-Path $testRoot 'source'
        $script:mockBin = Join-Path $testRoot 'bin'
        $script:archive = Join-Path $testRoot 'archive.enc'
        $script:originalPath = $env:PATH
        $script:originalPathExt = $env:PATHEXT

        New-Item -ItemType Directory -Path $source, $mockBin | Out-Null
        Set-Content -LiteralPath (Join-Path $source 'data.txt') -Value 'round trip payload'
        New-MockOpenSsl -Directory $mockBin
        $env:PATHEXT = '.COM;.EXE;.BAT;.CMD'
        $env:PATH = "$mockBin;$originalPath"
        Remove-Item Env:MOCK_OPENSSL_FAIL -ErrorAction SilentlyContinue
    }

    AfterEach {
        $env:PATH = $originalPath
        $env:PATHEXT = $originalPathExt
        Remove-Item Env:MOCK_OPENSSL_FAIL -ErrorAction SilentlyContinue
        Remove-Variable `
            -Name CustomShellMoveCall, CustomShellPublishFailed `
            -Scope Global `
            -ErrorAction SilentlyContinue

        $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
        $resolvedTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if ($resolvedTestRoot.StartsWith($resolvedTempRoot, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'preserves an existing archive when forced encryption fails' {
        Set-Content -LiteralPath $archive -Value 'existing archive'
        $env:MOCK_OPENSSL_FAIL = '1'

        $didThrow = $false
        try {
            Protect-Tar -Source $source -Output $archive -Force | Out-Null
        }
        catch {
            $didThrow = $true
        }

        $didThrow | Should Be $true
        (Get-Content -LiteralPath $archive -Raw).Trim() | Should Be 'existing archive'
    }

    It 'replaces an existing archive without leaving replacement files' {
        Set-Content -LiteralPath $archive -Value 'existing archive'

        Protect-Tar -Source $source -Output $archive -Force | Out-Null

        (Get-Content -LiteralPath $archive -Raw).Trim() | Should Not Be 'existing archive'
        @(Get-ChildItem -LiteralPath $testRoot -Force -File |
            Where-Object Name -Match '\.(tmp|bak)$').Count | Should Be 0
    }

    It 'preserves the backup when publishing and restoration both fail' {
        Set-Content -LiteralPath $archive -Value 'existing archive'
        $global:CustomShellMoveCall = 0

        Mock Move-CustomShellArchiveFile {
            param($SourcePath, $DestinationPath)

            $global:CustomShellMoveCall++
            if ($global:CustomShellMoveCall -gt 1) {
                throw 'simulated move failure'
            }

            [IO.File]::Move($SourcePath, $DestinationPath)
        } -ModuleName CustomShell.Commands

        $didThrow = $false
        try {
            Protect-Tar -Source $source -Output $archive -Force | Out-Null
        }
        catch {
            $didThrow = $true
        }

        $didThrow | Should Be $true
        Test-Path -LiteralPath $archive | Should Be $false
        $backups = @(Get-ChildItem -LiteralPath $testRoot -Force -File |
            Where-Object Name -Match '\.bak$')
        $backups.Count | Should Be 1
        (Get-Content -LiteralPath $backups[0].FullName -Raw).Trim() |
            Should Be 'existing archive'
        @(Get-ChildItem -LiteralPath $testRoot -Force -File |
            Where-Object Name -Match '\.tmp$').Count | Should Be 0
    }

    It 'round-trips an archive into a new destination' {
        $destination = Join-Path $testRoot 'restored'

        Protect-Tar -Source $source -Output $archive | Out-Null
        $result = @(Unprotect-Tar -Archive $archive -Destination $destination)

        $restoredFile = Join-Path $destination 'source\data.txt'
        (Get-Content -LiteralPath $restoredFile -Raw).Trim() | Should Be 'round trip payload'
        $result.Count | Should Be 1
        $result[0].Name | Should Be 'source'
    }

    It 'enumerates the current destination after extraction' {
        $destination = Join-Path $testRoot 'restored'
        New-Item -ItemType Directory -Path $destination | Out-Null

        Protect-Tar -Source $source -Output $archive | Out-Null

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

        Protect-Tar -Source $source -Output $archive | Out-Null
        Unprotect-Tar -Archive $archive -Destination $destination | Out-Null

        (Get-Content -LiteralPath (Join-Path $existingSource 'data.txt') -Raw).Trim() |
            Should Be 'round trip payload'
        (Get-Content -LiteralPath (Join-Path $existingSource 'keep.txt') -Raw).Trim() |
            Should Be 'keep me'
    }

    It 'rolls back an existing destination when publication fails' {
        $destination = Join-Path $testRoot 'restored'
        $existingSource = Join-Path $destination 'source'
        New-Item -ItemType Directory -Path $existingSource | Out-Null
        Set-Content -LiteralPath (Join-Path $existingSource 'data.txt') -Value 'existing payload'
        Set-Content -LiteralPath (Join-Path $existingSource 'keep.txt') -Value 'keep me'
        Protect-Tar -Source $source -Output $archive | Out-Null
        $global:CustomShellPublishFailed = $false

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
        Protect-Tar -Source $source -Output $archive | Out-Null
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
