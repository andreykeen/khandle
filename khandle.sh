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
VERBOSE=false
RETURN_OUTPUT=""


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

    # Create a new structure with both arrays preserved under 'nodes'
    local all_nodes=$(yq e '.nodes = (.control_planes + .worker_nodes) | with_entries(select(.key == "nodes"))' "$nodes_file")

    hostname="$node"
    public_ip=$(echo "$all_nodes" | yq e '.nodes[] | select(.hostname == "'$node'") | .public_ip')
    private_ip=$(echo "$all_nodes" | yq e '.nodes[] | select(.hostname == "'$node'") | .private_ip')

    connection_address=$public_ip
    if [ "$ssh_connect_through" = "hostname" ]; then
        connection_address=$hostname
    elif [ "$ssh_connect_through" = "private_ip" ]; then
        connection_address=$private_ip
    fi

    local ssh_args="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o GlobalKnownHostsFile=/dev/null -o LogLevel=ERROR"

    if [ "$VERBOSE" = true ]; then
        print_status "info" "Running '$cmd' on node $hostname ($connection_address) $bastion_message..."
    fi

    local ssh_exit_code
    local output
    if [ "$bastion_enabled" = "true" ]; then
        output=$(ssh $ssh_args -o ProxyCommand="ssh -W %h:%p $bastion_private_key_arg $bastion_username_arg $bastion_port_arg $bastion_address" \
        $ssh_private_key_arg $ssh_username_arg $ssh_port_arg $connection_address "$cmd" 2>&1)
        ssh_exit_code=$?
    else
        output=$(ssh $ssh_args $ssh_private_key_arg $ssh_username_arg $ssh_port_arg $connection_address "$cmd" 2>&1)
        ssh_exit_code=$?
    fi

    if [ $ssh_exit_code -ne 0 ]; then
        print_status "error" "Failed to run '$cmd' on node $hostname ($connection_address) $bastion_message"
        print_status "error" "SSH output: $output"
        exit 1
    fi
    if [ "$VERBOSE" = true ]; then
        echo "-------------------- OUTPUT from $hostname ($connection_address) --------------------"
        echo "$output"
        echo "-------------------- END OUTPUT from $hostname ($connection_address) -------------------- "
    fi
    RETURN_OUTPUT="$output"
}


##########################################
# Interact with the nodes
##########################################
function manage_nodes() {
    if [ "$VERBOSE" = true ]; then
        print_status "info" "Managing all nodes"
    fi

    manage_control_plane_nodes
    manage_worker_nodes
}


##########################################
# Interact with the control plane nodes
##########################################
function manage_control_plane_nodes() {
    if [ "$VERBOSE" = true ]; then
        print_status "info" "Managing control plane nodes only"
    fi

    # Only use the first control plane node for the initialisation
    local control_plane_main_node="$(yq e ".control_planes[0].hostname" "$NODES_FILE")"

    local control_plane_count=$(yq e '.control_planes | length' "$NODES_FILE")
    for ((i=0; i<control_plane_count; i++)); do
        hostname=$(yq e ".control_planes[$i].hostname" "$NODES_FILE")

        sysctl_configuration $hostname
        load_modules $hostname
        install_runtime $hostname
        install_haproxy $hostname

        if [ "$hostname" = "$control_plane_main_node" ]; then
            kubeadm_control_plane_init $hostname
            install_helm $hostname

            local cni_calico=$(yq e '.cluster_network.cni.calico' "$NODES_FILE")
            if [ "$cni_calico" != "null" ] && [ -n "$cni_calico" ]; then
                install_calico $hostname
            fi

        else
            kubeadm_control_plane_join $hostname
        fi

    done
}


##########################################
# Interact with the worker nodes
##########################################
function manage_worker_nodes() {
    if [ "$VERBOSE" = true ]; then
        print_status "info" "Managing worker nodes only"
    fi

    local worker_nodes_count=$(yq e '.worker_nodes | length' "$NODES_FILE")
    for ((i=0; i<worker_nodes_count; i++)); do
        hostname=$(yq e ".worker_nodes[$i].hostname" "$NODES_FILE")
        print_status "info" "Managing worker node $hostname"
        sysctl_configuration $hostname
        load_modules $hostname
        install_runtime $hostname
        install_haproxy $hostname
        kubeadm_worker_node_join $hostname
    done
}


##########################################
# Configure sysctl
##########################################
function sysctl_configuration() {
    local node="$1"
    print_status "info" "Configuring sysctl on node $node"

    run_commands_on_node $node "sudo tee /etc/sysctl.d/kubernetes.conf > /dev/null <<EOF
net.ipv4.ip_forward = 1
EOF"

    run_commands_on_node $node "sudo sysctl -p /etc/sysctl.d/kubernetes.conf"
}

