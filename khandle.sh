#!/usr/bin/env bash

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
ALL_NODES=""
CONTROL_PLANE_MAIN_NODE=""
VERBOSE=false
RETURN_OUTPUT=""


source lib/nodes.sh
source lib/cni.sh
source lib/kubeadm.sh
source lib/kubectl.sh
source lib/kubelet.sh
source lib/packages.sh
source lib/ssh.sh
source lib/sysctl.sh


##########################################
# Print coloured output
##########################################
function print_status() {
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


##########################################
# Display usage
##########################################
function show_usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

Commands:
    install    Install the cluster
    update     Update the cluster
    help       Show this help message

Options:
    -m, --manifest <nodes.yaml>  Path to the nodes.yaml manifest file
    -v, --verbose                Enable verbose output
    -d, --dry-run                Show what would be executed without running commands

Examples:
    $0 install -m nodes.yaml
    $0 update -m nodes.yaml
    $0 help

EOF
}


##########################################
# Parse command line arguments
##########################################
function parse_arguments() {
    if [[ $# -eq 0 ]]; then
        show_usage
        exit 0
    fi

    while [[ $# -gt 0 ]]; do
        case $1 in
            install)
                COMMAND="install"
                shift
                ;;
            update)
                COMMAND="update"
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


##########################################
# Validate arguments
##########################################
function validate_arguments() {
    if [ "$COMMAND" == "install" ]; then
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


##########################################
# Check tools
##########################################
function check_tools() {
    local required_utilities=(yq ssh)
    for utility in "${required_utilities[@]}"; do
        if [ -z "$(which ${utility})" ]; then
            print_status "error" "You must install '$utility'."
            exit 1
        fi
    done
}


##########################################
# Main function
##########################################
function main() {

    parse_arguments "$@"
    validate_arguments
    check_tools

    # Create a new structure with both arrays preserved under 'nodes'
    ALL_NODES=$(yq e '.nodes = (.control_planes + .worker_nodes) | with_entries(select(.key == "nodes"))' "$NODES_FILE")

    # Get the main control plane node
    CONTROL_PLANE_MAIN_NODE=$(yq e ".control_planes[0].hostname" "$NODES_FILE")
    if [ "$CONTROL_PLANE_MAIN_NODE" = "null" ] || [ -z "$CONTROL_PLANE_MAIN_NODE" ]; then
        print_status "error" "There should be at least one control plane node in the manifest"
        exit 1
    fi

    case $COMMAND in
        install)
            print_status "info" "Installing the cluster"
            nodes_manage
            ;;
        update)
            print_status "info" "Updating the cluster"
            ;;
        help)
            show_usage
            ;;
    esac

    print_status "success" "Operation completed"
}


##########################################
# Run main function
##########################################
main "$@"
