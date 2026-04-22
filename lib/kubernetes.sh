##########################################
# Set the APT repository
##########################################
function kubernetes_set_apt_repository() {
    local node="$1"
    local hostname=$(yq ".hostname" <<< "${node}")
    local version_full=$(yq ".kubernetes.version" <<< "${node}")
    local version_minor=$(echo "${version_full}" | awk -F'.' '{print $1 "." $2}')

    run_commands_on_node "${node}" "if [ -f /etc/apt/sources.list.d/kubernetes.list ]; then sudo grep -w \"v${version_minor}\" /etc/apt/sources.list.d/kubernetes.list || true; fi";
    if [[ -n "${RETURN_OUTPUT}" ]]; then
        print_status "verbose" "${hostname}: APT repository for Kubernetes ${version_minor}.* version is already set"
        return
    fi

    print_status "info" "${hostname}: Setting APT repository for Kubernetes ${version_full} version"
    run_commands_on_node "${node}" "sudo mkdir -p -m 755 /etc/apt/keyrings && \
        curl -fsSL https://pkgs.k8s.io/core:/stable:/v${version_minor}/deb/Release.key | sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg && \
        sudo chmod 0644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg && echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${version_minor}/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list && sudo apt-get update"
}


##########################################
# Install Kubernetes
##########################################
function kubernetes_install_binaries() {
    local node="$1"
    local hostname=$(yq ".hostname" <<< "${node}")
    local version_full=$(yq ".kubernetes.version" <<< "${node}")
    local version_minor=$(echo "${version_full}" | awk -F'.' '{print $1 "." $2}')
    local installing_components=""

    run_commands_on_node "${node}" "sudo which kubeadm || true";
    if [[ -z "$RETURN_OUTPUT" ]]; then
        installing_components+="kubeadm=${version_full}-* "
    fi
    run_commands_on_node "${node}" "sudo which kubelet || true";
    if [[ -z "$RETURN_OUTPUT" ]]; then
        installing_components+="kubelet=${version_full}-* "
    fi
    run_commands_on_node "${node}" "sudo which kubectl || true";
    if [[ -z "$RETURN_OUTPUT" ]]; then
        installing_components+="kubectl=${version_full}-* "
    fi

    if [[ -z "$installing_components" ]]; then
        print_status "verbose" "${hostname}: Kubernetes binaries are already installed"
        return
    fi

    # Set the APT repository
    kubernetes_set_apt_repository "${node}"

    print_status "info" "${hostname}: Installing Kubernetes binaries: ${installing_components}"
    run_commands_on_node "${node}" "sudo apt-get install -y --allow-downgrades --allow-change-held-packages ${installing_components} && \
        sudo apt-mark hold kubelet kubeadm kubectl && \
        sudo systemctl enable --now kubelet && \
        sudo systemctl restart kubelet"
}


