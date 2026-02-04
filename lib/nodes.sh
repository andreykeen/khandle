##########################################
# Install the cluster
##########################################
function nodes_install_cluster() {

    local control_plane_nodes=$(manifest_read_yaml "[.nodes[] | select(.control_plane == true)]")
    local worker_nodes=$(manifest_read_yaml "[.nodes[] | select(.control_plane == false)]")

    nodes_install_control_plane "$control_plane_nodes"
    nodes_install_worker "$worker_nodes"
}


##########################################
# Install the control plane nodes
##########################################
function nodes_install_control_plane() {
    local nodes="$1"

    local nodes_count=$(echo "$nodes" | yq length)
    local i
    for ((i=0; i<nodes_count; i++)); do
        local node=$(yq ".[$i]" <<< "$nodes")

        sysctl_configuration "$node"
        load_modules "$node"
        packages_system_install "$node"
        packages_runtime_install "$node"
        packages_kubernetes_install "$node"
        packages_haproxy_install "$node"

        # Only use the first control plane node for the initialisation
        if [ "$i" = 0 ]; then
            kubernetes_kubeadm_control_plane_init "$node"
        else
            kubernetes_kubeadm_control_plane_join "$node"
        fi

        kubernetes_kubelet_patch_config "$node"
        kubernetes_kubectl_label_node "$node"
    done
}


##########################################
# Install the worker nodes
##########################################
function nodes_install_worker() {
    local nodes="$1"

    local nodes_count=$(echo "$nodes" | yq length)
    local i
    for ((i=0; i<nodes_count; i++)); do
        local node=$(yq ".[$i]" <<< "$nodes")

        sysctl_configuration "$node"
        load_modules "$node"
        packages_system_install "$node"
        packages_runtime_install "$node"
        packages_kubernetes_install "$node"
        packages_haproxy_install "$node"
        kubernetes_kubeadm_worker_join "$node"
        kubernetes_kubelet_patch_config "$node"
        kubernetes_kubectl_label_node "$node"
    done
}
