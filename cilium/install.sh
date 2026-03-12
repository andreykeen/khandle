#!/usr/bin/env bash

CILIUM_VERSION="1.18.2"

helm upgrade --install cilium cilium/cilium \
    --version ${CILIUM_VERSION} \
    --namespace kube-system \
    --values ./release.yaml
