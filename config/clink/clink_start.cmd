@echo off
:::::: FNM
:: for /F will launch a new instance of cmd so we create a guard to prevent an infnite loop
if not defined FNM_AUTORUN_GUARD (
    set "FNM_AUTORUN_GUARD=AutorunGuard"
    FOR /f "tokens=*" %%z IN ('fnm env --use-on-cd') DO CALL %%z
)

:: Create useful aliases (doskey)
where coreutils >nul 2>&1 && (
    doskey rm=rm.exe $*
    doskey ls=ls.exe --color=auto $*
    doskey ll=ls.exe -la --color=auto $*
) || (
    doskey rm=del $*
    doskey ls=dir /B $*
    doskey ll=dir $*
    doskey grep=findstrs
)
doskey pwsh=pwsh_x
doskey powershell=pwsh_x

:: If bat exists
where bat >nul 2>&1 && (
    doskey bat_nonum=bat --style=header,grid $*
)
