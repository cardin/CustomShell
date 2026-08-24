#!/usr/bin/env bash

# Adds supported user-local and Linuxbrew command directories to PATH when
# present, without duplicating existing entries.

if [[ ":${PATH:-}:" != *":${HOME:?HOME is not set}/.local/bin:"* ]]; then
    export PATH="$HOME/.local/bin:${PATH:-}"
fi

if [[ -d /home/linuxbrew && ":${PATH:-}:" != *":/home/linuxbrew/.linuxbrew/bin:"* ]]; then
    export PATH="/home/linuxbrew/.linuxbrew/bin:${PATH:-}"
fi
