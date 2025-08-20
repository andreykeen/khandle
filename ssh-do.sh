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


    local bastion_hostname=$(yq e '.cluster_nodes.bastion.hostname' "$nodes_file")
    local bastion_port=$(yq e '.cluster_nodes.bastion.port' "$nodes_file")
    local bastion_username=$(yq e '.cluster_nodes.bastion.username' "$nodes_file")

    echo "Bastion hostname: $bastion_hostname"
    echo "Bastion port: $bastion_port"
    echo "Bastion username: $bastion_username"

    # SSH to the bastion host
    print_status "info" "Connecting to bastion host $bastion_username@$bastion_hostname on port $bastion_port..."
    ssh -p "$bastion_port" -l "$bastion_username" "$bastion_hostname"

    # Run the command on the bastion host
    # print_status "info" "Running command on bastion host $bastion_username@$bastion_hostname on port $bastion_port..."
    # ssh -p "$bastion_port" -l "$bastion_username" "$bastion_hostname" "$cmd"

    print_status "info" "Done"
}






# Run main function
main "$@"
