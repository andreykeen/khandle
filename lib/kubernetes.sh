##########################################
# Install Kubernetes
##########################################
function kubernetes_install() {
    local node="$1"

    local hostname=$(yq ".hostname" <<< "$node")
    local version_full=$(yq ".kubernetes.version" <<< "$node")
    local version_minor=$(echo "$version_full" | awk -F'.' '{print $1 "." $2}')

    local installing_components=""

    run_commands_on_node "$node" "sudo dpkg-query -W -f='\${Package} \${Version}\n' kube* 2>/dev/null || true"
    if [[ "$RETURN_OUTPUT" != *"kubeadm ${version_full}"* ]]; then
        installing_components+="kubeadm=${version_full}* "
    fi
    if [[ "$RETURN_OUTPUT" != *"kubelet ${version_full}"* ]]; then
        installing_components+="kubelet=${version_full}* "
    fi
    if [[ "$RETURN_OUTPUT" != *"kubectl ${version_full}"* ]]; then
        installing_components+="kubectl=${version_full}* "
    fi
    # run_commands_on_node "$node" "sudo dpkg-query -W -f='\${Package} \${Version}\n' cri-tools 2>/dev/null || true"
    # if [[ "$RETURN_OUTPUT" != *"cri-tools ${version_full}"* ]]; then
    #     installing_components+="cri-tools=${version_full}* "
    # fi

    # echo "installing_components: $installing_components"
    # exit 0

    if [[ -n "${installing_components}" ]]; then
        print_status "info" "${hostname}: Installing Kubernetes components: ${installing_components}"

        run_commands_on_node "${node}" "sudo mkdir -p -m 755 /etc/apt/keyrings && \
            curl -fsSL https://pkgs.k8s.io/core:/stable:/v${version_minor}/deb/Release.key | sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg && \
            sudo chmod 0644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg && \
            echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${version_minor}/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list && \
            sudo apt-get update && \
            sudo apt-get install -y --allow-downgrades --allow-change-held-packages $installing_components && \
            sudo apt-mark hold kubelet kubeadm kubectl && \
            sudo systemctl enable --now kubelet && \
            sudo systemctl restart kubelet"
        print_status "info" "${hostname}: Restarting kubelet to apply the new version"
    else
        print_status "info" "${hostname}: Kubernetes components are already installed and up to date"
    fi

}


##########################################
# Initialise control plane
##########################################
function kubernetes_kubeadm_control_plane_init() {
    local node="$1"

    local hostname=$(yq ".hostname" <<< "$node")

    run_commands_on_node "$node" "test -f /etc/kubernetes/manifests/kube-apiserver.yaml && echo 'exists' || echo 'doesnotexist'"
    if [[ "$RETURN_OUTPUT" == "exists" ]]; then
        print_status "info" "$hostname: Control plane is already initialised"
        return
    fi

    local version_full=$(yq ".kubernetes.version" <<< "$node")
    local apiserver_cert_extra_sans=$(manifest_read_yaml ".cluster_network.apiserver_cert_extra_sans | join(\",\")")
    local control_plane_endpoint=$(manifest_read_yaml ".cluster_network.control_plane_endpoint")
    local pod_network_cidr=$(manifest_read_yaml ".cluster_network.pod_network_cidr")
    local service_dns_domain=$(manifest_read_yaml ".cluster_network.service_dns_domain")
    local kube_proxy_enabled=$(manifest_read_yaml ".cluster_network.kube_proxy.enabled")
    local apiserver_advertise_address=$(yq ".kubernetes.apiserver_advertise_address" <<< "$node")

    local kubeadm_init_command="sudo kubeadm init --kubernetes-version=${version_full}"

    if [ -n "$apiserver_cert_extra_sans" ] && [ "$apiserver_cert_extra_sans" != "null" ]; then
        kubeadm_init_command+=" --apiserver-cert-extra-sans=$apiserver_cert_extra_sans"
    fi

    if [ -n "$control_plane_endpoint" ] && [ "$control_plane_endpoint" != "null" ]; then
        kubeadm_init_command+=" --control-plane-endpoint=$control_plane_endpoint"
    fi

    if [ -n "$pod_network_cidr" ] && [ "$pod_network_cidr" != "null" ]; then
        kubeadm_init_command+=" --pod-network-cidr=$pod_network_cidr"
    fi

    if [ -n "$service_dns_domain" ] && [ "$service_dns_domain" != "null" ]; then
        kubeadm_init_command+=" --service-dns-domain=$service_dns_domain"
    fi

    if [ -n "$apiserver_advertise_address" ] && [ "$apiserver_advertise_address" != "null" ]; then
        kubeadm_init_command+=" --apiserver-advertise-address=$apiserver_advertise_address"
    fi

    if [ "$kube_proxy_enabled" = false ]; then
        kubeadm_init_command+=" --skip-phases=addon/kube-proxy"
    fi

    print_status "info" "$hostname: Initialising control plane with command: $kubeadm_init_command"
    run_commands_on_node "$node" "$kubeadm_init_command"

    kubernetes_kubeadm_control_plane_download_kubeconfig "$node"
}


