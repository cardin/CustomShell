$tarEncScript = Join-Path $PSScriptRoot '..\Scripts\tools\TarEnc.ps1'

function New-MockOpenSsl {
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
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $EntryName,

        [string] $Content = 'test payload'
    )

    $header = New-Object byte[] 512
    [Text.Encoding]::ASCII.GetBytes($EntryName).CopyTo($header, 0)
    Set-TarOctalField $header 100 8 420
    Set-TarOctalField $header 108 8 0
    Set-TarOctalField $header 116 8 0
    $contentBytes = [Text.Encoding]::UTF8.GetBytes($Content)
    Set-TarOctalField $header 124 12 $contentBytes.Length
    Set-TarOctalField $header 136 12 0

    for ($index = 148; $index -lt 156; $index++) {
        $header[$index] = 32
    }

    $header[156] = [byte][char]'0'
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

Describe 'TarEnc and UnTarEnc' {
    BeforeEach {
        $script:testRoot = Join-Path ([IO.Path]::GetTempPath()) "CustomShell.Tests-$([guid]::NewGuid())"
        $script:source = Join-Path $testRoot 'source'
        $script:mockBin = Join-Path $testRoot 'bin'
        $script:archive = Join-Path $testRoot 'archive.enc'
        $script:originalPath = $env:PATH

        New-Item -ItemType Directory -Path $source, $mockBin | Out-Null
        Set-Content -LiteralPath (Join-Path $source 'data.txt') -Value 'round trip payload'
        New-MockOpenSsl -Directory $mockBin
        $env:PATH = "$mockBin;$originalPath"
        Remove-Item Env:MOCK_OPENSSL_FAIL -ErrorAction SilentlyContinue
        . $tarEncScript
    }

    AfterEach {
        $env:PATH = $originalPath
        Remove-Item Env:MOCK_OPENSSL_FAIL -ErrorAction SilentlyContinue

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
            TarEnc -Source $source -Output $archive -Force | Out-Null
        }
        catch {
            $didThrow = $true
        }

        $didThrow | Should Be $true
        (Get-Content -LiteralPath $archive -Raw).Trim() | Should Be 'existing archive'
    }

    It 'replaces an existing archive without leaving replacement files' {
        Set-Content -LiteralPath $archive -Value 'existing archive'

        TarEnc -Source $source -Output $archive -Force | Out-Null

        (Get-Content -LiteralPath $archive -Raw).Trim() | Should Not Be 'existing archive'
        @(Get-ChildItem -LiteralPath $testRoot -Force -File |
            Where-Object Name -Match '\.(tmp|bak)$').Count | Should Be 0
    }

    It 'round-trips an archive into a new destination' {
        $destination = Join-Path $testRoot 'restored'

        TarEnc -Source $source -Output $archive | Out-Null
        $result = @(UnTarEnc -Archive $archive -Destination $destination)

        $restoredFile = Join-Path $destination 'source\data.txt'
        (Get-Content -LiteralPath $restoredFile -Raw).Trim() | Should Be 'round trip payload'
        $result.Count | Should Be 1
        $result[0].Name | Should Be 'source'
    }

    It 'enumerates the current destination after extraction' {
        $destination = Join-Path $testRoot 'restored'
        New-Item -ItemType Directory -Path $destination | Out-Null

        TarEnc -Source $source -Output $archive | Out-Null

        Push-Location $destination
        try {
            $result = @(UnTarEnc -Archive $archive)
        }
        finally {
            Pop-Location
        }

        $result.Count | Should Be 1
        $result[0].Name | Should Be 'source'
        $result[0].Parent.FullName | Should Be $destination
    }

    It 'rejects archive entries that escape the destination' {
        $destination = Join-Path $testRoot 'restored'
        New-TestTarGzip -Path $archive -EntryName '../escape.txt'

        $didThrow = $false
        try {
            UnTarEnc -Archive $archive -Destination $destination | Out-Null
        }
        catch {
            $didThrow = $true
        }

        $didThrow | Should Be $true
        Test-Path -LiteralPath (Join-Path $testRoot 'escape.txt') | Should Be $false
        Test-Path -LiteralPath $destination | Should Be $false
    }
}
