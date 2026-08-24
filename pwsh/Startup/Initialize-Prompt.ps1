# Initializes the prompt engine selected in CustomShell settings when its command
# is installed. Starship and Oh My Posh output is evaluated only after successful,
# non-empty initialization, while the `none` option leaves the prompt unchanged.

switch ($customShellSettings.Prompt) {
    'none' {
        break
    }
    'starship' {
        if (-not (Get-Command starship -ErrorAction SilentlyContinue)) {
            break
        }

        $env:STARSHIP_UPDATE_CHECK = 'false'

        function global:Invoke-Starship-PreCommand {
            <#
            .SYNOPSIS
            Updates the terminal title before Starship renders a prompt.

            .DESCRIPTION
            Sets the current terminal window title to the leaf name of the
            working directory. Starship calls this hook immediately before it
            renders each prompt so the title follows location changes.
            #>
            $host.UI.RawUI.WindowTitle = [IO.Path]::GetFileName($PWD)
        }

        $promptInitialization = starship init powershell --print-full-init 2>$null | Out-String
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($promptInitialization)) {
            Invoke-Expression $promptInitialization
        }
    }
    'ohmyposh' {
        if (-not (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
            break
        }

        $themeName = if ($customShellState.IsStandaloneTerminal) {
            'catppuccin_gruvbox.json'
        }
        else {
            'ascii.json'
        }
        $themePath = Join-Path $PSScriptRoot "../../config/omp/$themeName"
        $promptInitialization = oh-my-posh init pwsh --config $themePath 2>$null | Out-String

        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($promptInitialization)) {
            Invoke-Expression $promptInitialization
        }
    }
    default {
        Write-Warning "Unknown CustomShell prompt selection: $($customShellSettings.Prompt)"
    }
}
