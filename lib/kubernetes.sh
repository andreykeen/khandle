##########################################
# Initialise control plane
##########################################
function kubernetes_kubeadm_control_plane_init() {
    local node="$1"

    local apiserver_cert_extra_sans=$(yq e '.cluster_network.apiserver_cert_extra_sans | join(",")' "$NODES_FILE")
    local control_plane_endpoint=$(yq e '.cluster_network.control_plane_endpoint' "$NODES_FILE")
    local pod_network_cidr=$(yq e '.cluster_network.pod_network_cidr' "$NODES_FILE")
    local service_dns_domain=$(yq e '.cluster_network.service_dns_domain' "$NODES_FILE")
    local public_ip=$(echo "$ALL_NODES" | yq e '.nodes[] | select(.hostname == "'$node'") | .public_ip')
    local private_ip=$(echo "$ALL_NODES" | yq e '.nodes[] | select(.hostname == "'$node'") | .private_ip')
    local kube_proxy_enabled=$(yq e '.cluster_network.kube_proxy.enabled' "$NODES_FILE")

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

    if [ "$private_ip" != "null" ] && [ -n "$private_ip" ]; then
        kubeadm_init_command+=" --apiserver-advertise-address=$private_ip"
    fi

    if [ "$kube_proxy_enabled" = false ]; then
        kubeadm_init_command+=" --skip-phases=addon/kube-proxy"
    fi

    run_commands_on_node $node "test -f /etc/kubernetes/manifests/kube-apiserver.yaml && echo 'exists' || echo 'doesnotexist'"
    if [ "$RETURN_OUTPUT" = "doesnotexist" ]; then
        print_status "info" "$node: Initialising control plane with command: $kubeadm_init_command"
        run_commands_on_node $node "$kubeadm_init_command"
    else
        print_status "info" "$node: Control plane is already initialised"
    fi
    kubernetes_kubeadm_control_plane_download_kubeconfig $node
}


##########################################
# Configure kubeconfig file
##########################################
function kubernetes_kubeadm_control_plane_download_kubeconfig() {
    local node="$1"

    local cluster_name=$(yq e '.global.cluster_name' "$NODES_FILE")
    local public_ip=$(echo "$ALL_NODES" | yq e '.nodes[] | select(.hostname == "'$node'") | .public_ip')
    local kubeconfig_file="$HOME/.kube/${cluster_name}.kubeconfig"

    run_commands_on_node $node "sudo mkdir -p /root/.kube && sudo cp /etc/kubernetes/admin.conf /root/.kube/config && sudo chmod 600 /root/.kube/config"

    run_commands_on_node $node "sudo cat /etc/kubernetes/admin.conf"
    local kubeconfig_output=$RETURN_OUTPUT

    print_status "info" "$node: Downloading kubeconfig to $kubeconfig_file"
    if [ "$public_ip" != "null" ] && [ -n "$public_ip" ]; then
        echo "$kubeconfig_output" | sed "s/169.254.10.10/$public_ip/" > "$kubeconfig_file"
    else
        echo "$kubeconfig_output" > "$kubeconfig_file"
    fi
}


##########################################
# Join node to the control plane
##########################################
function kubernetes_kubeadm_control_plane_join() {
    local node="$1"

    run_commands_on_node $node "test -f /etc/kubernetes/manifests/kube-apiserver.yaml && echo 'exists' || echo 'doesnotexist'"
    if [ "$RETURN_OUTPUT" = "doesnotexist" ]; then

        local private_ip=$(echo "$ALL_NODES" | yq e '.nodes[] | select(.hostname == "'$node'") | .private_ip')

        run_commands_on_node $CONTROL_PLANE_MAIN_NODE "sudo kubeadm init phase upload-certs --upload-certs 2> /dev/null | grep -v 'upload-certs'"
        local certificate_key=$RETURN_OUTPUT
        run_commands_on_node $CONTROL_PLANE_MAIN_NODE "sudo kubeadm token create --print-join-command"
        local join_command=$RETURN_OUTPUT
        join_command="$join_command --control-plane --certificate-key $certificate_key --apiserver-advertise-address=$private_ip"

        print_status "info" "$node: Joining to the control plane with command: $join_command"
        run_commands_on_node $node "sudo $join_command"

    else
        print_status "info" "$node: The node is already joined to the control plane"
    fi

}


##########################################
# Join node to the worker nodes
##########################################
function kubernetes_kubeadm_worker_node_join() {
    local node="$1"

    run_commands_on_node $node "test -f /etc/kubernetes/kubelet.conf && echo 'exists' || echo 'doesnotexist'"
    if [ "$RETURN_OUTPUT" = "doesnotexist" ]; then
        print_status "info" "$node: Joining to the cluster"

        # Get the token from the control plane main node
        run_commands_on_node $CONTROL_PLANE_MAIN_NODE "sudo kubeadm token create --print-join-command"
        local join_command=$RETURN_OUTPUT

        print_status "info" "$node: Joining to the cluster with command: $join_command"
        run_commands_on_node $node "sudo $join_command"
    else
        print_status "info" "$node: The node is already joined to the cluster"
    fi
}


