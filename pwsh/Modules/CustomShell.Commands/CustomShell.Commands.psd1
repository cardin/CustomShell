# Declares metadata and the explicit public surface of the import-safe
# CustomShell.Commands module. Keeping the export list here aligned with the
# root module prevents helper implementation details from becoming public APIs.
@{
    RootModule        = 'CustomShell.Commands.psm1'
    ModuleVersion     = '2.0.0'
    GUID              = '71d73486-9d2c-49ad-a826-49f62b9d99f1'
    Author            = 'CustomShell contributors'
    Description       = 'Reusable PowerShell commands supplied by CustomShell.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Get-SSHConfig'
        'Unprotect-Tar'
        'Protect-Tar'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
