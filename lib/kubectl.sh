##########################################
# Label node
##########################################
function kubectl_label_node() {
    local node="$1"

    local node_labels=$(echo "$ALL_NODES" | yq e '.nodes[] | select(.hostname == "'$node'") | .kubernetes.labels')
    if [ "$node_labels" != "null" ] && [ -n "$node_labels" ]; then
        print_status "info" "Labeling node $node"
        # echo "$node_labels"


        local labels_string=$(echo "$node_labels" | tr -s ':' '=' | tr -d ' ' | tr -s '\n' ' ')
        # echo "$labels_string"

        run_commands_on_node $CONTROL_PLANE_MAIN_NODE "sudo kubectl --kubeconfig /etc/kubernetes/admin.conf label node $node $labels_string"
    fi
}
