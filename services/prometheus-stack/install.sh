#!/usr/bin/env bash

PROMETHEUS_STACK_VERSION="79.4.1"

helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack \
    --version ${PROMETHEUS_STACK_VERSION} \
    --namespace monitoring --create-namespace \
    --values ./release.yaml
