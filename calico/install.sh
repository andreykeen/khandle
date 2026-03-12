#!/usr/bin/env bash

VALUES_FILE=$1

if [[ -z "$VALUES_FILE" || ! -f "$VALUES_FILE" ]]; then
    echo "VALUES_FILE is not set or does not exist"
    exit 1
fi

helm upgrade --install calico projectcalico/tigera-operator \
    --version v3.31.0 \
    --namespace tigera-operator \
    --create-namespace \
    --values ./${VALUES_FILE}
