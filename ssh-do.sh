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
        print_status "error" "$nodes_file file not found"
        exit 1
    fi

    print_status "info" "Running command on nodes from $nodes_file..."

    local bastion_enabled=$(yq e '.global.ssh_connection.use_bastion' "$nodes_file")
    local bastion_hostname=$(yq e '.bastion.hostname' "$nodes_file")
    local bastion_port=$(yq e '.bastion.port' "$nodes_file")
    local bastion_username=$(yq e '.bastion.username' "$nodes_file")
    local bastion_private_key=$(yq e '.bastion.private_key' "$nodes_file")

    if [ "$bastion_enabled" = "true" ]; then
        echo "Bastion hostname: $bastion_hostname"
        echo "Bastion port: $bastion_port"
        echo "Bastion username: $bastion_username"
        echo "Bastion private key: $bastion_private_key"

        proxy_jump_arg="-o ProxyJump=$bastion_username@$bastion_hostname:$bastion_port"
        bastion_message="via bastion $bastion_username@$bastion_hostname"
    else
        proxy_jump_arg=""
        bastion_message=""
    fi

    # Define how to connect to the node
    connect_through=$(yq e '.global.ssh_connection.connect_through' "$nodes_file")
    username=$(yq e ".global.ssh_connection.username" "$nodes_file")
    port=$(yq e ".global.ssh_connection.port" "$nodes_file")
    private_key=$(yq e ".global.ssh_connection.private_key" "$nodes_file")
    echo connect_through: $connect_through
    echo username: $username
    echo port: $port
    echo private_key: $private_key

    if [ -n "$private_key" ]; then
        private_key_arg="-i $private_key"
    else
        private_key_arg=""
    fi

    # Get the number of control-plane nodes
    local control_plane_count=$(yq e '.control_planes | length' "$nodes_file")
    for ((i=0; i<control_plane_count; i++)); do
        hostname=$(yq e ".control_planes[$i].hostname" "$nodes_file")
        public_ip=$(yq e ".control_planes[$i].public_ip" "$nodes_file")
        private_ip=$(yq e ".control_planes[$i].private_ip" "$nodes_file")

        echo hostname: $hostname
        echo public_ip: $public_ip
        echo private_ip: $private_ip

        connection_address=$public_ip
        if [ "$connect_through" = "hostname" ]; then
            connection_address=$hostname
        elif [ "$connect_through" = "private_ip" ]; then
            connection_address=$private_ip
        fi

        print_status "info" "Running '$cmd' on node $hostname ($connection_address) $bastion_message..."

        output=$(ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o GlobalKnownHostsFile=/dev/null $proxy_jump_arg $private_key_arg -l "$username" -p "$port" "$connection_address" "$cmd")
        echo "-------------------- OUTPUT from $hostname ($connection_address) --------------------"
        echo "$output"
        echo "-------------------- END OUTPUT from $hostname ($connection_address) -------------------- "

    done



    print_status "info" "Done"
}






# Run main function
main "$@"
