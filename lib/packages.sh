##########################################
# Install packages
##########################################
function packages_system_install() {
    local node="$1"

    local hostname=$(yq ".hostname" <<< "$node")
    print_status "info" "$hostname: Installing system packages"

    run_commands_on_node "$node" "sudo apt-get update && \
        sudo apt-get install -y apt-transport-https ca-certificates curl gpg conntrack"

    run_commands_on_node "$node" "sudo curl -fsSL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq && sudo chmod +x /usr/local/bin/yq"
}


##########################################
# Install runtime
##########################################
function packages_runtime_install() {
    local node="$1"

    local hostname=$(yq ".hostname" <<< "$node")
    print_status "info" "$hostname: Installing runtime packages"

    run_commands_on_node "$node" "sudo whereis containerd | sed 's/^.*://g'"
    if [ -z "$RETURN_OUTPUT" ]; then
        print_status "info" "$hostname: Installing containerd"

        run_commands_on_node "$node" "sudo apt-get update && sudo apt-get install -y containerd"
        run_commands_on_node "$node" "sudo mkdir -p /etc/containerd"
        run_commands_on_node "$node" "sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null"
        run_commands_on_node "$node" "sudo sed -ri 's/^(\s*)SystemdCgroup\s*=.*/\1SystemdCgroup = true/' /etc/containerd/config.toml"
        run_commands_on_node "$node" "sudo systemctl daemon-reload"
        run_commands_on_node "$node" "sudo systemctl enable --now containerd"
        run_commands_on_node "$node" "sudo systemctl restart containerd"
    else
        print_status "info" "$hostname: containerd is already installed"
    fi

    run_commands_on_node "$node" "sudo test -f /etc/crictl.yaml && echo 'exists' || echo 'doesnotexist'"
    if [ "$RETURN_OUTPUT" = "doesnotexist" ]; then
        print_status "info" "$hostname: Creating crictl configuration"

        run_commands_on_node "$node" "sudo tee /etc/crictl.yaml > /dev/null <<EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF"
    else
        print_status "info" "$hostname: crictl configuration already exists"
    fi
}


##########################################
# Install haproxy
##########################################
function packages_haproxy_install() {
    local node="$1"

    local hostname=$(yq ".hostname" <<< "$node")

    run_commands_on_node "$node" "sudo whereis haproxy | sed 's/^.*://g'"
    if [ -z "$RETURN_OUTPUT" ]; then
        print_status "info" "$hostname: Installing haproxy"
        run_commands_on_node "$node" "sudo apt-get update && sudo apt-get install -y haproxy \
            && sudo systemctl enable --now haproxy && sudo systemctl start haproxy"
    else
        print_status "info" "$hostname: haproxy is already installed"
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
    local cp_nodes_count=$(echo "$cp_nodes" | yq length)
    local i
    for ((i=0; i<cp_nodes_count; i++)); do
        local backend_host=$(yq ".[$i].hostname" <<< "$cp_nodes")
        local backend_ip=$(yq ".[$i].private_ip" <<< "$cp_nodes")
        haproxy_config+="
    server $backend_host $backend_ip:6443 check"
    done

    print_status "info" "$hostname: Configuring haproxy"
    run_commands_on_node "$node" "sudo tee /etc/haproxy/haproxy.cfg > /dev/null <<EOF
$haproxy_config
EOF
sudo systemctl reload haproxy"
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
