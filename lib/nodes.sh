##########################################
# Interact with the nodes
##########################################
function nodes_manage() {
    if [ "$VERBOSE" = true ]; then
        print_status "info" "Managing all nodes"
    fi

    nodes_control_plane_manage
    nodes_worker_manage
}


##########################################
# Interact with the control plane nodes
##########################################
function nodes_control_plane_manage() {
    if [ "$VERBOSE" = true ]; then
        print_status "info" "Managing control plane nodes only"
    fi

    local control_plane_count=$(yq e '.control_planes | length' "$NODES_FILE")
    for ((i=0; i<control_plane_count; i++)); do
        hostname=$(yq e ".control_planes[$i].hostname" "$NODES_FILE")

        sysctl_configuration $hostname
        load_modules $hostname
        packages_install $hostname
        packages_runtime_install $hostname
        haproxy_configure $hostname

        # Only use the first control plane node for the initialisation
        if [ "$hostname" = "$CONTROL_PLANE_MAIN_NODE" ]; then
            kubeadm_control_plane_init $hostname
            # packages_helm_install $hostname
            # cni_manage $hostname
        else
            kubeadm_control_plane_join $hostname
        fi

        # if [ "$hostname" = "fsn1-nd02.cxense.com" ]; then
        #     print_status "info" "Skipping control plane join for node $hostname"
        #     return 0
        # fi

        kubelet_patch_config $hostname
        kubectl_label_node $hostname
    done
}


##########################################
# Interact with the worker nodes
##########################################
function nodes_worker_manage() {
    if [ "$VERBOSE" = true ]; then
        print_status "info" "Managing worker nodes only"
    fi

    local worker_nodes_count=$(yq e '.worker_nodes | length' "$NODES_FILE")
    for ((i=0; i<worker_nodes_count; i++)); do
        hostname=$(yq e ".worker_nodes[$i].hostname" "$NODES_FILE")
        print_status "info" "Managing worker node $hostname"

        sysctl_configuration $hostname
        load_modules $hostname
        packages_install $hostname
        packages_runtime_install $hostname
        haproxy_configure $hostname
        kubeadm_worker_node_join $hostname

        kubelet_patch_config $hostname
        kubectl_label_node $hostname
    done
}
