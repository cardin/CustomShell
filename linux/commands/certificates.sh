#!/usr/bin/env bash

# Defines commands for inspecting remote TLS certificate chains.

# list_cert_chain
# Prints the certificate chain presented by HOST on PORT, which defaults to 443.
list_cert_chain() {
    local host="${1:-}"
    local port="${2:-443}"

    if [[ -z "$host" ]]; then
        echo "Usage: list_cert_chain HOST [PORT]"
        return 2
    fi

    if ! command -v gnutls-cli >/dev/null 2>&1; then
        echo "Error: gnutls-cli not found in PATH."
        return 1
    fi

    gnutls-cli -p "$port" --print-cert "$host" --tofu
}
