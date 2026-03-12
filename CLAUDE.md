# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

khandle is a bash-based Kubernetes cluster installation and management tool that deploys self-managed Kubernetes clusters via kubeadm on bare metal or cloud infrastructure. It automates the entire cluster bootstrap process including system configuration, container runtime installation, control plane initialization, worker node joining, and CNI plugin deployment.

## Core Architecture

### Main Entry Point
- **khandle.sh**: Primary script with command-line interface
  - Commands: `apply` (install cluster), `update` (update cluster), `help`
  - Requires `-m/--manifest` flag pointing to a nodes YAML file
  - Sources all lib modules and orchestrates cluster operations

### Modular Library Structure (lib/)

Each library file is sourced by khandle.sh and provides focused functionality:

- **manifest.sh**: YAML file parsing and variable resolution
  - Loads manifest with `yq` and resolves `${...}` references within YAML
  - Global `MANIFEST_DATA` variable holds parsed manifest content
  - `manifest_read_yaml()` queries the parsed manifest using yq expressions

- **nodes.sh**: Cluster installation orchestration
  - `nodes_install_cluster()`: Main orchestrator, separates control plane from worker nodes
  - `nodes_install_control_plane()`: Installs control plane nodes sequentially (first node inits, others join)
  - `nodes_install_worker()`: Installs worker nodes in parallel
  - Each installation runs through: sysctl → modules → packages → runtime → haproxy → kubernetes

- **ssh.sh**: Remote command execution
  - `run_commands_on_node()`: Core function that SSH's into nodes and executes commands
  - Supports bastion/jump host configuration
  - Sets global `RETURN_OUTPUT` variable with command output
  - Connection target configurable via `connect_through`: hostname, public_ip, or private_ip

- **sysctl.sh**: System configuration
  - Configures kernel parameters (ip_forward)
  - Loads required kernel modules (overlay, br_netfilter)

- **packages.sh**: Package installation
  - `packages_system_install()`: Base system packages (apt-transport-https, curl, conntrack, yq)
  - `packages_runtime_install()`: Containerd container runtime with SystemdCgroup enabled
  - `packages_haproxy_install()`: HAProxy load balancer dynamically configured with all control plane nodes
  - `packages_helm_install()`: Helm package manager

- **kubernetes.sh**: Kubernetes cluster management
  - `kubernetes_install()`: Installs kubeadm, kubelet, kubectl from official k8s repos
  - `kubernetes_kubeadm_control_plane_init()`: Initializes first control plane node with kubeadm
  - `kubernetes_kubeadm_control_plane_join()`: Joins additional control plane nodes
  - `kubernetes_kubeadm_worker_join()`: Joins worker nodes to cluster
  - `kubernetes_kubelet_patch_config()`: Patches kubelet configuration and kubeadm flags
  - `kubernetes_kubectl_label_node()`: Applies custom labels to nodes
  - Downloads kubeconfig to `~/.kube/{cluster_name}.kubeconfig`

- **cni.sh**: CNI plugin management
  - `cni_calico_install()`: Installs Calico via Helm with custom values

### Configuration Model

Cluster configuration is defined in YAML manifest files (e.g., `nodes.hetzner.fsn1.yaml`, `nodes.aws.us-west-1.yaml`):

```yaml
global:
  cluster_name: "cluster-name"
  ssh_connection: {...}

cluster_network:
  control_plane_endpoint: "169.254.10.10:6444"  # HAProxy local endpoint
  pod_network_cidr: "172.16.0.0/18"
  kube_proxy:
    enabled: false

control_planes:
  - hostname: node1.example.com
    public_ip: x.x.x.x
    private_ip: 10.0.0.2
    kubernetes:
      version: 1.32.0
      labels: {...}
      kubelet:
        config: {...}
        kubelet_kubeadm_args: [...]

worker_nodes:
  - hostname: worker1.example.com
    ...
```

The manifest supports variable interpolation with `${...}` syntax (e.g., `${nodes[0].public_ip}`).

### HAProxy Local Load Balancer

Each node runs HAProxy listening on `169.254.10.10:6444`, load balancing to all control plane nodes on port 6443. This provides a stable control plane endpoint that works even if individual control plane nodes are unavailable.

### Infrastructure Provisioning (terraform/)

Optional Terraform configuration for AWS infrastructure:
- VPC, subnets, security groups, load balancers
- EC2 instances with cloud-init for initial setup
- Outputs instance IPs for use in nodes YAML manifests

## Common Commands

### Cluster Operations

```bash
# Install a new cluster
./khandle.sh apply -m nodes.hetzner.fsn1.yaml

# Update an existing cluster
./khandle.sh update -m nodes.hetzner.fsn1.yaml

# Show help
./khandle.sh help
```

### Required Tools

The script requires these tools installed locally:
- `yq` - YAML parsing
- `ssh` - Remote command execution

### Accessing Clusters

After installation, kubeconfig is downloaded to:
```bash
~/.kube/{cluster_name}.kubeconfig

# Use with kubectl
kubectl --kubeconfig ~/.kube/hetzner.fsn1.kubeconfig get nodes
```

### Terraform Infrastructure

```bash
cd terraform/

# Initialize Terraform
terraform init

# Plan infrastructure changes
terraform plan

# Apply infrastructure
terraform apply

# Destroy infrastructure
terraform destroy
```

## Development Guidelines

### Code Organization

- Keep SSH operations in `ssh.sh` and use `run_commands_on_node()` consistently
- All package installation logic belongs in `packages.sh`
- Kubernetes-specific operations go in `kubernetes.sh`
- Use `manifest_read_yaml()` to query manifest data, never parse YAML manually
- Set global `RETURN_OUTPUT` in `run_commands_on_node()` for function return values

### Testing Changes

- Always test with `-m` flag pointing to a test manifest
- Verify SSH connectivity before making changes
- Check idempotency: running `apply` twice should not break the cluster
- Test with both control plane and worker node configurations

### Node State Detection

Functions should detect existing state before making changes:
- Check if files exist before creating them
- Check if packages are installed before installing
- Check if nodes are joined before joining them
- Use `test -f`, `whereis`, `dpkg-query` to detect state

### Error Handling

- Use `print_status "error"` for errors and exit with non-zero code
- Validate SSH exit codes in `run_commands_on_node()`
- Check for null/empty values before using manifest data

### Bash style guide

Use this document to analyse bash scripts: https://google.github.io/styleguide/shellguide.html
