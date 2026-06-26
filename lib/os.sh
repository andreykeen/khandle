##########################################
# Check SSH connection
##########################################
function os_check_ssh_connections() {

    local all_nodes=$(manifest_read_yaml "[.nodes[]]")
    local nodes_count=$(echo "${all_nodes}" | yq length)
    local i
    for ((i=0; i<nodes_count; i++)); do
        local node=$(yq ".[$i]" <<< "${all_nodes}")
        local hostname=$(yq ".hostname" <<< "${node}")

        print_status "verbose" "${hostname}: Checking SSH connection"
        run_commands_on_node "$node" "sudo whoami"
        if [[ "$RETURN_OUTPUT" != "root" ]]; then
            print_status "error" "${hostname}: SSH connection failed"
            exit 1
        fi
        print_status "verbose" "${hostname}: SSH connection established"
    done
    print_status "info" "All SSH connections established"
}


##########################################
# Configure kubeapiserver interface
##########################################
function os_kubeapiserver_interface() {
    local node="$1"
    local hostname=$(yq ".hostname" <<< "${node}")
    local control_plane_endpoint=$(manifest_read_yaml ".cluster_network.control_plane_endpoint")
    local control_plane_endpoint_ip=$(echo "${control_plane_endpoint}" | awk -F':' '{print $1}')

    # Check if the control plane interface is enabled in the manifest
    local control_plane_interface=$(manifest_read_yaml ".cluster_network.control_plane_interface")
    if [[ "${control_plane_interface}" == "null" ]] || [[ -z "${control_plane_interface}" ]] || [[ "${control_plane_interface}" == "false" ]]; then
        print_status "verbose" "${hostname}: Control plane interface is not enabled"
        return
    fi

    # Create the kubeapiserver interface service file
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
    run_commands_on_node "${node}" "[[ ! -f /etc/systemd/system/kubeapiserver.service ]] && echo 'doesnotexist' || echo 'exists'"
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
            print_status "verbose" "${hostname}: Kubeapiserver interface is already up to date"
        fi
    fi
}


##########################################
# Configure sysctl
##########################################
function os_sysctl() {
    local node="$1"
    local hostname=$(yq ".hostname" <<< "${node}")

    # Check if the sysctl parameters are listed in the manifest
    local sysctl_parameters=$(manifest_read_yaml ".global.os.sysctl[]")
    local skip_os_configuration=$(manifest_read_yaml ".global.os.skip_os_configuration")

    if [[ "${sysctl_parameters}" == "null" ]] || [[ -z "${sysctl_parameters}" ]] || [[ "${skip_os_configuration}" == "true" ]]; then
        print_status "verbose" "${hostname}: Sysctl parameters are not listed in the manifest or skip_os_configuration is enabled"
        return
    fi

    print_status "info" "${hostname}: Configuring sysctl"
    run_commands_on_node "${node}" "sudo tee /etc/sysctl.d/khandle.conf > /dev/null <<EOF
${sysctl_parameters}
EOF
sudo sysctl -p /etc/sysctl.d/khandle.conf"
}


##########################################
# Load modules
##########################################
function os_kernel_modules() {
    local node="$1"
    local hostname=$(yq ".hostname" <<< "${node}")

    # Check if the kernel modules are listed in the manifest
    local kernel_modules=$(manifest_read_yaml ".global.os.kernel_modules[]")
    local skip_os_configuration=$(manifest_read_yaml ".global.os.skip_os_configuration")

    if [[ "${kernel_modules}" == "null" ]] || [[ -z "${kernel_modules}" ]] || [[ "${skip_os_configuration}" == "true" ]]; then
        print_status "verbose" "${hostname}: Kernel modules are not listed in the manifest or skip_os_configuration is enabled"
        return
    fi

    print_status "info" "${hostname}: Loading modules"
    run_commands_on_node "${node}" "sudo tee /etc/modules-load.d/khandle.conf > /dev/null <<EOF
${kernel_modules}
EOF
sudo modprobe $(echo "${kernel_modules[@]}" | tr '\n' ' ')"
}
