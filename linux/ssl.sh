#!/usr/bin/env bash

function list_cert_chain() {
    host="${1:-}"
    port="${2:-443}"

    if [[ -z "$host" ]]; then
        echo "Usage: list_cert_chain HOST [PORT]"
        return 2
    fi
    gnutls-cli -p "$port" --print-cert "$host" --tofu
}

# Apply custom CA certs only on work devices.
if [[ "$IS_WORK_DEVICE" == "true" ]]; then
    if [[ -z "$CUSTOM_CA_CERT" || ! -f "$CUSTOM_CA_CERT" ]]; then
        echo -e "${Red}CUSTOM_CA_CERT is not set or file does not exist!"
    else
        export NODE_EXTRA_CA_CERTS="${CUSTOM_CA_CERT}"
        export REQUESTS_CA_BUNDLE="${CUSTOM_CA_CERT}"
    fi
fi
