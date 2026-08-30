# Initializes zoxide after the selected prompt engine so zoxide can wrap the
# final prompt function and keep its directory-tracking hook active.

if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    if (
        (Get-Variable __zoxide_hooked -Scope Global -ErrorAction SilentlyContinue -ValueOnly) -eq 1 -and
        $function:prompt -notmatch '\b__zoxide_hook\b'
    ) {
        $global:__zoxide_hooked = 0
    }

    $zoxideInitialization = zoxide init powershell 2>$null | Out-String
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($zoxideInitialization)) {
        Invoke-Expression $zoxideInitialization
    }
}
