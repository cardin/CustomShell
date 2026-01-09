#!/usr/bin/env bash
TOOLACTIVATION_SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")

# === batcat ===
if command -v batcat &>/dev/null; then
    alias bat="batcat"
fi
if command -v bat &>/dev/null; then
    export MANPAGER="sh -c 'col -bx | bat -l man -p'"
fi

# === fd-find ===
if command -v fdfind &>/dev/null; then
    alias fd="fdfind"
fi

# === fzf ===
if command -v fzf &>/dev/null; then
    export FZF_DEFAULT_OPTS="--preview 'bat --color=always {}'"
    export FZF_DEFAULT_COMMAND="fd --type f"
    export FZF_CTRL_T_OPTS="
    --walker-skip .git,node_modules,target
    --preview 'bat -n --color=always {}'
    --bind 'ctrl-/:change-preview-window(down|hidden|)'"
fi

# === Oh My Posh ===
if [ "$PRETTY_PROMPT" = "ohmyposh" ] && command -v oh-my-posh &>/dev/null; then
    if [ "$IS_BARE_TERMINAL" = true ]; then
        export OMP_THEME="ascii"
    else
        export OMP_THEME="catppuccin_gruvbox"
    fi
    eval "$(oh-my-posh init bash --config "$TOOLACTIVATION_SCRIPT_DIR/../../themes/omp/$OMP_THEME.json")"
fi

# === starship ===
if [ "$PRETTY_PROMPT" = "starship" ] && command -v starship &>/dev/null; then
    function set_win_title() {
        echo -ne "\033]0;$(basename "$PWD")\007"
    }
    # shellcheck disable=SC2034
    export starship_precmd_user_func="set_win_title"

    eval "$(starship init bash)"
fi

# === fnm ===
FNM_PATH="$HOME/.local/share/fnm"
if [ -d "$FNM_PATH" ]; then
    export PATH="$FNM_PATH:$PATH"
    eval "$(fnm env)"
    # eval "$(fnm env --version-file-strategy=recursive --shell bash)"
    #  --use-on-cd not needed if don't care about auto-switching versions on cd
fi

# === zoxide ===
if command -v zoxide &>/dev/null; then
    eval "$(zoxide init bash)"
fi
