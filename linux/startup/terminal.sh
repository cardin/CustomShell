#!/usr/bin/env bash

# Applies interactive terminal defaults shared by every shell that sources the
# entry point.

# Disable Bash's idle auto-logout. The managed tmux configuration relies on
# panes outliving a timed-out shell (config/tmux.conf), so a positive TMOUT
# would kill them.
export TMOUT=-1
