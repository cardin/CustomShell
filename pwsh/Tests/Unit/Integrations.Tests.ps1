# Verifies that optional startup integrations tolerate unavailable or empty
# provider output without interrupting profile startup.

Describe 'optional PowerShell integrations' {
    BeforeAll {
        $script:integrationScript = (Resolve-Path (
                Join-Path $PSScriptRoot '..\..\Startup\Initialize-Integrations.ps1')).Path
    }

    BeforeEach {
        $script:originalTermProgram = $env:TERM_PROGRAM
        $script:originalCondaPath = $env:CONDA_PATH
        $env:TERM_PROGRAM = 'vscode'
        Remove-Item Env:CONDA_PATH -ErrorAction SilentlyContinue
        function global:code {
            $global:LASTEXITCODE = 0
        }
    }

    AfterEach {
        if ($null -eq $script:originalTermProgram) {
            Remove-Item Env:TERM_PROGRAM -ErrorAction SilentlyContinue
        }
        else {
            $env:TERM_PROGRAM = $script:originalTermProgram
        }
        if ($null -eq $script:originalCondaPath) {
            Remove-Item Env:CONDA_PATH -ErrorAction SilentlyContinue
        }
        else {
            $env:CONDA_PATH = $script:originalCondaPath
        }
        Remove-Item Function:\global:code -ErrorAction SilentlyContinue
    }

    It 'ignores an empty VS Code shell-integration path' {
        { . $script:integrationScript } | Should -Not -Throw
    }
}
