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

# Check if CUSTOM_CA_CERT env variable is not set or doesn't point to a valid file
if [[ -z "$CUSTOM_CA_CERT" || ! -f "$CUSTOM_CA_CERT" ]]; then
    echo -e "$Red CUSTOM_CA_CERT is not set or file does not exist!"
else
    export NODE_EXTRA_CA_CERTS="${CUSTOM_CA_CERT}"
    export REQUESTS_CA_BUNDLE="${CUSTOM_CA_CERT}"
fi
