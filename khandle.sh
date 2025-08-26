#!/usr/bin/env bash

set -e

# Colours for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Colour


# Function to print coloured output
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

run_commands_on_nodes() {
    local nodes_file="$1"
    local cmd="$2"

    ##### Configure SSH connection #####

    local ssh_port=$(yq e ".global.ssh_connection.port" "$nodes_file")
    local ssh_username=$(yq e ".global.ssh_connection.username" "$nodes_file")
    local ssh_private_key=$(yq e ".global.ssh_connection.private_key" "$nodes_file")
    local ssh_connect_through=$(yq e '.global.ssh_connection.connect_through' "$nodes_file")
    local bastion_enabled=$(yq e '.global.ssh_connection.use_bastion' "$nodes_file")
    print_status "info" "SSH port: $ssh_port"
    print_status "info" "SSH username: $ssh_username"
    print_status "info" "SSH private key: $ssh_private_key"
    print_status "info" "SSH connect through: $ssh_connect_through"
    print_status "info" "Bastion enabled: $bastion_enabled"

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
        print_status "info" "Bastion address: $bastion_address"
        print_status "info" "Bastion port: $bastion_port"
        print_status "info" "Bastion username: $bastion_username"
        print_status "info" "Bastion private key: $bastion_private_key"

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

    # Get the number of control-plane nodes
    local control_plane_count=$(yq e '.control_planes | length' "$nodes_file")
    for ((i=0; i<control_plane_count; i++)); do
        hostname=$(yq e ".control_planes[$i].hostname" "$nodes_file")
        public_ip=$(yq e ".control_planes[$i].public_ip" "$nodes_file")
        private_ip=$(yq e ".control_planes[$i].private_ip" "$nodes_file")

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

    done
}


function manage_nodes() {
    local nodes_file="$1"
    local cmd="$2"
}

function manage_control_plane() {
    local nodes_file="$1"
    local cmd="$2"
}

function manage_worker_nodes() {
    local nodes_file="$1"
    local cmd="$2"
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





    print_status "info" "Done"
}






# Run main function
main "$@"
