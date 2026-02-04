##########################################
# Configure sysctl
##########################################
function sysctl_configuration() {
    local node="$1"

    local hostname=$(yq ".hostname" <<< "$node")
    print_status "info" "$hostname: Configuring sysctl"

    run_commands_on_node "$node" "sudo tee /etc/sysctl.d/kubernetes.conf > /dev/null <<EOF
net.ipv4.ip_forward = 1
EOF
sudo sysctl -p /etc/sysctl.d/kubernetes.conf"
}


##########################################
# Load modules
##########################################
function load_modules() {
    local node="$1"

    local hostname=$(yq ".hostname" <<< "$node")
    print_status "info" "$hostname: Loading modules"

    run_commands_on_node "$node" "sudo tee /etc/modules-load.d/k8s.conf > /dev/null <<EOF
overlay
br_netfilter
EOF
sudo modprobe overlay br_netfilter"
}
