#!/usr/bin/env bash

# Configures Git's global credential cache when Git is installed.

if command -v git >/dev/null 2>&1; then
    git config --global credential.helper 'cache --timeout=21600'
fi
