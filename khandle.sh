#!/usr/bin/env bash

set -e

# Colours for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
LIGHT_BLUE='\033[1;34m'
NC='\033[0m' # No Colour


# Global variables
COMMAND=""
NODES_FILE=""
VERBOSE=true


# Function to print coloured output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "info")
            echo -e "${LIGHT_BLUE}[INFO]${NC} $message"
            ;;
        "success")
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
        "warning")
            echo -e "${YELLOW}[WARNING]${NC} $message"
            ;;
        "error")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
    esac
}

# Function to display usage
show_usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

Commands:
    apply    Apply the manifest to the cluster
    get      Get the status of the cluster
    help     Show this help message

Options:
    -m, --manifest <nodes.yaml>  Path to the nodes.yaml manifest file
    -v, --verbose                Enable verbose output
    -d, --dry-run                Show what would be executed without running commands

Examples:
    $0 apply -m nodes.yaml
    $0 get -m nodes.yaml
    $0 help

EOF
}

# Function to parse command line arguments
parse_arguments() {
    if [[ $# -eq 0 ]]; then
        show_usage
        exit 0
    fi

    while [[ $# -gt 0 ]]; do
        case $1 in
            apply)
                COMMAND="apply"
                shift
                ;;
            get)
                COMMAND="get"
                shift
                ;;
            help)
                show_usage
                exit 0
                ;;
            -m|--manifest)
                NODES_FILE="$2"
                shift 2
                ;;
            *)
                print_status "error" "Unknown command: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Function to validate arguments
validate_arguments() {
    if [ "$COMMAND" == "apply" ]; then
        if [ -z "$NODES_FILE" ]; then
            print_status "error" "Nodes file is required"
            show_usage
            exit 1
        fi
        if [ ! -f "$NODES_FILE" ]; then
            print_status "error" "Nodes file '$NODES_FILE' not found"
            exit 1
        fi
    fi
}


check_tools() {
    local required_utilities=(yq ssh)
    for utility in "${required_utilities[@]}"; do
        if [ -z "$(which ${utility})" ]; then
            print_status "error" "You must install '$utility'."
            exit 1
        fi
    done
}

run_commands_on_node() {
    local node="$1"
    local cmd="$2"
    local nodes_file="$NODES_FILE"


    ####################################
    ##### Configure SSH connection #####

    local ssh_port=$(yq e ".global.ssh_connection.port" "$nodes_file")
    local ssh_username=$(yq e ".global.ssh_connection.username" "$nodes_file")
    local ssh_private_key=$(yq e ".global.ssh_connection.private_key" "$nodes_file")
    local ssh_connect_through=$(yq e '.global.ssh_connection.connect_through' "$nodes_file")
    local bastion_enabled=$(yq e '.global.ssh_connection.use_bastion' "$nodes_file")
    # print_status "info" "SSH port: $ssh_port"
    # print_status "info" "SSH username: $ssh_username"
    # print_status "info" "SSH private key: $ssh_private_key"
    # print_status "info" "SSH connect through: $ssh_connect_through"
    # print_status "info" "Bastion enabled: $bastion_enabled"

    local ssh_port_arg=""
    local ssh_username_arg=""
    local ssh_private_key_arg=""

    if [ -n "$ssh_port" ] && [ "$ssh_port" != "null" ]; then
        ssh_port_arg="-p $ssh_port"
    fi
    if [ -n "$ssh_username" ] && [ "$ssh_username" != "null" ]; then
        ssh_username_arg="-l $ssh_username"
    fi
    if [ -n "$ssh_private_key" ] && [ "$ssh_private_key" != "null" ]; then
        # Expand tilde to home directory
        expanded_ssh_key=$(eval echo "$ssh_private_key")
        ssh_private_key_arg="-i $expanded_ssh_key"
    fi


    ########################################
    ##### Configure bastion connection #####

    local bastion_port_arg=""
    local bastion_username_arg=""
    local bastion_private_key_arg=""
    local bastion_message=""

    if [ "$bastion_enabled" = "true" ]; then
        local bastion_address=$(yq e '.bastion.address' "$nodes_file")
        local bastion_port=$(yq e '.bastion.port' "$nodes_file")
        local bastion_username=$(yq e '.bastion.username' "$nodes_file")
        local bastion_private_key=$(yq e '.bastion.private_key' "$nodes_file")
        # print_status "info" "Bastion address: $bastion_address"
        # print_status "info" "Bastion port: $bastion_port"
        # print_status "info" "Bastion username: $bastion_username"
        # print_status "info" "Bastion private key: $bastion_private_key"

        if [ -z "$bastion_address" ]; then
            print_status "error" "Bastion address is required"
            exit 1
        fi
        if [ -n "$bastion_port" ] && [ "$bastion_port" != "null" ]; then
            bastion_port_arg="-p $bastion_port"
        fi
        if [ -n "$bastion_username" ] && [ "$bastion_username" != "null" ]; then
            bastion_username_arg="-l $bastion_username"
        fi
        if [ -n "$bastion_private_key" ] && [ "$bastion_private_key" != "null" ]; then
            # Expand tilde to home directory
            expanded_bastion_key=$(eval echo "$bastion_private_key")
            bastion_private_key_arg="-i $expanded_bastion_key"
        fi

        bastion_message="via bastion $bastion_address"
    fi

    local ssh_args="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=accept-new -o GlobalKnownHostsFile=/dev/null"

    hostname="$node"
    public_ip=$(yq e '.control_planes[] | select(.hostname == "'$node'") | .public_ip' "$nodes_file")
    private_ip=$(yq e '.control_planes[] | select(.hostname == "'$node'") | .private_ip' "$nodes_file")

    # print_status "info" "Hostname: $hostname"
    # print_status "info" "Public IP: $public_ip"
    # print_status "info" "Private IP: $private_ip"

    connection_address=$public_ip
    if [ "$ssh_connect_through" = "hostname" ]; then
        connection_address=$hostname
    elif [ "$ssh_connect_through" = "private_ip" ]; then
        connection_address=$private_ip
    fi

    print_status "info" "Running '$cmd' on node $hostname ($connection_address) $bastion_message..."
    # set -x
    if [ "$bastion_enabled" = "true" ]; then
        output=$(ssh $ssh_args -o ProxyCommand="ssh -W %h:%p $bastion_private_key_arg $bastion_username_arg $bastion_port_arg $bastion_address" \
        $ssh_private_key_arg $ssh_username_arg $ssh_port_arg $connection_address "$cmd")
    else
        output=$(ssh $ssh_args $ssh_private_key_arg $ssh_username_arg $ssh_port_arg $connection_address "$cmd")
    fi
    echo "-------------------- OUTPUT from $hostname ($connection_address) --------------------"
    echo "$output"
    echo "-------------------- END OUTPUT from $hostname ($connection_address) -------------------- "
}


