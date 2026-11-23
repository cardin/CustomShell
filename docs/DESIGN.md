# CustomShell call flows

These diagrams show selected calls and dependencies in the current code.
For behaviour and options, see [requirements](REQUIREMENTS.md) and
[command contracts](INTERFACES.md).

## Bash startup

```mermaid
sequenceDiagram
    participant Shell as Bash profile
    participant Main as linux/main.sh
    participant Modules as Sourced scripts in the same shell
    participant Files as User environment files
    Shell->>Main: source from managed .bashrc block
    Main->>Modules: core/context.sh, then core/paths.sh
    Main->>Modules: ui/colors.sh and commands/{archive,certificates,utilities}.sh
    opt IS_WSL
        Main->>Modules: platform/wsl.sh
    end
    Main->>Modules: core/portable-env.sh (fill TMPDIR and PROJECTS_* defaults)
    Main->>Modules: startup/certificates.sh, then integrations/tools.sh (zoxide)
    opt Interactive Bash
        Main->>Modules: integrations/prompt.sh, then bind config/inputrc
    end
    Main->>Modules: startup/ssh-agent.sh, then startup/environment-d.sh
    Modules->>Files: customshell_publish_lines writes environment.d and env.sh
    Main->>Modules: startup/terminal.sh, then ui/diagnostics.sh
    opt Interactive, outside tmux, non-dumb TERM, not suppressed, not already shown
        Main->>Modules: Show-Help()
    end
```

