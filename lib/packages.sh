##########################################
# Install packages
##########################################
function packages_install() {
    local node="$1"

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
        print_status "info" "Installing containerd on node $node"

        run_commands_on_node $node "sudo apt-get update && sudo apt-get install -y containerd"
        run_commands_on_node $node "sudo mkdir -p /etc/containerd"
        run_commands_on_node $node "sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null"
        run_commands_on_node $node "sudo sed -ri 's/^(\s*)SystemdCgroup\s*=.*/\1SystemdCgroup = true/' /etc/containerd/config.toml"
        run_commands_on_node $node "sudo systemctl daemon-reload"
        run_commands_on_node $node "sudo systemctl enable --now containerd"
        run_commands_on_node $node "sudo systemctl restart containerd"
    else
        print_status "info" "containerd is already installed on node $node"
    fi

    run_commands_on_node $node "sudo test -f /etc/crictl.yaml && echo 'exists' || echo 'doesnotexist'"
    if [ "$RETURN_OUTPUT" = "doesnotexist" ]; then
        print_status "info" "Creating crictl configuration on node $node"

        run_commands_on_node $node "sudo tee /etc/crictl.yaml > /dev/null <<EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF"
    else
        print_status "info" "crictl configuration already exists on node $node"
    fi

    run_commands_on_node $node "sudo whereis kubelet | sed 's/^.*://g'"
    if [ -z "$RETURN_OUTPUT" ]; then
        print_status "info" "Installing kubelet kubeadm kubectl on node $node"

        run_commands_on_node $node "sudo mkdir -p -m 755 /etc/apt/keyrings"
        run_commands_on_node $node "curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg"
        run_commands_on_node $node "sudo chmod 0644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg"
        run_commands_on_node $node "echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list"
        run_commands_on_node $node "sudo apt-get update && \
            sudo apt-get install -y kubelet kubeadm kubectl && \
            sudo apt-mark hold kubelet kubeadm kubectl && \
            sudo systemctl enable --now kubelet"
    else
        print_status "info" "kubelet kubeadm kubectl are already installed on node $node"
    fi
}


##########################################
# Install Helm
##########################################
function packages_helm_install() {
    local node="$1"

    run_commands_on_node $node "sudo whereis helm | sed 's/^.*://g'"
    if [ -z "$RETURN_OUTPUT" ]; then
        print_status "info" "Installing helm on node $node"
        run_commands_on_node $node "curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
    else
        print_status "info" "helm is already installed on node $node"
    fi
}
