@echo off
:::::: FNM
:: for /F will launch a new instance of cmd so we create a guard to prevent an infnite loop
if not defined FNM_AUTORUN_GUARD (
    set "FNM_AUTORUN_GUARD=AutorunGuard"
    FOR /f "tokens=*" %%z IN ('fnm env --use-on-cd') DO CALL %%z
)

:::::: manShel
echo ##########
echo - conda ^| pipx ^| node
echo - z[i] ^| bat[diff] ^| nvitop ^| vim
echo - rg ^<regex^> [--glob ..] [--type ^<py^>] [--no-ignore] [--hidden] [--max-depth ..]
echo     [-l] [-B^|A^|C ^<int^>] [^<path^> ...]
echo - fd ^<regex^> [--glob ..] [--type d^|f] [--no-ignore] [--hidden] [--max^|min-depth ..]
echo     [--full-path] [-e ^<py^>] [^<targetDir^>] [--exec ^<cmd^> {} /;]
echo - ssh [-p ^<port^>] [-NT] [-L [^<local^>:]^<port^>:^<remote^>:^<port^>] [-J ^<user^>@^<hop1^>] ^<user^>@^<hop2^>
echo - %%USERPROFILE%%