Sources: [entry point](../linux/main.sh#L12-L48),
[zoxide initialization](../linux/integrations/tools.sh#L64-L74),
[prompt initialization](../linux/integrations/prompt.sh),
[environment publication](../linux/startup/environment-d.sh#L75-L98).

## PowerShell startup

```mermaid
sequenceDiagram
    participant Profile as CurrentUserAllHosts profile
    participant Main as pwsh/main.ps1
    participant Host as Settings and Win32_Process
    participant Startup as pwsh/Startup scripts (same scope)
    participant Commands as CustomShell.Commands module
    Profile->>Main: dot-source
    Main->>Host: load Settings.psd1 and inspect process ancestry
    Main->>Startup: dot-source Set-InteractiveAliases.ps1
    Main->>Startup: dot-source Initialize-Integrations.ps1 and Initialize-PSReadLine.ps1
    Main->>Startup: dot-source Initialize-Prompt.ps1, then Initialize-Zoxide.ps1
    Main->>Startup: dot-source Show-StartupStatus.ps1
    opt Standalone terminal
        Startup->>Startup: Show-Help()
    end
    Main->>Commands: Import-Module via manifest
    Commands->>Commands: dot-source Archive.ps1 and Ssh.ps1, then export public functions
```

The command module can also be imported without running `pwsh/main.ps1`.
Sources: [entry point](../pwsh/main.ps1#L12-L62),
[startup status](../pwsh/Startup/Show-StartupStatus.ps1#L28-L30),
[command module](../pwsh/Modules/CustomShell.Commands/CustomShell.Commands.psm1).

## Setup and environment ownership

```mermaid
flowchart TD
    subgraph W["Windows installer"]
        WI["pwsh/Install.ps1"]
        WI -->|install| WM["Install-ProfileBlock<br/>Install-PersistentEnvironment<br/>Install-Configs · Install-Clink"]
        WI -->|check| WC["Invoke-Checks"]
        WI -->|uninstall| WU["Uninstall-* counterparts"]
    end
    WM --> WSTATE["PowerShell profile, user environment,<br/>tool settings and install state"]
    subgraph L["Linux installer"]
        LI["linux/install.sh"]
        LI -->|install| LM["write_profile_block · write_posix_profile_block<br/>customshell_shims_link · customshell_git_install"]
        LI -->|check| LC["report_checks"]
        LI -->|uninstall| LU["Remove hooks and shims, restore Git helper,<br/>customshell_environment_uninstall"]
    end
    LM --> RC[".bashrc block: export values and source linux/main.sh"]
    LM --> LP[".profile block: source portable-env.sh and env.sh when readable"]
    LM --> LB[".bashrc and .profile blocks: export BASH_ENV when empty"]
    LB --> NB["linux/noninteractive.sh<br/>paths and portable defaults only"]
    subgraph R["Linux runtime"]
        MAIN["linux/main.sh"] -->|sources| PUB["startup/environment-d.sh"]
    end
    RC --> MAIN
    PUB -->|writes| ENV["env.sh"]
    PUB -->|writes| CONF["90-customshell.conf"]
    LP -->|reads| ENV
    CONF -->|read by| SYSTEMD["systemd user environment"]
```

Installers write hooks for later shells; they do not execute startup as part of
installing. Sources: [PowerShell mode dispatch](../pwsh/Install.ps1#L94-L151),
[Bash hook generation and mode dispatch](../linux/install.sh#L99-L147),
[Linux runtime publisher](../linux/startup/environment-d.sh),
[environment ownership decision](ADR.md#adr-0001-installer-owned-environment-values-runtime-publication).

Non-interactive Bash never loads `linux/main.sh`. The managed blocks export
`BASH_ENV` to
[`linux/noninteractive.sh`](../linux/noninteractive.sh), which composes only
`core/paths.sh` and `core/portable-env.sh`. Keeping it separate is deliberate:
`main.sh` starts the SSH agent, selects a prompt, and may print startup help,
which build tools and agent shells must not see. A launch that runs no profile
at all, such as a Windows to WSL interoperability process, still bypasses both
entry points; see [ADR-0003](ADR.md#adr-0003-non-interactive-bash-environment-through-bash_env).

## Archive commands

```mermaid
flowchart TD
    B["Bash: Protect-Tar / Unprotect-Tar<br/>linux/commands/archive.sh"]
    P["PowerShell: Protect-Tar / Unprotect-Tar<br/>CustomShell.Commands/Archive.ps1"]
    P --> PA["Invoke-CustomShellArchiveCore()"]
    subgraph C["Shared Python process: tools/archive_core.py"]
        MAIN["main()"]
        MAIN -->|creation| CREATE["resolve_output() · list_source()"]
        MAIN -->|extraction| CHECK["validate_destination() · validate_tar()"]
    end
    B -->|python3| MAIN
    PA -->|python3 or python| MAIN
    subgraph T["External tools"]
        GNU["GNU tar"]
        BSD["tar.exe"]
        AGE["age"]
        GIT["Git ignore matcher"]
    end
    B --> GNU
    P --> BSD
    B --> AGE
    P --> AGE
    CREATE -->|directory ignore rules, if enabled| GIT
```

```mermaid
flowchart TD
    CP["Protect-Tar"] --> CV["Validate and list source; resolve output"]
    CV --> CT["tar packs the selected files"]
    CT --> CE["age encrypts to a temporary output"]
    CE --> CW["Shell publishes the archive"]
    XP["Unprotect-Tar"] --> XV["Validate destination"]
    XV --> XD["age decrypts and authenticates"]
    XD --> XC["Python validates archive members"]
    XC --> XT["tar extracts into staging"]
    XT --> XW["Shell checks collisions and publishes or rolls back"]
```

Python owns validation and source selection. The shell front ends call
`tar` and `age` and own staging and publication.
Sources: [Bash front end](../linux/commands/archive.sh),
[PowerShell front end](../pwsh/Modules/CustomShell.Commands/Archive.ps1),
[Python dispatch](../tools/archive_core.py#L415-L493).

## WSL boundary

```mermaid
flowchart TD
    subgraph W["Windows host"]
        PS["PowerShell alias → generated Invoke-Wsl… function"]
        WSL["wsl -e"]
        CMD["cmd.exe"]
        WINSSH["Windows .ssh directory"]
        PS -->|configured alias with no native provider| WSL
    end
    subgraph L["WSL distribution"]
        LOGIN["bash -lic → configured command"]
        MAIN["linux/main.sh"]
        MOD["platform/wsl.sh"]
        BROWSER["Generated BROWSER wrapper"]
        MIRROR["mirror-win-ssh()"]
        COPY["rsync"]
        STAGE["Staged SSH tree"]
        DEST["WSL .ssh directory"]
        MAIN -->|IS_WSL| MOD
        MOD -->|writes if BROWSER is unset and cmd.exe is usable| BROWSER
        MOD -->|defines, does not invoke| MIRROR
        MIRROR -->|when called, after validation| COPY
        COPY -->|writes| STAGE
        MIRROR -->|sets modes on| STAGE
        MIRROR -->|publishes staged tree; restores on failure| DEST
    end
    WSL -->|forwards arguments; suppresses Bash startup help| LOGIN
    MOD -->|queries Windows profile if USERPROFILE is missing and tools are available| CMD
    BROWSER -->|when invoked, opens the default Windows browser| CMD
    WINSSH -->|read by| COPY
```

Sources: [PowerShell wrapper](../pwsh/Startup/Set-InteractiveAliases.ps1#L76-L133),
[WSL startup helpers](../linux/platform/wsl.sh#L12-L75),
[mirror call](../linux/platform/wsl.sh#L110-L204).
