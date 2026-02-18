##########################################
# Configure kubeapiserver interface
##########################################
function os_configuration_kubeapiserver_interface() {
    local node="$1"

    local hostname=$(yq ".hostname" <<< "$node")
    local control_plane_endpoint=$(manifest_read_yaml ".cluster_network.control_plane_endpoint")
    local control_plane_endpoint_ip=$(echo "$control_plane_endpoint" | awk -F':' '{print $1}')

    run_commands_on_node "${node}" "sudo tee /tmp/kubeapiserver.service > /dev/null <<EOF
[Unit]
Description=Create kubeapiserver interface
After=systemd-modules-load.service
Before=network-pre.target
Wants=network-pre.target
DefaultDependencies=no

[Service]
Type=oneshot
ExecStartPre=/sbin/modprobe dummy
ExecStart=/sbin/ip link add kubeapiserver type dummy
ExecStartPost=/sbin/ip addr add ${control_plane_endpoint_ip}/32 dev kubeapiserver
ExecStop=/sbin/ip link delete kubeapiserver
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF"

    # Check if the kubeapiserver interface is already created
    run_commands_on_node "${node}" "test ! -f /etc/systemd/system/kubeapiserver.service && echo 'doesnotexist' || echo 'exists'"
    # If the kubeapiserver interface is not created, then create it
    if [[ "$RETURN_OUTPUT" == "doesnotexist" ]]; then
        print_status "info" "${hostname}: Creating kubeapiserver interface"
        run_commands_on_node "${node}" "sudo mv /tmp/kubeapiserver.service /etc/systemd/system/kubeapiserver.service && \
            sudo systemctl daemon-reload && \
            sudo systemctl enable kubeapiserver.service && \
            sudo systemctl start kubeapiserver.service"
    else
        # Check if the kubeapiserver interface is different from the expected configuration
        run_commands_on_node "${node}" "sudo diff -q /tmp/kubeapiserver.service /etc/systemd/system/kubeapiserver.service || true"
        # If the difference is not empty, then update the kubeapiserver service file
        if [[ -n "$RETURN_OUTPUT" ]]; then
            print_status "info" "${hostname}: Updating kubeapiserver interface"
            run_commands_on_node "${node}" "sudo mv /tmp/kubeapiserver.service /etc/systemd/system/kubeapiserver.service"
            run_commands_on_node "${node}" "sudo systemctl daemon-reload && \
                sudo systemctl enable kubeapiserver.service && \
                sudo systemctl restart kubeapiserver.service"
        else
            print_status "info" "${hostname}: Kubeapiserver interface is already up to date"
        fi
    fi
}


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
