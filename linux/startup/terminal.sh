#!/usr/bin/env bash

# Applies interactive terminal defaults shared by every shell that sources the
# entry point.

# Disable Bash's idle auto-logout so long-lived interactive shells, including
# those inside tmux panes, are not killed after a period of inactivity.
export TMOUT=-1