##########################################
# Configure kubelet
##########################################
function kubernetes_kubelet_patch_config() {
    local node="$1"

    local private_ip=$(echo "$ALL_NODES" | yq e '.nodes[] | select(.hostname == "'$node'") | .private_ip')
    local kubelet_config=$(echo "$ALL_NODES" | yq e '.nodes[] | select(.hostname == "'$node'") | .kubernetes.kubelet.config')
    local kubelet_kubeadm_args=$(echo "$ALL_NODES" | yq e '.nodes[] | select(.hostname == "'$node'") | .kubernetes.kubelet.kubelet_kubeadm_args[]')
    local kubelet_config_is_updated="no"

    ### Update the Kubelet config
    if [ "$kubelet_config" != "null" ] && [ -n "$kubelet_config" ]; then
        print_status "info" "$node: Updating Kubelet config"
        kubelet_config_is_updated="yes"

        # Create the patch file
        run_commands_on_node $node "sudo tee /var/lib/kubelet/config-patch.yaml > /dev/null <<EOF
$kubelet_config
EOF"

        # Backup the original config
        run_commands_on_node $node "if [ ! -f /var/lib/kubelet/config-original.yaml ]; then sudo cp /var/lib/kubelet/config.yaml /var/lib/kubelet/config-original.yaml; fi"

        # Update the config with the patch
        run_commands_on_node $node "sudo yq eval-all 'select(fileIndex == 0) as \$orig | select(fileIndex == 1) as \$patch | (\$orig | delpaths([[\$patch | keys[]]])) * \$patch' /var/lib/kubelet/config-original.yaml /var/lib/kubelet/config-patch.yaml | yq 'sort_keys(..)' | sudo tee /var/lib/kubelet/config.yaml > /dev/null"
    fi

    ### Update the Kubeadm flags env file
    if [ "$kubelet_kubeadm_args" != "null" ] && [ -n "$kubelet_kubeadm_args" ]; then
        print_status "info" "$node: Updating Kubeadm flags env file"
        kubelet_config_is_updated="yes"

        run_commands_on_node $node "if [ -f /var/lib/kubelet/kubeadm-flags.env ]; then sudo cat /var/lib/kubelet/kubeadm-flags.env; fi"
        local kubeadm_flags_env_output=$RETURN_OUTPUT

        if [ -z "$kubeadm_flags_env_output" ]; then
            print_status "info" "$node: Creating Kubeadm flags env file"
            kubeadm_flags_env_output="KUBELET_KUBEADM_ARGS=\"\""
        fi


        ### Go through each line and add it to the kubeadm-flags.env file
        while IFS= read -r kubelet_kubeadm_args_line; do

            local kubeadm_flag_name=$(echo "$kubelet_kubeadm_args_line" | awk -F'=' '{print $1}')
            local kubeadm_flag_value=$(echo "$kubelet_kubeadm_args_line" | awk -F'=' '{print $2}')

            if [ "$kubeadm_flag_value" = "-" ]; then
                # Remove the line if the value is "-"
                kubeadm_flags_env_output=$(echo "$kubeadm_flags_env_output" | sed "s/$kubeadm_flag_name=[^ \"]*//")
            else
                if [[ "$kubeadm_flags_env_output" == *"$kubeadm_flag_name="* ]]; then
                    # Update existing value
                    kubeadm_flags_env_output=$(echo "$kubeadm_flags_env_output" | sed "s/$kubeadm_flag_name=[^ \"]*/$kubelet_kubeadm_args_line/")
                else
                    # Append if missing (before the last quote)
                    kubeadm_flags_env_output=$(echo "$kubeadm_flags_env_output" | sed "s/\"$/ $kubelet_kubeadm_args_line\"/")
                fi
            fi

            # Remove extra spaces
            kubeadm_flags_env_output=$(echo "$kubeadm_flags_env_output" | sed -E 's/"[[:blank:]]+/"/g' | sed -E 's/[[:blank:]]+/ /g' | sed -E 's/[[:blank:]]+"/"/g')

        done <<< "$kubelet_kubeadm_args"

        run_commands_on_node $node "sudo tee /var/lib/kubelet/kubeadm-flags.env > /dev/null <<EOF
$kubeadm_flags_env_output
EOF"
    fi

    if [ "$kubelet_config_is_updated" = "yes" ]; then
        print_status "info" "$node: Restarting kubelet to apply the new configuration"
        run_commands_on_node $node "sudo systemctl restart kubelet"
    fi
}