##########################################
# Configure kubeconfig file
##########################################
function kubernetes_kubeadm_control_plane_download_kubeconfig() {
    local node="$1"

    local hostname=$(yq ".hostname" <<< "$node")
    local cluster_name=$(manifest_read_yaml ".global.cluster_name")
    local public_ip=$(yq ".public_ip" <<< "$node")
    local kubeconfig_file="$HOME/.kube/${cluster_name}.kubeconfig"

    run_commands_on_node "$node" "sudo mkdir -p /root/.kube && sudo cp /etc/kubernetes/admin.conf /root/.kube/config && sudo chmod 600 /root/.kube/config"

    run_commands_on_node "$node" "sudo cat /etc/kubernetes/admin.conf"
    local kubeconfig_output=$RETURN_OUTPUT

    print_status "info" "$hostname: Downloading kubeconfig to $kubeconfig_file"
    if [ -n "$public_ip" ] && [ "$public_ip" != "null" ]; then
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

    local hostname=$(yq ".hostname" <<< "$node")
    run_commands_on_node "$node" "test -f /etc/kubernetes/manifests/kube-apiserver.yaml && echo 'exists' || echo 'doesnotexist'"
    if [ "$RETURN_OUTPUT" = "doesnotexist" ]; then

        local control_plane_main_node=$(manifest_read_yaml "[.nodes[] | select(.control_plane == true)] | .[0]")
        local apiserver_advertise_address=$(yq ".kubernetes.apiserver_advertise_address" <<< "$node")

        # Getting the certificate key from the control plane main node
        run_commands_on_node "$control_plane_main_node" "sudo kubeadm init phase upload-certs --upload-certs 2> /dev/null | grep -v 'upload-certs'"
        local certificate_key=$RETURN_OUTPUT

        # Getting the join command from the control plane main node
        run_commands_on_node "$control_plane_main_node" "sudo kubeadm token create --print-join-command"
        local join_command=$RETURN_OUTPUT

        # Adding the certificate key and the private IP to the join command
        join_command="$join_command --control-plane --certificate-key $certificate_key --apiserver-advertise-address=$apiserver_advertise_address"

        print_status "info" "$hostname: Joining to the control plane with command: $join_command"
        run_commands_on_node "$node" "sudo $join_command"

    else
        print_status "info" "$hostname: The node is already joined to the control plane"
    fi

}


##########################################
# Join node to the worker nodes
##########################################
function kubernetes_kubeadm_worker_join() {
    local node="$1"

    local hostname=$(yq ".hostname" <<< "$node")

    run_commands_on_node "$node" "test -f /etc/kubernetes/kubelet.conf && echo 'exists' || echo 'doesnotexist'"
    if [ "$RETURN_OUTPUT" = "doesnotexist" ]; then
        print_status "info" "$hostname: Joining to the cluster"

        # Getting the join command from the control plane main node
        local control_plane_main_node=$(manifest_read_yaml "[.nodes[] | select(.control_plane == true)] | .[0]")
        run_commands_on_node "$control_plane_main_node" "sudo kubeadm token create --print-join-command"
        local join_command=$RETURN_OUTPUT

        print_status "info" "$hostname: Joining to the cluster with command: $join_command"
        run_commands_on_node "$node" "sudo $join_command"
    else
        print_status "info" "$hostname: The node is already joined to the cluster"
    fi
}


