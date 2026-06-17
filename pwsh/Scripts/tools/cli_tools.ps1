New-Alias pwsh pwsh_x
New-Alias powershell pwsh_x

if (Get-Command coreutils -ErrorAction SilentlyContinue) {
    Remove-Alias rm
    New-Alias rm rm.exe
    
    Remove-Alias ls
    function ls { ls.exe --color=auto @args }
    function ll { ls.exe -la --color=auto @args }
}
else {
    function rmrf { Remove-Item -Recurse -Force $args }

    Remove-Alias ls
    function ls {
        $items = Get-ChildItem @args

        foreach ($item in $items) {
            $style = if ($item.PSIsContainer) {
                $PSStyle.FileInfo.Directory
            }
            elseif ($item.LinkType) {
                $PSStyle.FileInfo.SymbolicLink
            }
            elseif ($item.Extension -in '.exe', '.bat', '.cmd', '.ps1') {
                $PSStyle.FileInfo.Executable
            }
            else {
                ''
            }

            Write-Host "$style$($item.Name)$($PSStyle.Reset)" -NoNewline
            Write-Host "  " -NoNewline
        }

        Write-Host
    }
    New-Alias ll Get-ChildItem
}

New-Alias ping Test-Connection
New-Alias vi vim
New-Alias which Get-Command

# if codex command doesn't already exist, create alias to run codex in WSL
if (!(Get-Command codex -ErrorAction SilentlyContinue)) {
    function cx { wsl bash -lic "codex $args" }
    Set-Alias codex cx
}

if (Get-Command bat -ErrorAction SilentlyContinue) {
    function bat_nonum { bat --style='header,grid' $args }
}

function ssh_get_config {
    # Parse and display SSH config file entries in a table
    param()

    $configPath = Join-Path $HOME ".ssh\config"
    if (-not (Test-Path -LiteralPath $configPath)) {
        Write-Warning "No SSH config file found at $configPath"
        return
    }

    $results = @()
    $currentAliases = @()

    foreach ($raw in Get-Content -LiteralPath $configPath) {
        $line = $raw.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { continue }

        if ($line -match '^(?i)Host\s+(.+)$') {
            $tokens = $Matches[1] -split '\s+'
            foreach ($alias in $tokens) {
                $obj = [pscustomobject]@{
                    Alias    = $alias
                    HostName = $null
                    User     = $null
                    Port     = $null
                }
                $results += $obj
                $currentAliases = @($obj)
            }
            continue
        }

        if ($currentAliases.Count -gt 0) {
            if ($line -match '^(?i)HostName\s+(.+)$') {
                $val = $Matches[1].Trim()
                foreach ($e in $currentAliases) { $e.HostName = $val }
                continue
            }
            if ($line -match '^(?i)User\s+(.+)$') {
                $val = $Matches[1].Trim()
                foreach ($e in $currentAliases) { $e.User = $val }
                continue
            }
            if ($line -match '^(?i)Port\s+(\d+)$') {
                $val = [int]$Matches[1]
                foreach ($e in $currentAliases) { $e.Port = $val }
                continue
            }
        }
    }

    $results |
    Where-Object { $_.Alias -notmatch '[\*\?]' } |
    Sort-Object Alias |
    Format-Table -AutoSize
}

# Git
git config --global credential.helper 'cache --timeout=21600'

# Python
$env:UV_SYSTEM_CERTS = "true"
