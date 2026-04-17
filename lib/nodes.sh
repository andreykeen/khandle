##########################################
# Install the cluster
##########################################
function nodes_install_cluster() {
    local specific_node_names="$1"
    local specific_node_names_list="$(echo "${specific_node_names}" | tr ',' ' ')"

    local control_plane_nodes=""
    local worker_nodes=""

    if [[ -n "${specific_node_names}" ]]; then
        print_status "info" "Working with nodes: ${specific_node_names_list}"

        local nodes_select_string=""
        for node_name in ${specific_node_names_list}; do
            nodes_select_string+=".hostname == \"${node_name}\" or "
        done
        nodes_select_string="${nodes_select_string% or }"

        local nodes=$(manifest_read_yaml "[.nodes[] | select(${nodes_select_string})]")

        if [[ -n "${nodes}" ]]; then
            control_plane_nodes="$(yq "[.[] | select(.control_plane == true)]" <<< "${nodes}")"
            worker_nodes="$(yq "[.[] | select(.control_plane == false)]" <<< "${nodes}")"
        fi
    else
        local control_plane_nodes=$(manifest_read_yaml "[.nodes[] | select(.control_plane == true)]")
        local worker_nodes=$(manifest_read_yaml "[.nodes[] | select(.control_plane == false)]")
    fi

    nodes_install_control_plane "$control_plane_nodes"
    nodes_install_worker "$worker_nodes"
}


##########################################
# Install the control plane nodes
##########################################
function nodes_install_control_plane() {
    local nodes="$1"
    local nodes_count=$(echo "${nodes}" | yq length)
    local i

    for ((i=0; i<nodes_count; i++)); do
        local node=$(yq ".[$i]" <<< "${nodes}")
        local hostname=$(yq ".hostname" <<< "${node}")

        print_status "info" "---------- Working with control plane node ${hostname} ----------"
        os_kubeapiserver_interface "${node}"
        os_sysctl "${node}"
        os_kernel_modules "${node}"
        packages_apt_install "${node}"
        packages_runtime_install "${node}"
        packages_haproxy_install "${node}"

        kubernetes_install_binaries "${node}"
        kubernetes_kubeadm_upgrade "${node}"

        # Only use the first control plane node for running the commands
        if [[ "$i" == 0 ]]; then
            kubernetes_kubeadm_control_plane_init "${node}"
            kubernetes_kubeadm_certs_renew "${node}"
        else
            kubernetes_kubeadm_control_plane_join "${node}"
        fi

        kubernetes_kubelet_patch_config "${node}"
        kubernetes_kubectl_label_node "${node}"
    done
}


##########################################
# Install the worker nodes
##########################################
function nodes_install_worker() {
    local nodes="$1"

    local nodes_count=$(echo "${nodes}" | yq length)
    local i
    for ((i=0; i<nodes_count; i++)); do
        local node=$(yq ".[$i]" <<< "${nodes}")
        local hostname=$(yq ".hostname" <<< "${node}")

        print_status "info" "---------- Working with worker node ${hostname} ----------"
        os_kubeapiserver_interface "${node}"
        os_sysctl "${node}"
        os_kernel_modules "${node}"
        packages_apt_install "${node}"
        packages_runtime_install "${node}"
        packages_haproxy_install "${node}"

        kubernetes_install_binaries "${node}"
        kubernetes_kubeadm_upgrade "${node}"
        kubernetes_kubeadm_worker_join "${node}"
        kubernetes_kubelet_patch_config "${node}"
        kubernetes_kubectl_label_node "${node}"
    done
}
