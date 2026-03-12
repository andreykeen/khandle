#!/bin/bash

# helm upgrade --install metrics-server metrics-server/metrics-server \
#     --namespace kube-system \
#     --values values.metrics-server.yaml

# helm upgrade --install kube-prometheus-stack oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack \
#     --namespace monitoring --create-namespace \
#     --values values.kube-prometheus-stack.yaml

helm upgrade --install vpa fairwinds-stable/vpa \
    --namespace vpa --create-namespace \
    --values values.vpa.yaml
