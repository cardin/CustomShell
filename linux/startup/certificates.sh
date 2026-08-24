#!/usr/bin/env bash

# Applies the configured custom CA certificate to Node.js and Python tooling on
# detected work devices.

if [[ "$IS_WORK_DEVICE" == true ]]; then
    if [[ -z ${CUSTOM_CA_CERT:-} || ! -f "$CUSTOM_CA_CERT" ]]; then
        echo -e "${Red}CUSTOM_CA_CERT is not set or file does not exist!"
    else
        export NODE_EXTRA_CA_CERTS="$CUSTOM_CA_CERT"
        export REQUESTS_CA_BUNDLE="$CUSTOM_CA_CERT"
    fi
fi
