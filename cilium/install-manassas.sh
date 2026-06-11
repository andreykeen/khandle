#!/usr/bin/env bash

CILIUM_VERSION="1.19.4"
CLUSTER_NAME="gcore-manassas"
# CLUSTER_NAME="hetzner-helsinki"
# CLUSTER_NAME="hetzner-hillsboro"

echo "Installing Cilium ${CILIUM_VERSION} for ${CLUSTER_NAME}"

helm upgrade --install cilium cilium/cilium \
    --version ${CILIUM_VERSION} \
    --namespace kube-system \
    --force-conflicts \
    --values ./release-${CLUSTER_NAME}.yaml

# helm template cilium cilium/cilium \
#     --version ${CILIUM_VERSION} \
#     --namespace kube-system \
#     --values ./release-${CLUSTER_NAME}.yaml > manifests-${CLUSTER_NAME}.yaml
