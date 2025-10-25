#!/usr/bin/env bash

function list_cert_chain() {
    host="${1:-}"
    port="${2:-443}"

    if [[ -z "$host" ]]; then
        echo "Usage: $0 HOST [PORT]"
        return 2
    fi
    gnutls-cli -p "$port" --print-cert "$host" --tofu
}
