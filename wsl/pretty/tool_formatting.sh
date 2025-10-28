#!/usr/bin/env bash
my_local_dir=$(dirname "${BASH_SOURCE[0]}")

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
export FZF_DEFAULT_OPTS="--preview 'bat --color=always {}'"
export FZF_DEFAULT_COMMAND="fd --type f"
export FZF_CTRL_T_OPTS="
  --walker-skip .git,node_modules,target
  --preview 'bat -n --color=always {}'
  --bind 'ctrl-/:change-preview-window(down|hidden|)'"

# === starship ===
if command -v starship &>/dev/null; then
    function set_win_title() {
        echo -ne "\033]0;$(basename "$PWD")\007"
    }
    # shellcheck disable=SC2034
    export starship_precmd_user_func="set_win_title"

    # shellcheck disable=SC2155
    export STARSHIP_CONFIG=$(realpath "$my_local_dir/../../starship.toml")
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
    export PATH="$HOME/.local/bin:$PATH"
    eval "$(zoxide init bash)"
fi
