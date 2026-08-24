# Verifies safety behavior for destructive interactive filesystem helpers. Each
# test operates in a unique temporary directory and confirms that protected broad
# targets are rejected while narrow, explicitly supplied paths can be removed.

$aliasScript = Join-Path $PSScriptRoot '..\..\Startup\Set-InteractiveAliases.ps1'

Describe 'Remove-ItemTree' {
    BeforeAll {
        . $aliasScript
    }

    BeforeEach {
        $script:testRoot = Join-Path ([IO.Path]::GetTempPath()) "CustomShell.Tests-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $testRoot | Out-Null
        Set-Content -LiteralPath (Join-Path $testRoot 'payload.txt') -Value 'test'
    }

    AfterEach {
        $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
        $resolvedTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if ($resolvedTestRoot.StartsWith($resolvedTempRoot, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'removes an explicitly supplied narrow directory' {
        Remove-ItemTree -Path $testRoot -Confirm:$false

        Test-Path -LiteralPath $testRoot | Should Be $false
    }

    It 'refuses to remove the filesystem root' {
        $rootPath = [IO.Path]::GetPathRoot($testRoot)
        $didThrow = $false

        try {
            Remove-ItemTree -Path $rootPath -Confirm:$false
        }
        catch {
            $didThrow = $true
        }

        $didThrow | Should Be $true
        Test-Path -LiteralPath $testRoot | Should Be $true
    }
}

Describe 'batx' {
    BeforeAll {
        function global:bat {
            $script:receivedBatArguments = @($args)
        }

        . $aliasScript
    }

    AfterAll {
        Remove-Item -Path Function:\bat -ErrorAction SilentlyContinue
        Remove-Item -Path Function:\batx -ErrorAction SilentlyContinue
    }

    It 'forwards arguments to bat with compact decorations' {
        batx 'example.txt' '--plain'

        ($receivedBatArguments -join '|') | Should Be '--style=header,grid|example.txt|--plain'
    }
}
