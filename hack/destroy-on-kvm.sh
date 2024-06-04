#!/bin/bash
# ./hack/destroy-on-kvm.sh examples/bond0-signal-vlan/nodes.yml
if [ $# -ne 1 ]; then
    echo "Usage: $0 <yaml_file>"
    exit 1
fi

yaml_file=$1

LIBVIRT_VM_PATH="/var/lib/libvirt/images"

#########################################################
## Check to see if all the nodes have reported in

echo -e "===== Deleting OpenShift Libvirt Infrastructure..."

node_names=$(yq e '.nodes[].hostname' "$yaml_file")

num_nodes=$(echo "$node_names" | wc -l)

## Loop through defined nodes, match to this node if applicable
for node_name in $node_names; do
echo "Node Name: $node_name"
  ## Check to see if the VM exists
  VIRSH_VM=$(sudo virsh list --all | grep ${node_name} || true);
  if [[ ! -z "${VIRSH_VM}" ]]; then
    echo "  Deleting VM ${node_name} ..."
    sudo virsh shutdown ${node_name} || true
    sudo virsh undefine ${node_name} || true
  fi

  ## See if the disk image exists
  if [[ -f "${LIBVIRT_VM_PATH}/${node_name}.qcow2" ]]; then
    echo "  Deleting disk for VM $(_jq '.name') at ${LIBVIRT_VM_PATH}/${node_name}.qcow2 ..."
    sudo rm ${LIBVIRT_VM_PATH}/${node_name}.qcow2 || true
  fi

done