##########################################
# Global variables
##########################################
MANIFEST_DATA=""


##########################################
# Read YAML file
##########################################
function manifest_read_yaml_file() {
    local yaml_file="$1"

    ###
    # Todo: Validate YAML file
    ###
    MANIFEST_DATA=$(yq '. | (... comments="")' "$yaml_file")

    MANIFEST_DATA=$(manifest_resolve_this_node_references "$MANIFEST_DATA")
    if [ $? -ne 0 ]; then
        print_status "error" "Failed to resolve this_node references"
        exit 1
    fi

    MANIFEST_DATA=$(manifest_resolve_yaml_references "$MANIFEST_DATA")
    if [ $? -ne 0 ]; then
        print_status "error" "Failed to marshal YAML file"
        exit 1
    fi
    # echo "$MANIFEST_DATA"
    # exit 0
}


##########################################
# Resolve YAML references
##########################################
function manifest_resolve_yaml_references() {
    local content="$1"

    # Continue as long as the content contains the pattern ${...}
    while [[ "$content" =~ \$\{([^}]+)\} ]]; do
        # 1. Extract the full match (e.g., ${nodes[0].public_ip})
        # 2. Extract the raw path inside (e.g., nodes[0].public_ip)
        local full_match="${BASH_REMATCH[0]}"
        local yaml_path="${BASH_REMATCH[1]}"

        # 3. Use yq to find the value for this path from the current content
        local value=$(yq ".$yaml_path" <<< "$content")

        # Handle null values to avoid infinite loops or broken yaml
        if [ "$value" = "null" ]; then
            print_status "error" "Cannot resolve YAML reference: value is null for path $yaml_path"
            exit 1
        fi
        if [ -z "$value" ]; then
            print_status "error" "Cannot resolve YAML reference: value is empty for path $yaml_path"
            exit 1
        fi

        # 4. Use sed to replace ONLY the first occurrence of this specific full_match
        local escaped_match=$(echo "$full_match" | sed 's/[][\.^$*]/\\&/g')
        content=$(echo "$content" | sed "s/$escaped_match/$value/")
    done

    echo "$content"
}


##########################################
# Resolve ${this_node.<path>} references inside each node of .nodes
#
# For each element of the .nodes list, replace every occurrence of
# ${this_node.<yaml_path>} with the value at <yaml_path> taken from
# that same node. This avoids hard-coded indices like ${nodes[0].public_ip}
# that break when nodes are added/removed/commented out.
##########################################
function manifest_resolve_this_node_references() {
    local content="$1"

    local nodes_count
    nodes_count=$(yq '.nodes | length' <<< "$content")

    if [ -z "$nodes_count" ] || [ "$nodes_count" = "null" ] || [ "$nodes_count" -eq 0 ]; then
        echo "$content"
        return 0
    fi

    local i
    for ((i = 0; i < nodes_count; i++)); do
        local node_yaml
        node_yaml=$(yq ".nodes[$i]" <<< "$content")

        while [[ "$node_yaml" =~ \$\{this_node\.([^}]+)\} ]]; do
            local full_match="${BASH_REMATCH[0]}"
            local yaml_path="${BASH_REMATCH[1]}"

            local value
            value=$(yq ".$yaml_path" <<< "$node_yaml")

            if [ "$value" = "null" ]; then
                print_status "error" "Cannot resolve this_node reference: value is null for path $yaml_path in nodes[$i]"
                exit 1
            fi
            if [ -z "$value" ]; then
                print_status "error" "Cannot resolve this_node reference: value is empty for path $yaml_path in nodes[$i]"
                exit 1
            fi

            local escaped_match
            escaped_match=$(echo "$full_match" | sed 's/[][\.^$*]/\\&/g')
            node_yaml=$(echo "$node_yaml" | sed "s/$escaped_match/$value/")
        done

        content=$(NODE_YAML="$node_yaml" yq ".nodes[$i] = (env(NODE_YAML))" <<< "$content")
    done

    echo "$content"
}


##########################################
# Get value from YAML file
##########################################
function manifest_read_yaml() {
    local yaml_expression="$1"

    local data=$(yq "$yaml_expression" <<< "$MANIFEST_DATA")

    echo "$data"
}
