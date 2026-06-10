#!/usr/bin/env bash
# Generate a env conf file into shell config
ENV_DIR="$HOME/.config/environment.d"
ENV_FILE="$ENV_DIR/90-customshell.conf"

FILE_ENVS=(
    "REQUESTS_CA_BUNDLE"
    "NODE_EXTRA_CA_CERTS"
)
VALUE_ENVS=("GTK_OVERLAY_SCROLLING")

# Create and Empty the file
mkdir -p "$ENV_DIR"
: >"$ENV_FILE"

for env in "${FILE_ENVS[@]}"; do
    if [[ -n "${!env+x}" && -f "${!env}" ]]; then
        echo "$env=${!env}" >>"$ENV_FILE"
    fi
done

for env in "${VALUE_ENVS[@]}"; do
    var_name="${env%%=*}"
    if [[ -n "${!var_name+x}" ]]; then
        echo "$var_name=${!var_name}" >>"$ENV_FILE"
    fi
done
