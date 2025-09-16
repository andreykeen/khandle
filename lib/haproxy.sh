##########################################
# Install haproxy
##########################################
function haproxy_configure() {
    local node="$1"

    run_commands_on_node $node "sudo whereis haproxy | sed 's/^.*://g'"
    if [ -z "$RETURN_OUTPUT" ]; then
        print_status "info" "Installing haproxy on node $node"
        run_commands_on_node $node "sudo apt-get update && sudo apt-get install -y haproxy \
            && sudo systemctl enable --now haproxy && sudo systemctl start haproxy"
    else
        print_status "info" "haproxy is already installed on node $node"
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

    print_status "info" "Configuring haproxy on node $node"
    run_commands_on_node $node "sudo tee /etc/haproxy/haproxy.cfg > /dev/null <<EOF
$haproxy_config
EOF"

    run_commands_on_node $node "sudo systemctl reload haproxy"
}