##########################################
# Upgrade Kubernetes
##########################################
function kubernetes_kubeadm_upgrade() {
    local node="$1"

    local hostname=$(yq ".hostname" <<< "$node")
    local version_full=$(yq ".kubernetes.version" <<< "$node")

    run_commands_on_node "$node" "sudo yq '.spec.containers[] | select(.name == \"kube-apiserver\") | .image' /etc/kubernetes/manifests/kube-apiserver.yaml"
    if [[ "$RETURN_OUTPUT" == *"${version_full}"* ]]; then
        print_status "info" "${hostname}: kube-apiserver is already up to date"
        return
    fi

    # If the node is the main control plane node, then we need to upgrade the control plane
    local control_plane_main_node_hostname=$(manifest_read_yaml "[.nodes[] | select(.control_plane == true)] | .[0].hostname")
    if [[ "${control_plane_main_node_hostname}" == "${hostname}" ]]; then
        print_status "info" "${hostname}: Upgrading kube-apiserver to version: $version_full on the main control plane node"
        run_commands_on_node "$node" "sudo kubeadm upgrade apply ${version_full} --yes"
    else
        print_status "info" "${hostname}: Upgrading kube-apiserver to version: $version_full on the other control plane nodes"
        run_commands_on_node "$node" "sudo kubeadm upgrade node"
    fi
}


##########################################
# Configure kubelet
##########################################
function kubernetes_kubelet_patch_config() {
    local node="$1"

    local hostname=$(yq ".hostname" <<< "$node")
    print_status "info" "$hostname: Configuring kubelet"

    local kubelet_config=$(yq ".kubernetes.kubelet.config" <<< "$node")
    local kubelet_kubeadm_args=$(yq ".kubernetes.kubelet.kubelet_kubeadm_args[]" <<< "$node")
    local kubelet_config_is_updated="no"

    ### Update the Kubelet config
    if [ -n "$kubelet_config" ] && [ "$kubelet_config" != "null" ]; then
        print_status "info" "$hostname: Updating Kubelet config"

        # Create the patch file
        run_commands_on_node "$node" "sudo tee /var/lib/kubelet/config-patch.yaml > /dev/null <<EOF
$kubelet_config
EOF"

        # Backup the original config
        run_commands_on_node "$node" "if [ ! -f /var/lib/kubelet/config-original.yaml ]; then sudo cp /var/lib/kubelet/config.yaml /var/lib/kubelet/config-original.yaml; fi"

        # Update the config with the patch
        run_commands_on_node "$node" "sudo yq eval-all 'select(fileIndex == 0) as \$orig | select(fileIndex == 1) as \$patch | (\$orig | delpaths([[\$patch | keys[]]])) * \$patch' /var/lib/kubelet/config-original.yaml /var/lib/kubelet/config-patch.yaml | yq 'sort_keys(..)' | sudo tee /var/lib/kubelet/config.yaml > /dev/null"

        kubelet_config_is_updated="yes"
    fi


    ### Update the Kubeadm flags env file
    if [ -n "$kubelet_kubeadm_args" ] && [ "$kubelet_kubeadm_args" != "null" ]; then
        print_status "info" "$hostname: Updating Kubeadm flags env file"

        run_commands_on_node "$node" "if [ -f /var/lib/kubelet/kubeadm-flags.env ]; then sudo cat /var/lib/kubelet/kubeadm-flags.env; fi"
        local kubeadm_flags_env_output=$RETURN_OUTPUT

        if [ -z "$kubeadm_flags_env_output" ]; then
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

        run_commands_on_node "$node" "sudo tee /var/lib/kubelet/kubeadm-flags.env > /dev/null <<EOF
$kubeadm_flags_env_output
EOF"
        kubelet_config_is_updated="yes"
    fi

    if [ "$kubelet_config_is_updated" = "yes" ]; then
        print_status "info" "$hostname: Restarting kubelet to apply the new configuration"
        run_commands_on_node "$node" "sudo systemctl restart kubelet"
    fi
}


##########################################
# Label node
##########################################
function kubernetes_kubectl_label_node() {
    local node="$1"

    local hostname=$(yq ".hostname" <<< "$node")
    local node_labels=$(yq ".kubernetes.labels" <<< "$node")

    if [ -n "$node_labels" ] && [ "$node_labels" != "null" ]; then
        print_status "info" "$hostname: Labeling node"

        local labels_string=$(echo "$node_labels" | tr -s ':' '=' | tr -d ' ' | tr -s '\n' ' ')

        local control_plane_main_node=$(manifest_read_yaml "[.nodes[] | select(.control_plane == true)] | .[0]")
        run_commands_on_node "$control_plane_main_node" "sudo kubectl --kubeconfig /etc/kubernetes/admin.conf label --overwrite node $hostname $labels_string"
    fi
}
