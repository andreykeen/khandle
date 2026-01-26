##########################################
# Configure kubelet
##########################################
function kubelet_patch_config() {
    local node="$1"

    local kubelet_config=$(echo "$ALL_NODES" | yq e '.nodes[] | select(.hostname == "'$node'") | .kubernetes.kubelet.config')
    local private_ip=$(echo "$ALL_NODES" | yq e '.nodes[] | select(.hostname == "'$node'") | .private_ip')


    if [ "$kubelet_config" != "null" ] && [ -n "$kubelet_config" ]; then
        print_status "info" "Specifying Kubelet config on node $node"

        # Create the patch file
        run_commands_on_node $node "sudo tee /var/lib/kubelet/config-patch.yaml > /dev/null <<EOF
$kubelet_config
EOF"

        # Backup the original config
        run_commands_on_node $node "sudo cp /var/lib/kubelet/config.yaml /var/lib/kubelet/config-original.yaml"

        # Delete fields that exist in the patch file
        run_commands_on_node $node "sudo yq eval-all 'select(fileIndex == 0) as \$orig | select(fileIndex == 1) as \$patch | (\$orig | delpaths([[\$patch | keys[]]])) * \$patch' /var/lib/kubelet/config-original.yaml /var/lib/kubelet/config-patch.yaml | sudo tee /var/lib/kubelet/config.yaml > /dev/null"
    fi


    # Create the kubeadm-flags.env file
    run_commands_on_node $node "sudo tee /var/lib/kubelet/kubeadm-flags.env > /dev/null <<EOF
KUBELET_KUBEADM_ARGS=\"--node-ip=$private_ip\"
EOF"

    # Restart kubelet to apply the new configuration
    run_commands_on_node $node "sudo systemctl restart kubelet"
}