##########################################
# Upgrade Kubernetes
##########################################
function kubernetes_kubeadm_upgrade() {
    local node="$1"
    local hostname=$(yq ".hostname" <<< "${node}")
    local version_full=$(yq ".kubernetes.version" <<< "${node}")
    local node_is_control_plane=$(yq ".control_plane" <<< "${node}")

    # Check if the node is joined to the cluster
    run_commands_on_node "${node}" "test -f /etc/kubernetes/kubelet.conf && echo 'exists' || echo 'doesnotexist'"
    if [[ "${RETURN_OUTPUT}" == "doesnotexist" ]]; then
        print_status "verbose" "${hostname}: Kubernetes node is not joined to the cluster. Skipping upgrade"
        return
    fi

    # Get the current kubeadm version
    run_commands_on_node "${node}" "sudo kubeadm version --output short | tr -d 'v'"
    local current_kubeadm_version="${RETURN_OUTPUT}"
    print_status "verbose" "${hostname}: Current kubeadm version: ${current_kubeadm_version}"

    # Get the current kubelet versions
    run_commands_on_node "${node}" "sudo kubelet --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'"
    local current_kubelet_version="${RETURN_OUTPUT}"
    print_status "verbose" "${hostname}: Current kubelet version: ${current_kubelet_version}"

    # Get the current kubectl versions
    run_commands_on_node "${node}" "sudo kubectl version --client | grep 'Client Version:' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'"
    local current_kubectl_version="${RETURN_OUTPUT}"
    print_status "verbose" "${hostname}: Current kubectl version: ${current_kubectl_version}"

    if [[ "${current_kubeadm_version}" == "${version_full}" && \
        "${current_kubelet_version}" == "${version_full}" && \
        "${current_kubectl_version}" == "${version_full}" \
    ]]; then
        print_status "verbose" "${hostname}: Kubernetes binaries are already at version: ${version_full}. Skipping upgrade."
        return
    fi

    # Set the APT repository for the new version
    kubernetes_set_apt_repository "${node}"

    # Upgrade the kubeadm binary to the new version
    print_status "info" "${hostname}: Upgrading kubeadm binary to version: ${version_full}"
    run_commands_on_node "${node}" "sudo apt-get install -y --allow-downgrades --allow-change-held-packages kubeadm=${version_full}-* && \
        sudo apt-mark hold kubeadm"

    # If the node is the main control plane node, then we need to upgrade the control plane
    local control_plane_main_node_hostname=$(manifest_read_yaml "[.nodes[] | select(.control_plane == true)] | .[0].hostname")
    if [[ "${control_plane_main_node_hostname}" == "${hostname}" ]]; then

        print_status "info" "${hostname}: Upgrading Kubernetes on the main control plane node to version: ${version_full}"
        run_commands_on_node "${node}" "sudo kubeadm upgrade apply ${version_full} --yes"

        print_status "verbose" "${hostname}: Waiting for 90 seconds after the upgrade to allow the control plane to stabilise"
        sleep 90
    else
        print_status "info" "${hostname}: Upgrading Kubernetes on the other nodes to version: ${version_full}"
        run_commands_on_node "${node}" "sudo kubeadm upgrade node"
    fi

    # Drain the node
    kubernetes_drain_node "${node}"

    # Upgrade the kubelet
    print_status "info" "${hostname}: Upgrading kubelet and kubectl binaries to version: ${version_full}"
    run_commands_on_node "${node}" "sudo apt-get install -y --allow-downgrades --allow-change-held-packages kubelet=${version_full}-* kubectl=${version_full}-* && \
        sudo apt-mark hold kubelet kubectl && \
        sudo systemctl restart kubelet"

    print_status "verbose" "${hostname}: Waiting for 30 seconds after the kubelet upgrade to allow the node to stabilise"
    sleep 30

    # Uncordon the node
    kubernetes_uncordon_node "${node}"
}


##########################################
# Drain node
##########################################
function kubernetes_drain_node() {
    local node="$1"
    local hostname=$(yq ".hostname" <<< "${node}")
    local control_plane_main_node=$(manifest_read_yaml "[.nodes[] | select(.control_plane == true)] | .[0]")
    local control_plane_main_node_hostname=$(yq ".hostname" <<< "${control_plane_main_node}")

    print_status "info" "${hostname}: Running the drain command on ${control_plane_main_node_hostname}"
    run_commands_on_node "${control_plane_main_node}" "sudo kubectl drain ${hostname} --ignore-daemonsets --delete-emptydir-data --force --grace-period=30"
}


##########################################
# Uncordon node
##########################################
function kubernetes_uncordon_node() {
    local node="$1"
    local hostname=$(yq ".hostname" <<< "${node}")
    local control_plane_main_node=$(manifest_read_yaml "[.nodes[] | select(.control_plane == true)] | .[0]")
    local control_plane_main_node_hostname=$(yq ".hostname" <<< "${control_plane_main_node}")

    print_status "info" "${hostname}: Running the uncordon command on ${control_plane_main_node_hostname}"
    run_commands_on_node "${control_plane_main_node}" "sudo kubectl uncordon ${hostname}"
}


