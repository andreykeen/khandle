#!/usr/bin/env bash

# Colours for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
LIGHT_BLUE='\033[1;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Colour

# Global variables
VERBOSE="false"
DRY_RUN="false"
RETURN_OUTPUT=""


source lib/manifest.sh
source lib/nodes.sh
source lib/ssh.sh
source lib/os.sh
source lib/packages.sh
source lib/kubernetes.sh
source lib/cni.sh


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
            echo -e "${RED}[ERROR]${NC} $message" >&2
            ;;
        "verbose")
            if [[ "${VERBOSE}" == "true" ]]; then
                echo -e "${PURPLE}[VERBOSE]${NC} $message"
            fi
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
    apply                     Apply the cluster
    check_ssh_connections     Check SSH connections
    render_manifest           Print the fully resolved manifest to stdout
    help                      Show this help message

Options:
    -m, --manifest <nodes.yaml>  Path to the nodes.yaml manifest file
    -v, --verbose                Enable verbose output
    -d, --dry-run                Show what would be executed without running commands
    -n, --nodes <nodes_names>    Comma separated list of node names to work with

Examples:
    $0 apply -m nodes.yaml
    $0 check_ssh_connections -m nodes.yaml
    $0 render_manifest -m nodes.yaml
    $0 help

EOF
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

    # parse_arguments "$@"

    if [[ $# -eq 0 ]]; then
        show_usage
        exit 0
    fi

    local command=""
    local manifest_file=""
    local nodes_names=""
    while [[ $# -gt 0 ]]; do
        case $1 in
            apply)
                command="apply"
                shift
                ;;
            check_ssh_connections)
                command="check_ssh_connections"
                shift
                ;;
            render_manifest)
                command="render_manifest"
                shift
                ;;
            help)
                show_usage
                exit 0
                ;;
            -m|--manifest)
                manifest_file="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE="true"
                shift
                ;;
            -d|--dry-run)
                DRY_RUN="true"
                shift
                ;;
            -n|--nodes)
                nodes_names="$2"
                shift 2
                ;;
            *)
                print_status "error" "Unknown command: $1"
                show_usage
                exit 1
                ;;
        esac
    done


    if [ "$command" == "apply" ] || [ "$command" == "render_manifest" ]; then
        if [ -z "$manifest_file" ]; then
            print_status "error" "Manifest file is required"
            show_usage
            exit 1
        fi
        if [ ! -f "$manifest_file" ]; then
            print_status "error" "Manifest file '$manifest_file' not found"
            exit 1
        fi
    fi

    manifest_read_yaml_file "$manifest_file"

    check_tools

    case $command in
        apply)
            print_status "info" "Applying the cluster"
            nodes_install_cluster "$nodes_names"
            ;;
        check_ssh_connections)
            print_status "info" "Checking SSH connections"
            os_check_ssh_connections
            ;;
        render_manifest)
            echo "$MANIFEST_DATA"
            exit 0
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
