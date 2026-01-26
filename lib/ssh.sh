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

    local hostname="$node"
    local public_ip=$(echo "$ALL_NODES" | yq e '.nodes[] | select(.hostname == "'$node'") | .public_ip')
    local private_ip=$(echo "$ALL_NODES" | yq e '.nodes[] | select(.hostname == "'$node'") | .private_ip')

    local connection_address=$public_ip
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