function load_modules() {
    local node="$1"
    print_status "info" "Loading modules on node $node"

    run_commands_on_node $node "sudo tee /etc/modules-load.d/k8s.conf > /dev/null <<EOF
overlay
br_netfilter
EOF"
    run_commands_on_node $node "sudo modprobe overlay br_netfilter"
}

##########################################
# Install runtime
##########################################
function install_runtime() {
    local node="$1"

    run_commands_on_node $node "sudo whereis containerd | sed 's/^.*://g'"
    if [ -z "$RETURN_OUTPUT" ]; then
        print_status "info" "Installing containerd on node $node"

        run_commands_on_node $node "sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates curl gpg containerd"
        run_commands_on_node $node "sudo mkdir -p /etc/containerd"
        run_commands_on_node $node "sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null"
        run_commands_on_node $node "sudo sed -ri 's/^(\s*)SystemdCgroup\s*=.*/\1SystemdCgroup = true/' /etc/containerd/config.toml"
        run_commands_on_node $node "sudo systemctl daemon-reload"
        run_commands_on_node $node "sudo systemctl enable --now containerd"
        run_commands_on_node $node "sudo systemctl restart containerd"
    else
        print_status "info" "containerd is already installed on node $node"
    fi

    run_commands_on_node $node "sudo test -f /etc/crictl.yaml && echo 'exists' || echo 'doesnotexist'"
    if [ "$RETURN_OUTPUT" = "doesnotexist" ]; then
        print_status "info" "Creating crictl configuration on node $node"

        run_commands_on_node $node "sudo tee /etc/crictl.yaml > /dev/null <<EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF"
    else
        print_status "info" "crictl configuration already exists on node $node"
    fi

    run_commands_on_node $node "sudo whereis kubelet | sed 's/^.*://g'"
    if [ -z "$RETURN_OUTPUT" ]; then
        print_status "info" "Installing kubelet kubeadm kubectl on node $node"

        run_commands_on_node $node "sudo mkdir -p -m 755 /etc/apt/keyrings"
        run_commands_on_node $node "curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg"
        run_commands_on_node $node "sudo chmod 0644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg"
        run_commands_on_node $node "echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list"
        run_commands_on_node $node "sudo apt-get update && \
            sudo apt-get install -y kubelet kubeadm kubectl && \
            sudo apt-mark hold kubelet kubeadm kubectl && \
            sudo systemctl enable --now kubelet"
    else
        print_status "info" "kubelet kubeadm kubectl are already installed on node $node"
    fi
}


