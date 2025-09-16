##########################################
# Install CNI
##########################################
function cni_manage() {
    local node="$1"

    local cni_calico=$(yq e '.cluster_network.cni.calico' "$NODES_FILE")
    if [ "$cni_calico" != "null" ] && [ -n "$cni_calico" ]; then
        cni_calico_install $hostname
    fi
}


##########################################
# Install Calico
##########################################
function cni_calico_install() {
    local node="$1"

    local calico_values=$(yq e '.cluster_network.cni.calico.values' "$NODES_FILE")
    if [ "$calico_values" = "null" ] || [ -z "$calico_values" ]; then
        print_status "info" "Calico config is not set in the manifest"
        return
    fi

    local calico_version=$(yq e '.cluster_network.cni.calico.version' "$NODES_FILE")
    local calico_version_arg=""
    if [ "$calico_version" != "null" ] && [ -n "$calico_version" ]; then
        calico_version_arg="--version $calico_version"
    else
        print_status "warning" "Calico version is not set in the manifest. Using latest version"
        calico_version="latest"
    fi

    run_commands_on_node $node "sudo helm --kubeconfig /etc/kubernetes/admin.conf --namespace tigera-operator list --no-headers"
    if [ -z "$RETURN_OUTPUT" ]; then
        print_status "info" "Installing Calico $calico_version version on node $node"

        run_commands_on_node $node "sudo tee /tmp/calico-values.yaml > /dev/null <<EOF
---
$calico_values
EOF"

        run_commands_on_node $node "sudo helm repo add projectcalico https://docs.tigera.io/calico/charts && sudo helm repo update"
        run_commands_on_node $node "sudo helm install calico projectcalico/tigera-operator \
            --kubeconfig /etc/kubernetes/admin.conf \
            $calico_version_arg \
            --namespace tigera-operator \
            --create-namespace \
            --values /tmp/calico-values.yaml"
    else
        print_status "info" "Calico is already installed on node $node"
    fi
}
