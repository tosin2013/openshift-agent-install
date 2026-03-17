#!/bin/bash
# ./hack/destroy-on-kvm.sh examples/bond0-signal-vlan/nodes.yml
if [ $# -ne 1 ]; then
    echo "Usage: $0 <yaml_file>"
    exit 1
fi

yaml_file=$1

LIBVIRT_VM_PATH="/var/lib/libvirt/images"

# Function to remove DNS entries from libvirt network
remove_cluster_dns() {
    local cluster_config=$1

    echo "============================================================="
    echo "Removing DNS entries from libvirt network..."
    echo "============================================================="

    local cluster_name=$(yq eval '.cluster_name' "$cluster_config" 2>/dev/null)
    local base_domain=$(yq eval '.base_domain' "$cluster_config" 2>/dev/null)
    local api_vip=$(yq eval '.api_vips[0]' "$cluster_config" 2>/dev/null)
    local app_vip=$(yq eval '.app_vips[0]' "$cluster_config" 2>/dev/null)

    if [ -z "$cluster_name" ] || [ -z "$base_domain" ]; then
        echo "Warning: Could not parse cluster config for DNS cleanup"
        return 0
    fi

    echo "Cluster: ${cluster_name}.${base_domain}"

    # Remove API entries (need to specify IP for removal)
    echo "Removing API DNS entries..."
    if [ -n "$api_vip" ]; then
        sudo virsh net-update default delete dns-host \
          "<host ip='${api_vip}'><hostname>api.${cluster_name}.${base_domain}</hostname><hostname>api-int.${cluster_name}.${base_domain}</hostname></host>" \
          --live --config 2>/dev/null || true
    fi

    # Remove app entries
    echo "Removing application DNS entries..."
    if [ -n "$app_vip" ]; then
        local apps="console-openshift-console oauth-openshift grafana-openshift-monitoring prometheus-k8s-openshift-monitoring alertmanager-main-openshift-monitoring thanos-querier-openshift-monitoring downloads-openshift-console"
        for app in $apps; do
            sudo virsh net-update default delete dns-host \
              "<host ip='${app_vip}'><hostname>${app}.apps.${cluster_name}.${base_domain}</hostname></host>" \
              --live --config 2>/dev/null || true
        done
    fi

    echo "DNS entries removed successfully"
    echo ""
}

#########################################################
## Check to see if all the nodes have reported in

echo -e "===== Deleting OpenShift Libvirt Infrastructure..."

# Remove DNS entries first
CLUSTER_CONFIG_FILE="${yaml_file%/nodes.yml}/cluster.yml"
if [ ! -f "$CLUSTER_CONFIG_FILE" ]; then
    # Try alternate path format
    CLUSTER_CONFIG_FILE="examples/$(basename $(dirname ${yaml_file}))/cluster.yml"
fi

if [ -f "$CLUSTER_CONFIG_FILE" ]; then
    echo "Using cluster config: $CLUSTER_CONFIG_FILE"
    remove_cluster_dns "$CLUSTER_CONFIG_FILE"
else
    echo "Warning: cluster.yml not found, skipping DNS cleanup"
fi

# Parse cluster name for disk cleanup
if [ -f "$CLUSTER_CONFIG_FILE" ]; then
    CLUSTER_NAME=$(yq eval '.cluster_name' "$CLUSTER_CONFIG_FILE" 2>/dev/null)
fi

# Default to ocp4 if not found
if [ -z "$CLUSTER_NAME" ]; then
    CLUSTER_NAME="ocp4"
fi

echo "Using cluster name: $CLUSTER_NAME"

node_names=$(yq e '.nodes[].hostname' "$yaml_file")

num_nodes=$(echo "$node_names" | wc -l)

## Loop through defined nodes, match to this node if applicable
for node_name in $node_names; do
echo "Node Name: $node_name"
  ## Check to see if the VM exists
  VIRSH_VM=$(sudo virsh list --all | grep ${node_name} || true);
  if [[ ! -z "${VIRSH_VM}" ]]; then
    echo "  Deleting VM ${node_name} ..."
    sudo virsh destroy ${node_name} 2>/dev/null || true
    sudo virsh undefine ${node_name} || true
  fi

  ## See if the disk image exists (with cluster name prefix)
  if [[ -f "${LIBVIRT_VM_PATH}/${CLUSTER_NAME}-${node_name}.qcow2" ]]; then
    echo "  Deleting disk for VM ${node_name} at ${LIBVIRT_VM_PATH}/${CLUSTER_NAME}-${node_name}.qcow2 ..."
    sudo rm ${LIBVIRT_VM_PATH}/${CLUSTER_NAME}-${node_name}.qcow2 || true
  fi

  ## Remove ODF disk if it exists
  if [[ -f "${LIBVIRT_VM_PATH}/${CLUSTER_NAME}-${node_name}-odf.qcow2" ]]; then
    echo "  Deleting ODF disk for VM ${node_name} ..."
    sudo rm ${LIBVIRT_VM_PATH}/${CLUSTER_NAME}-${node_name}-odf.qcow2 || true
  fi

done

# Remove agent ISO
if [[ -f "${LIBVIRT_VM_PATH}/agent.x86_64.iso" ]]; then
    echo "Removing agent ISO..."
    sudo rm ${LIBVIRT_VM_PATH}/agent.x86_64.iso || true
fi