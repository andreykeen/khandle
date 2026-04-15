##########################################
# Install packages
##########################################
function packages_apt_install() {
    local node="$1"
    local hostname=$(yq ".hostname" <<< "${node}")

    # Check if the APT packages are listed in the manifest
    local apt_packages=$(manifest_read_yaml ".global.os.apt_packages[]")
    if [[ "${apt_packages}" == "null" ]] || [[ -z "${apt_packages}" ]]; then
        print_status "verbose" "${hostname}: APT packages are not listed in the manifest"
        return
    fi

    local apt_packages_string=$(echo "${apt_packages[@]}" | tr '\n' ' ')

    print_status "info" "${hostname}: Installing APT packages: ${apt_packages_string}"
    run_commands_on_node "${node}" "sudo apt-get update && \
        sudo apt-get install -y ${apt_packages_string}"

    run_commands_on_node "${node}" "sudo curl -fsSL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq && sudo chmod +x /usr/local/bin/yq"
}


##########################################
# Install runtime
##########################################
function packages_runtime_install() {
    local node="$1"
    local hostname=$(yq ".hostname" <<< "${node}")

    run_commands_on_node "$node" "sudo whereis containerd | sed 's/^.*://g'"
    if [[ -z "$RETURN_OUTPUT" ]]; then
        print_status "info" "${hostname}: Installing containerd"
        run_commands_on_node "${node}" "sudo apt-get update && sudo apt-get install -y containerd"
        run_commands_on_node "${node}" "sudo mkdir -p /etc/containerd"
        run_commands_on_node "${node}" "sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null"
        run_commands_on_node "${node}" "sudo sed -ri 's/^(\s*)SystemdCgroup\s*=.*/\1SystemdCgroup = true/' /etc/containerd/config.toml"
        run_commands_on_node "${node}" "sudo systemctl daemon-reload"
        run_commands_on_node "${node}" "sudo systemctl enable --now containerd"
        run_commands_on_node "${node}" "sudo systemctl restart containerd"
    else
        print_status "verbose" "${hostname}: containerd is already installed"
    fi

    run_commands_on_node "${node}" "sudo test -f /etc/crictl.yaml && echo 'exists' || echo 'doesnotexist'"
    if [[ "${RETURN_OUTPUT}" == "doesnotexist" ]]; then
        print_status "info" "${hostname}: Creating crictl configuration"
        run_commands_on_node "${node}" "sudo tee /etc/crictl.yaml > /dev/null <<EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF"
    else
        print_status "verbose" "${hostname}: crictl configuration already exists"
    fi
}


##########################################
# Install haproxy
##########################################
# How to check if haproxy is running?
# curl -k https://169.254.10.10:6444/version
function packages_haproxy_install() {
    local node="$1"
    local hostname=$(yq ".hostname" <<< "${node}")


    # Check if the control plane interface is enabled in the manifest
    local control_plane_interface=$(manifest_read_yaml ".cluster_network.control_plane_interface")
    if [[ "${control_plane_interface}" == "null" ]] || [[ -z "${control_plane_interface}" ]] || [[ "${control_plane_interface}" == "false" ]]; then
        print_status "verbose" "${hostname}: Control plane interface is not enabled. Skipping haproxy installation"
        return
    fi

    run_commands_on_node "${node}" "sudo whereis haproxy | sed 's/^.*://g'"
    if [[ -z "$RETURN_OUTPUT" ]]; then
        print_status "info" "${hostname}: Installing haproxy"
        run_commands_on_node "${node}" "sudo apt-get update && sudo apt-get install -y haproxy \
            && sudo systemctl enable --now haproxy && sudo systemctl start haproxy"
    else
        print_status "verbose" "${hostname}: haproxy is already installed"
    fi

    # Generate HAProxy config with dynamic server entries
    local haproxy_config="
global
    log /dev/log    local0
    log /dev/log    local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000

frontend control-plane
    bind 0.0.0.0:6444
    mode tcp
    default_backend control-plane

backend control-plane
    mode tcp
    balance roundrobin
    option tcp-check"

    # Add server entries for each control plane node
    local cp_nodes=$(manifest_read_yaml "[.nodes[] | select(.control_plane == true)]")
    local cp_nodes_count=$(echo "${cp_nodes}" | yq length)
    local i
    for ((i=0; i<cp_nodes_count; i++)); do
        local backend_host=$(yq ".[$i].hostname" <<< "${cp_nodes}")
        local backend_ip=$(yq ".[$i].kubernetes.apiserver_advertise_address" <<< "${cp_nodes}")
        haproxy_config+="
    server $backend_host $backend_ip:6443 check"
    done

    # Create a new haproxy config file in /tmp
    run_commands_on_node "${node}" "sudo tee /tmp/haproxy.cfg > /dev/null <<EOF
$haproxy_config
EOF"

    run_commands_on_node "${node}" "sudo diff -q /tmp/haproxy.cfg /etc/haproxy/haproxy.cfg || true"
    # If the return output is not empty, then update the haproxy config file
    if [[ -n "$RETURN_OUTPUT" ]]; then
        print_status "info" "${hostname}: Updating haproxy config file"
        run_commands_on_node "${node}" "sudo mv /tmp/haproxy.cfg /etc/haproxy/haproxy.cfg && sudo systemctl reload haproxy"
    else
        print_status "verbose" "${hostname}: haproxy config file is already up to date"
    fi
}


##########################################
# Install Helm
##########################################
function packages_helm_install() {
    local node="$1"

    local hostname=$(yq ".hostname" <<< "$node")
    print_status "info" "$hostname: Installing Helm"

    run_commands_on_node "$node" "sudo whereis helm | sed 's/^.*://g'"
    if [ -z "$RETURN_OUTPUT" ]; then
        print_status "info" "$hostname: Installing helm"
        run_commands_on_node "$node" "curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
    else
        print_status "info" "$hostname: helm is already installed"
    fi
}
