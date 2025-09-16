##########################################
# Initialise control plane
##########################################
function kubeadm_control_plane_init() {
    local node="$1"

    local apiserver_cert_extra_sans=$(yq e '.cluster_network.apiserver_cert_extra_sans | join(",")' "$NODES_FILE")
    local control_plane_endpoint=$(yq e '.cluster_network.control_plane_endpoint' "$NODES_FILE")
    local pod_network_cidr=$(yq e '.cluster_network.pod_network_cidr' "$NODES_FILE")
    local service_dns_domain=$(yq e '.cluster_network.service_dns_domain' "$NODES_FILE")

    local kubeadm_init_command="sudo kubeadm init"

    if [ "$apiserver_cert_extra_sans" != "null" ] && [ -n "$apiserver_cert_extra_sans" ]; then
        kubeadm_init_command+=" --apiserver-cert-extra-sans=$apiserver_cert_extra_sans"
    fi

    if [ "$control_plane_endpoint" != "null" ] && [ -n "$control_plane_endpoint" ]; then
        kubeadm_init_command+=" --control-plane-endpoint=$control_plane_endpoint"
    fi

    if [ "$pod_network_cidr" != "null" ] && [ -n "$pod_network_cidr" ]; then
        kubeadm_init_command+=" --pod-network-cidr=$pod_network_cidr"
    fi

    if [ "$service_dns_domain" != "null" ] && [ -n "$service_dns_domain" ]; then
        kubeadm_init_command+=" --service-dns-domain=$service_dns_domain"
    fi

    run_commands_on_node $node "test -f /etc/kubernetes/manifests/kube-apiserver.yaml && echo 'exists' || echo 'doesnotexist'"
    if [ "$RETURN_OUTPUT" = "doesnotexist" ]; then
        print_status "info" "Initialising control plane on node $node with command: $kubeadm_init_command"
        run_commands_on_node $node "$kubeadm_init_command"

        print_status "info" "Copying kubeconfig to local directory"
        # run_commands_on_node $node "while sudo test ! -f /etc/kubernetes/admin.conf; do sleep 1; done"
        run_commands_on_node $node "sudo mkdir -p /root/.kube && sudo cp /etc/kubernetes/admin.conf /root/.kube/config && sudo chmod 600 /root/.kube/config"
        run_commands_on_node $node "sudo cat /etc/kubernetes/admin.conf"
        local kubeconfig_output=$RETURN_OUTPUT
        echo "$kubeconfig_output" > ./khandle.kubeconfig
    else
        print_status "info" "Control plane is already initialised on node $node"
    fi
}


##########################################
# Join node to the control plane
##########################################
function kubeadm_control_plane_join() {
    local node="$1"

    run_commands_on_node $node "test -f /etc/kubernetes/manifests/kube-apiserver.yaml && echo 'exists' || echo 'doesnotexist'"
    if [ "$RETURN_OUTPUT" = "doesnotexist" ]; then
        print_status "info" "Joining node $node to the control plane"


        run_commands_on_node $CONTROL_PLANE_MAIN_NODE "sudo kubeadm init phase upload-certs --upload-certs | grep -v 'upload-certs'"
        local certificate_key=$RETURN_OUTPUT
        run_commands_on_node $CONTROL_PLANE_MAIN_NODE "sudo kubeadm token create --print-join-command"
        local join_command=$RETURN_OUTPUT
        join_command="$join_command --control-plane --certificate-key $certificate_key"

        run_commands_on_node $node "sudo $join_command"

    else
        print_status "info" "Node $node is already joined to the control plane"
    fi

}


##########################################
# Join node to the worker nodes
##########################################
function kubeadm_worker_node_join() {
    local node="$1"

    run_commands_on_node $node "test -f /etc/kubernetes/kubelet.conf && echo 'exists' || echo 'doesnotexist'"
    if [ "$RETURN_OUTPUT" = "doesnotexist" ]; then
        print_status "info" "Joining worker node $node to the cluster"

        # Get the token from the control plane main node
        run_commands_on_node $CONTROL_PLANE_MAIN_NODE "sudo kubeadm token create --print-join-command"
        local join_command=$RETURN_OUTPUT
        run_commands_on_node $node "sudo $join_command"
    else
        print_status "info" "Node $node is already joined to the cluster"
    fi
}
