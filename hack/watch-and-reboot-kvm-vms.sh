#!/bin/bash
# ./hack/watch-and-reboot-kvm-vms.sh examples/bond0-signal-vlan/nodes.yml
if [ $# -ne 1 ]; then
    echo "Usage: $0 <yaml_file>"
    exit 1
fi

yaml_file=$1
node_names=$(yq e '.nodes[].hostname' "$yaml_file")

num_nodes=$(echo "$node_names" | wc -l)

# Make an array
VM_ARR=()

VM_ARR=($node_names)

LOOP_ON="true"
VIRSH_WATCH_CMD="sudo virsh list --state-shutoff --name"

echo "===== Watching virsh to reboot Cluster VMs: ${VM_ARR[@]}"

while [ $LOOP_ON = "true" ]; do
  currentPoweredOffVMs=$($VIRSH_WATCH_CMD)

  # loop through VMs that are powered off
  while IFS="" read -r p || [ -n "$p" ]
  do
    if [[ " ${VM_ARR[@]} " =~ " ${p} " ]]; then
      # Powered off VM matches the original list of VMs, turn it on and remove from array
      echo "  Starting VM: ${p} ..."
      sudo virsh start $p
      # Remove from original array
      TMP_ARR=()
      for val in "${VM_ARR[@]}"; do
        [[ $val != $p ]] && TMP_ARR+=($val)
      done
      VM_ARR=("${TMP_ARR[@]}")
      unset TMP_ARR
    fi
  done < <(printf '%s' "${currentPoweredOffVMs}")

  if [ '0' -eq "${#VM_ARR[@]}" ]; then
    LOOP_ON="false"
    echo "  All Cluster VMs have been restarted!"
  else
    echo "  Still waiting on ${#VM_ARR[@]} VMs: ${VM_ARR[@]}"
    sleep 30
  fi
done