##########################################
# Install packages
##########################################
function packages_system_install() {
    local node="$1"

    print_status "info" "$node: Installing system packages"

    run_commands_on_node $node "sudo apt-get update && \
        sudo apt-get install -y apt-transport-https ca-certificates curl gpg"

    run_commands_on_node $node "sudo curl -fsSL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq && sudo chmod +x /usr/local/bin/yq"
}


##########################################
# Install runtime
##########################################
function packages_runtime_install() {
    local node="$1"

    run_commands_on_node $node "sudo whereis containerd | sed 's/^.*://g'"
    if [ -z "$RETURN_OUTPUT" ]; then
        print_status "info" "$node: Installing containerd"

        run_commands_on_node $node "sudo apt-get update && sudo apt-get install -y containerd"
        run_commands_on_node $node "sudo mkdir -p /etc/containerd"
        run_commands_on_node $node "sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null"
        run_commands_on_node $node "sudo sed -ri 's/^(\s*)SystemdCgroup\s*=.*/\1SystemdCgroup = true/' /etc/containerd/config.toml"
        run_commands_on_node $node "sudo systemctl daemon-reload"
        run_commands_on_node $node "sudo systemctl enable --now containerd"
        run_commands_on_node $node "sudo systemctl restart containerd"
    else
        print_status "info" "$node: containerd is already installed"
    fi

    run_commands_on_node $node "sudo test -f /etc/crictl.yaml && echo 'exists' || echo 'doesnotexist'"
    if [ "$RETURN_OUTPUT" = "doesnotexist" ]; then
        print_status "info" "$node: Creating crictl configuration"

        run_commands_on_node $node "sudo tee /etc/crictl.yaml > /dev/null <<EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF"
    else
        print_status "info" "$node: crictl configuration already exists"
    fi
}


##########################################
# Install Kubernetes
##########################################
function packages_kubernetes_install() {
    local node="$1"

    run_commands_on_node $node "sudo whereis kubelet | sed 's/^.*://g'"
    if [ -z "$RETURN_OUTPUT" ]; then
        print_status "info" "$node: Installing kubelet kubeadm kubectl"

        run_commands_on_node $node "sudo mkdir -p -m 755 /etc/apt/keyrings"
        run_commands_on_node $node "curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg"
        run_commands_on_node $node "sudo chmod 0644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg"
        run_commands_on_node $node "echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list"
        run_commands_on_node $node "sudo apt-get update && \
            sudo apt-get install -y kubelet kubeadm kubectl && \
            sudo apt-mark hold kubelet kubeadm kubectl && \
            sudo systemctl enable --now kubelet"
    else
        print_status "info" "$node: kubelet kubeadm kubectl are already installed"
    fi

}


##########################################
# Install haproxy
##########################################
function packages_haproxy_install() {
    local node="$1"

    run_commands_on_node $node "sudo whereis haproxy | sed 's/^.*://g'"
    if [ -z "$RETURN_OUTPUT" ]; then
        print_status "info" "$node: Installing haproxy"
        run_commands_on_node $node "sudo apt-get update && sudo apt-get install -y haproxy \
            && sudo systemctl enable --now haproxy && sudo systemctl start haproxy"
    else
        print_status "info" "$node: haproxy is already installed"
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
    local cp_count=$(yq e '.control_planes | length' "$NODES_FILE")
    for ((j=0; j<cp_count; j++)); do
        j_hostname=$(yq e ".control_planes[$j].hostname" "$NODES_FILE")
        j_public_ip=$(yq e ".control_planes[$j].public_ip" "$NODES_FILE")
        j_private_ip=$(yq e ".control_planes[$j].private_ip" "$NODES_FILE")
        haproxy_config+="
    server $j_hostname $j_private_ip:6443 check"
    done

    print_status "info" "$node: Configuring haproxy"
    run_commands_on_node $node "sudo tee /etc/haproxy/haproxy.cfg > /dev/null <<EOF
$haproxy_config
EOF"

    run_commands_on_node $node "sudo systemctl reload haproxy"
}


##########################################
# Install Helm
##########################################
function packages_helm_install() {
    local node="$1"

    run_commands_on_node $node "sudo whereis helm | sed 's/^.*://g'"
    if [ -z "$RETURN_OUTPUT" ]; then
        print_status "info" "$node: Installing helm"
        run_commands_on_node $node "curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
    else
        print_status "info" "$node: helm is already installed"
    fi
}
