# ====== CONDA ======
If ($env:CONDA_PATH -and (Test-Path "$env:CONDA_PATH\conda.exe")) { 
    function _lazyLoadConda {
        param($zArgs)
        Remove-Item Function:\conda -ErrorAction SilentlyContinue
        (& "$env:CONDA_PATH\conda.exe" "shell.powershell" "hook") | Out-String | ? { $_ } | Invoke-Expression
        
        & conda @zArgs
    }
    function conda { _lazyLoadConda $args }
}

# ====== FNM ======
if (Get-Command fnm -ErrorAction SilentlyContinue) {
    function _lazyLoadFnm {
        param($zArgs)
        Remove-Item Function:\fnm -ErrorAction SilentlyContinue
        Invoke-Expression (& { (fnm env --shell powershell | Out-String) })
        
        & fnm @zArgs
    }
    function fnm { _lazyLoadFnm $args }
}

# ====== ZOXIDE ======
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    function _lazyLoadZoxide {
        param($CommandName, $zArgs)
        Remove-Item Function:\z, Function:\zi -ErrorAction SilentlyContinue
        Invoke-Expression (& { (zoxide init powershell | Out-String) })

        # --- key bit: promote all __zoxide_ functions to global so they persist ---
        $zoxideFunctions = Get-ChildItem Function:\ | Where-Object { $_.Name -like '__zoxide_*' }
        foreach ($func in $zoxideFunctions) {
            Set-Item Function:\global:$($func.Name) -Value $func.ScriptBlock -Force
        }
        
        & $CommandName @zArgs
    }
    function z { _lazyLoadZoxide 'z'  $args }
    function zi { _lazyLoadZoxide 'zi' $args }
}