##########################################
# Initialise control plane
##########################################
function kubernetes_kubeadm_control_plane_init() {
    local node="$1"
    local hostname=$(yq ".hostname" <<< "${node}")

    run_commands_on_node "${node}" "test -f /etc/kubernetes/manifests/kube-apiserver.yaml && echo 'exists' || echo 'doesnotexist'"
    if [[ "${RETURN_OUTPUT}" == "exists" ]]; then
        print_status "verbose" "${hostname}: Control plane is already initialised"
        return
    fi

    local version_full=$(yq ".kubernetes.version" <<< "${node}")
    local apiserver_cert_extra_sans=$(manifest_read_yaml ".cluster_network.apiserver_cert_extra_sans | join(\",\")")
    local control_plane_endpoint=$(manifest_read_yaml ".cluster_network.control_plane_endpoint")
    local pod_network_cidr=$(manifest_read_yaml ".cluster_network.pod_network_cidr")
    local service_dns_domain=$(manifest_read_yaml ".cluster_network.service_dns_domain")
    local kube_proxy_enabled=$(manifest_read_yaml ".cluster_network.kube_proxy.enabled")
    local apiserver_advertise_address=$(yq ".kubernetes.apiserver_advertise_address" <<< "${node}")
    local image_repository=$(manifest_read_yaml ".global.image_repository")

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

    if [ -n "$image_repository" ] && [ "$image_repository" != "null" ]; then
        kubeadm_init_command+=" --image-repository=$image_repository"
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
    local hostname=$(yq ".hostname" <<< "${node}")

    run_commands_on_node "${node}" "test -f /etc/kubernetes/manifests/kube-apiserver.yaml && echo 'exists' || echo 'doesnotexist'"
    if [[ "${RETURN_OUTPUT}" == "exists" ]]; then
        print_status "verbose" "${hostname}: The node is already joined to the control plane"
        return
    fi

    local control_plane_main_node=$(manifest_read_yaml "[.nodes[] | select(.control_plane == true)] | .[0]")
    local apiserver_advertise_address=$(yq ".kubernetes.apiserver_advertise_address" <<< "${node}")

    # Getting the certificate key from the control plane main node
    run_commands_on_node "${control_plane_main_node}" "sudo kubeadm init phase upload-certs --upload-certs 2> /dev/null | grep -v 'upload-certs'"
    local certificate_key="${RETURN_OUTPUT}"

    # Getting the join command from the control plane main node
    run_commands_on_node "${control_plane_main_node}" "sudo kubeadm token create --print-join-command"
    local join_command="${RETURN_OUTPUT}"

    # Adding the certificate key and the private IP to the join command
    join_command="${join_command} --control-plane --certificate-key ${certificate_key} --apiserver-advertise-address=${apiserver_advertise_address}"

    print_status "info" "${hostname}: Joining to the control plane with command: ${join_command}"
    run_commands_on_node "${node}" "sudo ${join_command}"
}


##########################################
# Join node to the worker nodes
##########################################
function kubernetes_kubeadm_worker_join() {
    local node="$1"
    local hostname=$(yq ".hostname" <<< "${node}")

    run_commands_on_node "${node}" "test -f /etc/kubernetes/kubelet.conf && echo 'exists' || echo 'doesnotexist'"
    if [[ "${RETURN_OUTPUT}" == "exists" ]]; then
        print_status "verbose" "${hostname}: The node is already joined to the cluster"
        return
    fi

    # Getting the join command from the control plane main node
    local control_plane_main_node=$(manifest_read_yaml "[.nodes[] | select(.control_plane == true)] | .[0]")
    run_commands_on_node "${control_plane_main_node}" "sudo kubeadm token create --print-join-command"
    local join_command="${RETURN_OUTPUT}"

    print_status "info" "${hostname}: Joining to the cluster with command: ${join_command}"
    run_commands_on_node "${node}" "sudo ${join_command}"
}


