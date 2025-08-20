#!/usr/bin/env bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "info")
            echo -e "${BLUE}[INFO]${NC} $message"
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


check_tools() {
    local required_utilities=(yq ssh)
    for utility in "${required_utilities[@]}"; do
        if [ -z "$(which ${utility})" ]; then
            print_status "error" "You must install '$utility'."
            exit 1
        fi
    done
}




# Run main function
main() {
    local nodes_file="$1"
    local cmd="$2"

    check_tools

    if [ -z "$nodes_file" ] || [ -z "$cmd" ]; then
        print_status "error" "Usage: $0 <nodes.yaml> <command>"
        exit 1
    fi

    # Check if YAML file exists
    if [ ! -f "$nodes_file" ]; then
        print_status "error" "$nodes_file file not found in curren"
        exit 1
    fi

    print_status "info" "Running command on nodes from $nodes_file..."

    local bastion_enabled=$(yq e '.cluster_nodes.bastion.enabled' "$nodes_file")
    local bastion_hostname=$(yq e '.cluster_nodes.bastion.hostname' "$nodes_file")
    local bastion_port=$(yq e '.cluster_nodes.bastion.port' "$nodes_file")
    local bastion_username=$(yq e '.cluster_nodes.bastion.username' "$nodes_file")
    local bastion_private_key=$(yq e '.cluster_nodes.bastion.private_key' "$nodes_file")

    if [ "$bastion_enabled" = "true" ]; then
        echo "Bastion hostname: $bastion_hostname"
        echo "Bastion port: $bastion_port"
        echo "Bastion username: $bastion_username"
        echo "Bastion private key: $bastion_private_key"

        ssh_bastion_host="$bastion_username@$bastion_hostname:$bastion_port"
        bastion_message="via bastion $bastion_username@$bastion_hostname"
    else
        ssh_bastion_host=""
        bastion_message=""
    fi

    # Use hostname to connect to the node instead of IP address
    local use_hostname_to_connect=$(yq e '.cluster_nodes.global.ssh_connection.use_hostname_to_connect' "$nodes_file")
    # Get the number of control-plane nodes
    local control_plane_count=$(yq e '.cluster_nodes.control_plane | length' "$nodes_file")

    for ((i=0; i<control_plane_count; i++)); do
        node_host=$(yq e ".cluster_nodes.control_plane[$i].hostname" "$nodes_file")
        node_ip=$(yq e ".cluster_nodes.control_plane[$i].public_ip" "$nodes_file")
        node_user=$(yq e ".cluster_nodes.global.ssh_connection.username" "$nodes_file")
        node_port=$(yq e ".cluster_nodes.global.ssh_connection.port" "$nodes_file")
        node_key=$(yq e ".cluster_nodes.global.ssh_connection.private_key" "$nodes_file")

        echo use_hostname_to_connect: $use_hostname_to_connect
        echo node_host: $node_host
        echo node_ip: $node_ip
        echo node_user: $node_user
        echo node_port: $node_port
        echo node_key: $node_key

        if [ "$use_hostname_to_connect" = "true" ]; then
            node_ip=$node_host
        fi

        print_status "info" "Running '$cmd' on node $node_host ($node_ip) $bastion_message..."

        output=$(ssh -o ProxyJump="$ssh_bastion_host" -l "$node_user" -p "$node_port" "$node_ip" "$cmd")
        echo "-------------------- OUTPUT from $node_host ($node_ip) --------------------"
        echo "$output"
        echo "-------------------- END OUTPUT from $node_host ($node_ip) ----------------"

    done



    print_status "info" "Done"
}






# Run main function
main "$@"
