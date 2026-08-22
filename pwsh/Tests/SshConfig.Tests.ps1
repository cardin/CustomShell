$cliToolsScript = Join-Path $PSScriptRoot '..\Scripts\tools\cli_tools.ps1'

function Import-SshGetConfigFunction {
    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile(
        $cliToolsScript,
        [ref] $tokens,
        [ref] $errors
    )

    if ($errors.Count -gt 0) {
        throw ($errors.Message -join [Environment]::NewLine)
    }

    $functionAst = $ast.Find(
        {
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'ssh_get_config'
        },
        $true
    )

    if (-not $functionAst) {
        throw 'Could not find ssh_get_config in cli_tools.ps1.'
    }

    . ([scriptblock]::Create($functionAst.Extent.Text))
}

Describe 'ssh_get_config' {
    BeforeAll {
        Import-SshGetConfigFunction
    }

    BeforeEach {
        $script:testRoot = Join-Path ([IO.Path]::GetTempPath()) "CustomShell.Tests-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $testRoot | Out-Null
        $script:configPath = Join-Path $testRoot 'config'
    }

    AfterEach {
        $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
        $resolvedTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if ($resolvedTestRoot.StartsWith($resolvedTempRoot, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'applies a Host block to every alias declared on the Host line' {
        @'
Host alpha beta
    HostName example.test
    User deploy
    Port 2222
Host *
    User fallback
'@ | Set-Content -LiteralPath $configPath

        $result = @(ssh_get_config -ConfigPath $configPath)

        $result.Count | Should Be 2
        $result[0].Alias | Should Be 'alpha'
        $result[1].Alias | Should Be 'beta'
        foreach ($entry in $result) {
            $entry.HostName | Should Be 'example.test'
            $entry.User | Should Be 'deploy'
            $entry.Port | Should Be 2222
        }
    }

    It 'returns no entries when the SSH config is missing' {
        $result = @(ssh_get_config -ConfigPath $configPath 3>$null)

        $result.Count | Should Be 0
    }
}
