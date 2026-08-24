#!/usr/bin/env bash

# Configures aliases, environment variables, and initialization hooks for
# optional command-line tools when they are available.

if command -v batcat >/dev/null 2>&1; then
    alias bat="batcat"
fi
if command -v bat >/dev/null 2>&1; then
    export MANPAGER="sh -c 'col -bx | bat -l man -p'"
    export BAT_CONFIG_PATH="$PROJ_DIR/config/bat.conf"
    alias batx="bat --style=header,grid"
fi
if command -v fdfind >/dev/null 2>&1; then
    alias fd="fdfind"
fi

FNM_PATH="$HOME/.local/share/fnm"
if [[ -d "$FNM_PATH" && ${CUSTOMSHELL_FNM_INITIALIZED:-false} != true ]]; then
    export FNM_PATH
    if [[ ":$PATH:" != *":$FNM_PATH:"* ]]; then
        export PATH="$FNM_PATH:$PATH"
    fi
    if fnm_init="$(fnm env 2>/dev/null)" && [[ -n "$fnm_init" ]] && \
        bash -n <<<"$fnm_init" 2>/dev/null; then
        if eval "$fnm_init" 2>/dev/null; then
            export CUSTOMSHELL_FNM_INITIALIZED=true
        fi
    fi
    unset fnm_init
fi

if command -v fzf >/dev/null 2>&1; then
    if command -v bat >/dev/null 2>&1 || command -v batcat >/dev/null 2>&1; then
        export FZF_DEFAULT_OPTS="--preview 'bat --color=always {}'"
        export FZF_CTRL_T_OPTS="
        --walker-skip .git,node_modules,target
        --preview 'bat -n --color=always {}'
        --bind 'ctrl-/:change-preview-window(down|hidden|)'"
    else
        export FZF_CTRL_T_OPTS="--walker-skip .git,node_modules,target"
    fi
    if command -v fd >/dev/null 2>&1 || command -v fdfind >/dev/null 2>&1; then
        export FZF_DEFAULT_COMMAND="fd --type f"
    fi
fi

if command -v lazydocker >/dev/null 2>&1; then
    # lazydocker
    # Runs LazyDocker with the repository's shared configuration directory.
    lazydocker() {
        XDG_CONFIG_HOME="$PROJ_DIR/config" command lazydocker "$@"
    }
fi
if command -v lazygit >/dev/null 2>&1; then
    export LG_CONFIG_FILE="$PROJ_DIR/config/lazygit/config.yml"
fi
if command -v tmux >/dev/null 2>&1; then
    alias tmux="tmux -f \$PROJ_DIR/config/tmux.conf"
fi
if command -v zoxide >/dev/null 2>&1 && [[ ${CUSTOMSHELL_ZOXIDE_INITIALIZED:-false} != true ]]; then
    if zoxide_init="$(zoxide init bash 2>/dev/null)" && [[ -n "$zoxide_init" ]] && \
        bash -n <<<"$zoxide_init" 2>/dev/null; then
        if eval "$zoxide_init" 2>/dev/null; then
            export CUSTOMSHELL_ZOXIDE_INITIALIZED=true
        fi
    fi
    unset zoxide_init
fi