##########################################
# Configure kubelet
##########################################
function kubernetes_kubelet_patch_config() {
    local node="$1"
    local hostname=$(yq ".hostname" <<< "${node}")
    local kubelet_config=$(yq ".kubernetes.kubelet.config" <<< "${node}")
    local kubelet_kubeadm_args=$(yq ".kubernetes.kubelet.kubelet_kubeadm_args[]" <<< "${node}")
    local kubelet_config_is_updated="no"

    ### Update the Kubelet config
    if [[ -n "${kubelet_config}" && "${kubelet_config}" != "null" ]]; then
        print_status "verbose" "${hostname}: Checking Kubelet config"

        # Backup the original config
        run_commands_on_node "${node}" "if [ ! -f /var/lib/kubelet/config-original.yaml ]; then sudo cp /var/lib/kubelet/config.yaml /var/lib/kubelet/config-original.yaml; fi"

        # Create the patch file
        run_commands_on_node "${node}" "sudo tee /var/lib/kubelet/config-patch.yaml > /dev/null <<EOF
$kubelet_config
EOF"
        # Create the updated config file
        run_commands_on_node "${node}" "sudo yq eval-all 'select(fileIndex == 0) as \$orig | select(fileIndex == 1) as \$patch | (\$orig | delpaths([[\$patch | keys[]]])) * \$patch' /var/lib/kubelet/config.yaml /var/lib/kubelet/config-patch.yaml | yq 'sort_keys(..)' | sudo tee /var/lib/kubelet/config-updated.yaml > /dev/null"

        # Check if the kubelet config is updated
        run_commands_on_node "${node}" "sudo diff -q /var/lib/kubelet/config.yaml /var/lib/kubelet/config-updated.yaml || true"
        # If the return output is not empty, then update the config
        if [[ -n "${RETURN_OUTPUT}" ]]; then
            run_commands_on_node "${node}" "sudo mv /var/lib/kubelet/config-updated.yaml /var/lib/kubelet/config.yaml"
            kubelet_config_is_updated="yes"
            print_status "info" "${hostname}: Kubelet config was updated"
        fi
    else
        print_status "verbose" "${hostname}: Kubelet config is not specified in the manifest"
    fi


    ### Update the Kubeadm flags env file
    if [[ -n "${kubelet_kubeadm_args}" && "${kubelet_kubeadm_args}" != "null" ]]; then
        print_status "verbose" "${hostname}: Checking Kubeadm flags env file"

        run_commands_on_node "${node}" "if [ -f /var/lib/kubelet/kubeadm-flags.env ]; then sudo cat /var/lib/kubelet/kubeadm-flags.env; fi"
        local kubeadm_flags_env_output="${RETURN_OUTPUT}"

        if [[ -z "${kubeadm_flags_env_output}" ]]; then
            kubeadm_flags_env_output="KUBELET_KUBEADM_ARGS=\"\""
        fi

        ### Go through each line and add it to the kubeadm-flags.env file
        while IFS= read -r kubelet_kubeadm_args_line; do

            local kubeadm_flag_name=$(echo "$kubelet_kubeadm_args_line" | awk -F'=' '{print $1}')
            local kubeadm_flag_value=$(echo "$kubelet_kubeadm_args_line" | awk -F'=' '{print $2}')

            if [[ "${kubeadm_flag_value}" == "-" ]]; then
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

        done <<< "${kubelet_kubeadm_args}"

        # Create the kubeadm-flags.env updated file
        run_commands_on_node "${node}" "sudo tee /tmp/kubeadm-flags.env > /dev/null <<EOF
$kubeadm_flags_env_output
EOF"

        run_commands_on_node "${node}" "sudo diff -q /var/lib/kubelet/kubeadm-flags.env /tmp/kubeadm-flags.env || true"
        # If the return output is not empty, then update the kubeadm-flags.env file
        if [[ -n "${RETURN_OUTPUT}" ]]; then
            run_commands_on_node "${node}" "sudo mv /tmp/kubeadm-flags.env /var/lib/kubelet/kubeadm-flags.env"
            kubelet_config_is_updated="yes"
            print_status "info" "${hostname}: Kubeadm flags env file was updated"
        fi
    else
        print_status "verbose" "${hostname}: Kubeadm flags env file is not specified in the manifest"
    fi

    # If the kubelet config and/or kubeadm flags env file is updated, then remove the temporary files and restart the kubelet
    if [[ "${kubelet_config_is_updated}" == "yes" ]]; then
        # Remove the temporary files
        run_commands_on_node "${node}" "sudo rm -f \
            /var/lib/kubelet/config-patch.yaml \
            /var/lib/kubelet/config-original.yaml \
            /var/lib/kubelet/config-updated.yaml \
            /tmp/kubeadm-flags.env"

        # Restart the kubelet to apply the new configuration
        print_status "info" "${hostname}: Restarting kubelet to apply the new configuration"
        run_commands_on_node "${node}" "sudo systemctl restart kubelet"
    fi
}