##########################################
# Interact with the nodes
##########################################
function manage_nodes() {
    if [ "$VERBOSE" = true ]; then
        print_status "info" "Managing all nodes"
    fi

    manage_control_plane

    manage_worker_nodes
}


##########################################
# Interact with the control plane nodes
##########################################
function manage_control_plane() {
    if [ "$VERBOSE" = true ]; then
        print_status "info" "Managing control plane nodes only"
    fi


    local control_plane_count=$(yq e '.control_planes | length' "$NODES_FILE")
    for ((i=0; i<control_plane_count; i++)); do
        hostname=$(yq e ".control_planes[$i].hostname" "$NODES_FILE")
        print_status "info" "Running command on node $hostname"
        # run_commands_on_node $hostname "sudo df -h"
        install_runtime $hostname
        install_haproxy $hostname

    done
}


##########################################
# Interact with the worker nodes
##########################################
function manage_worker_nodes() {
    if [ "$VERBOSE" = true ]; then
        print_status "info" "Managing worker nodes only"
    fi

}


##########################################
# Preconfigure nodes
##########################################
function preconfigure_nodes() {
    local node="$1"
    if [ "$VERBOSE" = true ]; then
        print_status "info" "Preconfiguring nodes on node $node"
    fi

    run_commands_on_node $node "sudo tee /etc/sysctl.d/kubernetes.conf > /dev/null <<EOF
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF"

    run_commands_on_node $node "sudo sysctl --system"

}


##########################################
# Install runtime
##########################################
function install_runtime() {
    local node="$1"
    if [ "$VERBOSE" = true ]; then
        print_status "info" "Installing runtime on node $node"
    fi

    run_commands_on_node $node "sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates curl gpg containerd"

    run_commands_on_node $node "sudo tee /etc/crictl.yaml > /dev/null <<EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF"

    run_commands_on_node $node "sudo mkdir -p -m 755 /etc/apt/keyrings"
    run_commands_on_node $node "curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg"
    run_commands_on_node $node "echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list"
    run_commands_on_node $node "sudo apt-get update && \
        sudo apt-get install -y kubelet kubeadm kubectl && \
        sudo apt-mark hold kubelet kubeadm kubectl && \
        sudo systemctl enable --now kubelet"
}


##########################################
# Install haproxy
##########################################
function install_haproxy() {
    local node="$1"
    if [ "$VERBOSE" = true ]; then
        print_status "info" "Installing haproxy on node $node"
    fi

    run_commands_on_node $node "sudo apt-get update && sudo apt-get install -y haproxy"
    run_commands_on_node $node "sudo tee /etc/haproxy/haproxy.cfg > /dev/null <<EOF
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
    mode    http
    option  httplog
    option  dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000

frontend control-plane
    bind :6444
    default_backend control-plane

backend control-plane
    balance roundrobin
    server node1 localhost:80

EOF"

    run_commands_on_node $node "sudo systemctl enable --now haproxy && sudo systemctl restart haproxy"
}

##########################################
# Initialise control plane
##########################################
function initialise_control_plane() {
    local node="$1"
    if [ "$VERBOSE" = true ]; then
        print_status "info" "Initialising control plane on node $node"
    fi
}


# Run main function
main() {

    parse_arguments "$@"
    validate_arguments
    check_tools

    case $COMMAND in
        apply)
            print_status "info" "Applying the manifest to the cluster"
            manage_nodes
            ;;
        get)
            print_status "info" "Getting the status of the cluster"
            ;;
        help)
            show_usage
            ;;
    esac

    print_status "success" "Operation completed"
}






# Run main function
main "$@"