##########################################
# Install haproxy
##########################################
function install_haproxy() {
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


##########################################
# Initialise control plane
##########################################
function kubeadm_control_plane_init() {
    local node="$1"

    local apiserver_cert_extra_sans=$(yq e '.cluster_network.apiserver_cert_extra_sans | join(",")' "$NODES_FILE")
    local control_plane_endpoint=$(yq e '.cluster_network.control_plane_endpoint' "$NODES_FILE")
    local pod_network_cidr=$(yq e '.cluster_network.pod_network_cidr' "$NODES_FILE")
    local service_dns_domain=$(yq e '.cluster_network.service_dns_domain' "$NODES_FILE")

    local kubeadm_init_command="sudo kubeadm init"

    if [ "$apiserver_cert_extra_sans" != "null" ] && [ -n "$apiserver_cert_extra_sans" ]; then
        kubeadm_init_command+=" --apiserver-cert-extra-sans=$apiserver_cert_extra_sans"
    fi

    if [ "$control_plane_endpoint" != "null" ] && [ -n "$control_plane_endpoint" ]; then
        kubeadm_init_command+=" --control-plane-endpoint=$control_plane_endpoint"
    fi

    if [ "$pod_network_cidr" != "null" ] && [ -n "$pod_network_cidr" ]; then
        kubeadm_init_command+=" --pod-network-cidr=$pod_network_cidr"
    fi

    if [ "$service_dns_domain" != "null" ] && [ -n "$service_dns_domain" ]; then
        kubeadm_init_command+=" --service-dns-domain=$service_dns_domain"
    fi

    run_commands_on_node $node "test -f /etc/kubernetes/manifests/kube-apiserver.yaml && echo 'exists' || echo 'doesnotexist'"
    if [ "$RETURN_OUTPUT" = "doesnotexist" ]; then
        print_status "info" "Initialising control plane on node $node with command: $kubeadm_init_command"
        run_commands_on_node $node "$kubeadm_init_command"

        print_status "info" "Copying kubeconfig to local directory"
        # run_commands_on_node $node "while sudo test ! -f /etc/kubernetes/admin.conf; do sleep 1; done"
        run_commands_on_node $node "sudo mkdir -p /root/.kube && sudo cp /etc/kubernetes/admin.conf /root/.kube/config && sudo chmod 600 /root/.kube/config"
        run_commands_on_node $node "sudo cat /etc/kubernetes/admin.conf"
        local kubeconfig_output=$RETURN_OUTPUT
        echo "$kubeconfig_output" > ./khandle.kubeconfig
    else
        print_status "info" "Control plane is already initialised on node $node"
    fi
}


##########################################
# Join node to the control plane
##########################################
function kubeadm_control_plane_join() {
    local node="$1"

    run_commands_on_node $node "test -f /etc/kubernetes/manifests/kube-apiserver.yaml && echo 'exists' || echo 'doesnotexist'"
    if [ "$RETURN_OUTPUT" = "doesnotexist" ]; then
        print_status "info" "Joining node $node to the control plane"

        # Get the token from the control plane main node
        local control_plane_main_node="$(yq e ".control_planes[0].hostname" "$NODES_FILE")"
        run_commands_on_node $control_plane_main_node "sudo kubeadm init phase upload-certs --upload-certs | grep -v 'upload-certs'"
        local certificate_key=$RETURN_OUTPUT
        run_commands_on_node $control_plane_main_node "sudo kubeadm token create --print-join-command"
        local join_command=$RETURN_OUTPUT
        join_command="$join_command --control-plane --certificate-key $certificate_key"

        run_commands_on_node $node "sudo $join_command"

    else
        print_status "info" "Node $node is already joined to the control plane"
    fi

}


##########################################
# Join node to the worker nodes
##########################################
function kubeadm_worker_node_join() {
    local node="$1"

    run_commands_on_node $node "test -f /etc/kubernetes/kubelet.conf && echo 'exists' || echo 'doesnotexist'"
    if [ "$RETURN_OUTPUT" = "doesnotexist" ]; then
        print_status "info" "Joining worker node $node to the cluster"

        # Get the token from the control plane main node
        local control_plane_main_node="$(yq e ".control_planes[0].hostname" "$NODES_FILE")"
        run_commands_on_node $control_plane_main_node "sudo kubeadm token create --print-join-command"
        local join_command=$RETURN_OUTPUT
        run_commands_on_node $node "sudo $join_command"
    else
        print_status "info" "Node $node is already joined to the cluster"
    fi
}


##########################################
# Install Helm
##########################################
function install_helm() {
    local node="$1"

    run_commands_on_node $node "sudo whereis helm | sed 's/^.*://g'"
    if [ -z "$RETURN_OUTPUT" ]; then
        print_status "info" "Installing helm on node $node"
        run_commands_on_node $node "curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
    else
        print_status "info" "helm is already installed on node $node"
    fi
}


##########################################
# Install Calico
##########################################
function install_calico() {
    local node="$1"

    local calico_values=$(yq e '.cluster_network.cni.calico.values' "$NODES_FILE")
    if [ "$calico_values" = "null" ] || [ -z "$calico_values" ]; then
        print_status "info" "Calico config is not set in the manifest"
        return
    fi

    local calico_version=$(yq e '.cluster_network.cni.calico.version' "$NODES_FILE")
    local calico_version_arg=""
    if [ "$calico_version" != "null" ] && [ -n "$calico_version" ]; then
        calico_version_arg="--version $calico_version"
    else
        print_status "warning" "Calico version is not set in the manifest. Using latest version"
        calico_version="latest"
    fi

    run_commands_on_node $node "sudo helm --kubeconfig /etc/kubernetes/admin.conf --namespace tigera-operator list --no-headers"
    if [ -z "$RETURN_OUTPUT" ]; then
        print_status "info" "Installing Calico $calico_version version on node $node"

        run_commands_on_node $node "sudo tee /tmp/calico-values.yaml > /dev/null <<EOF
---
$calico_values
EOF"

        run_commands_on_node $node "sudo helm repo add projectcalico https://docs.tigera.io/calico/charts && sudo helm repo update"
        run_commands_on_node $node "sudo helm install calico projectcalico/tigera-operator \
            --kubeconfig /etc/kubernetes/admin.conf \
            $calico_version_arg \
            --namespace tigera-operator \
            --create-namespace \
            --values /tmp/calico-values.yaml"
    else
        print_status "info" "Calico is already installed on node $node"
    fi
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