##########################################
# Label node
##########################################
function kubernetes_kubectl_label_node() {
    local node="$1"
    local hostname=$(yq ".hostname" <<< "${node}")
    local node_labels=$(yq ".kubernetes.labels" <<< "${node}")

    if [[ "${node_labels}" == "null" ]] || [[ -z "${node_labels}" ]]; then
        print_status "verbose" "${hostname}: Labels are not specified in the manifest"
        return
    fi

    local control_plane_main_node=$(manifest_read_yaml "[.nodes[] | select(.control_plane == true)] | .[0]")

    # Get the current labels of the node
    run_commands_on_node "${control_plane_main_node}" "sudo kubectl --kubeconfig /etc/kubernetes/admin.conf get node ${hostname} --output yaml | yq '.metadata.labels'"
    local current_node_labels="${RETURN_OUTPUT}"

    local labels_string=""
    while IFS= read -r label_key_value; do

        local trimmed_label="$(echo ${label_key_value} | tr -s ':' '=' | tr -d ' ' | tr -s '\n' ' ')"

        if [[  -n "$(echo ${current_node_labels} | grep -w "${label_key_value}")" ]]; then
            print_status "verbose" "${hostname}: Label ${trimmed_label}is already set on the node"
        else
            labels_string+="${trimmed_label} "
        fi
    done <<< "${node_labels}"

    if [[ -n "${labels_string}" ]]; then
        print_status "info" "${hostname}: Labeling node with labels: ${labels_string}"
        run_commands_on_node "${control_plane_main_node}" "sudo kubectl --kubeconfig /etc/kubernetes/admin.conf label --overwrite node ${hostname} ${labels_string}"
    fi
}


##########################################
# Renew certificates
##########################################
function kubernetes_kubeadm_certs_renew() {
    local node="$1"
    local hostname=$(yq ".hostname" <<< "${node}")

    # Get the CSR names
    run_commands_on_node "${node}" "sudo kubectl --kubeconfig /etc/kubernetes/admin.conf get csr --no-headers --ignore-not-found | awk '{print \$1}' | tr -s '\n' ' '"
    local csr_names="${RETURN_OUTPUT}"

    if [[ -n "${csr_names}" ]]; then
        print_status "info" "${hostname}: CSRs found, renewing the certificates"
        # Approve the CSRs
        run_commands_on_node "${node}" "sudo kubectl --kubeconfig /etc/kubernetes/admin.conf certificate approve ${csr_names}"

        # Wait for 30 seconds to allow the CSRs to be approved and issued
        sleep 30

        # Get the approved CSR names
        run_commands_on_node "${node}" "sudo kubectl --kubeconfig /etc/kubernetes/admin.conf get csr --no-headers --ignore-not-found | grep 'Approved,Issued' | awk '{print \$1}' | tr -s '\n' ' '"
        local approved_csr_names="${RETURN_OUTPUT}"
        if [[ -n "${approved_csr_names}" ]]; then
            print_status "info" "${hostname}: Approved CSRs found, deleting the remaining CSRs"
            run_commands_on_node "${node}" "sudo kubectl --kubeconfig /etc/kubernetes/admin.conf delete csr ${approved_csr_names}"
        else
            print_status "info" "${hostname}: No approved CSRs found"
        fi
    else
        print_status "verbose" "${hostname}: No CSRs found"
    fi
}
