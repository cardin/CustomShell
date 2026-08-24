#!/usr/bin/env bash

# Initializes the selected optional prompt engine for an interactive Bash
# session. Empty or failed initialization output is ignored.

if [[ "$PRETTY_PROMPT" == ohmyposh && ${CUSTOMSHELL_OMP_INITIALIZED:-false} != true ]] && command -v oh-my-posh >/dev/null 2>&1; then
    if [[ "$IS_BARE_TERMINAL" == true ]]; then
        export OMP_THEME="ascii"
    else
        export OMP_THEME="catppuccin_gruvbox"
    fi

    if prompt_init="$(oh-my-posh init bash --config "$PROJ_DIR/config/omp/$OMP_THEME.json" 2>/dev/null)" && \
        [[ -n "$prompt_init" ]] && bash -n <<<"$prompt_init" 2>/dev/null; then
        if eval "$prompt_init" 2>/dev/null; then
            export CUSTOMSHELL_OMP_INITIALIZED=true
        fi
    fi
    unset prompt_init
fi

if [[ "$PRETTY_PROMPT" == starship && ${CUSTOMSHELL_STARSHIP_INITIALIZED:-false} != true ]] && command -v starship >/dev/null 2>&1; then
    # set_win_title
    # Sets the terminal title to the basename of the current directory.
    set_win_title() {
        echo -ne "\033]0;$(basename "$PWD")\007"
    }
    export starship_precmd_user_func="set_win_title"

    if prompt_init="$(starship init bash 2>/dev/null)" && [[ -n "$prompt_init" ]] && \
        bash -n <<<"$prompt_init" 2>/dev/null; then
        if eval "$prompt_init" 2>/dev/null; then
            export CUSTOMSHELL_STARSHIP_INITIALIZED=true
        fi
    fi
    unset prompt_init
fi
