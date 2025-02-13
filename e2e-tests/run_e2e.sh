#!/bin/bash

# This script runs end-to-end tests targeting OpenShift 4.17

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print with color
print_status() {
    if [ $2 -eq 0 ]; then
        echo -e "${GREEN}✓ $1${NC}"
    else
        echo -e "${RED}✗ $1${NC}"
        exit 1
    fi
}

print_section() {
    echo -e "\n${YELLOW}$1${NC}"
    echo "================================"
}

print_info() {
    echo -e "${BLUE}$1${NC}"
}

print_section "Running End-to-End Tests"

# --- Core Test Functions ---

create_test_iso() {
    print_section "Creating Test ISO"

    # Where are we pulling cluster configuration from
    SITE_CONFIG_DIR="${SITE_CONFIG_DIR:-examples}"
    # Check if GENERATED_ASSET_PATH is set, if not, use the home directory
    if [ -z "${GENERATED_ASSET_PATH}" ]; then
        GENERATED_ASSET_PATH="${HOME}/generated_assets"
    fi

    # Check to see if the generated asset path exists
    if [ ! -d "${GENERATED_ASSET_PATH}" ]; then
        mkdir -p "${GENERATED_ASSET_PATH}"
    fi

    echo "Generated asset path is: ${GENERATED_ASSET_PATH}"

    # Check if a site config folder was specified
    if [ -z "$1" ]; then
        echo "No site config folder specified"
        exit 1
    fi

    # Check that the cluster name exists
    if [ ! -d "${SITE_CONFIG_DIR}/$1" ]; then
        echo "No site config folder found for $1"
        echo "Found these site config folders:"
        ls -1 "${SITE_CONFIG_DIR}"
        exit 1
    fi

    # Get the cluster_name
    CLUSTER_NAME=$(grep "cluster_name" "${SITE_CONFIG_DIR}/${1}/cluster.yml" | awk '{print $2}' | tr -d '"')
    # Get the base_domain
    BASE_DOMAIN=$(grep "base_domain" "${SITE_CONFIG_DIR}/${1}/cluster.yml" | awk '{print $2}' | tr -d '"')

    # Run the templating playbook
    ansible-playbook -e "@${SITE_CONFIG_DIR}/${1}/cluster.yml" -e "@${SITE_CONFIG_DIR}/${1}/nodes.yml" -e "generated_asset_path=${GENERATED_ASSET_PATH}" playbooks/create-manifests.yml || { echo "Failed to template manifests"; exit 1; }

    # Generate the ABI ISO
    openshift-install agent create image --dir "${GENERATED_ASSET_PATH}/${CLUSTER_NAME}/" || { echo "Failed to generate ISO"; exit 1; }

    print_status "Test ISO created successfully" 0
}

deploy_test_vms() {
    print_section "Deploying Test VMs"

    # Check for required variables (replace with actual checks/defaults)
    : ${CLUSTER_NAME:?"CLUSTER_NAME is not set"}
    yaml_file="$1" # Assuming the first argument is the nodes.yml file
    : ${yaml_file:?"yaml_file is not set"}

    # Use GENERATED_ASSET_PATH as an environment variable, default to "playbooks/generated_manifests" if not set
    GENERATED_ASSET_PATH="${GENERATED_ASSET_PATH:-"${HOME}"}"

    if [ ! -f "${GENERATED_ASSET_PATH}/${CLUSTER_NAME}/agent.x86_64.iso" ]; then
        echo "Please generate the agent.iso first"
        exit 1
    else
        echo "Agent ISO exists"
        if [ ! -f /var/lib/libvirt/images/agent.x86_64.iso ]; then
            sudo cp "${GENERATED_ASSET_PATH}/${CLUSTER_NAME}/agent.x86_64.iso" /var/lib/libvirt/images/agent.x86_64.iso || print_status "Failed to copy agent ISO" 1
        elif [ -f /var/lib/libvirt/images/agent.x86_64.iso ]; then
            sudo rm /var/lib/libvirt/images/agent.x86_64.iso
            sudo cp "${GENERATED_ASSET_PATH}/${CLUSTER_NAME}/agent.x86_64.iso" /var/lib/libvirt/images/agent.x86_64.iso || print_status "Failed to copy agent ISO" 1
        fi
    fi

    LIBVIRT_LIKE_OPTIONS="--connect=qemu:///system -v --memballoon none --cpu host-passthrough --autostart --noautoconsole --virt-type kvm --features kvm_hidden=on --controller type=scsi,model=virtio-scsi --cdrom=/var/lib/libvirt/images/agent.x86_64.iso --os-variant=fedora-coreos-stable --events on_reboot=restart --graphics vnc,listen=0.0.0.0,tlsport=,defaultMode='insecure' --console pty,target_type=serial"

    # Extract node names using yq
    node_names=$(yq e '.nodes[].hostname' "$yaml_file")

    num_nodes=$(echo "$node_names" | wc -l)

    # Function to calculate vCPU, memory, and storage based on node count
    calculate_resources() {
        local num=$1
        # Allow overriding resource values via environment variables
        : ${CP_CPU_CORES:=$(echo "$num" | awk '{if ($1 == 1) print 8; else if ($1 == 3) print 6; else print 4}')}
        : ${CP_RAM_GB:=$(echo "$num" | awk '{if ($1 == 1) print 32; else if ($1 == 3) print 16; else print 8}')}
        : ${DISK_SIZE:=120} # Default disk size in GB
        extra_storage="false" # Default to no extra storage
        if [ "$num" -le 3 ]; then
            extra_storage="true"
        fi
    }

    # Initialize counter for differentiating resources for first 3 nodes
    counter=0

    # Loop through each node name
    for node_name in $node_names; do
        echo "Node Name: $node_name"
        echo "counter: $counter"

        # Calculate resources for each node
        calculate_resources "$num_nodes"

        echo "CP_CPU_CORES: $CP_CPU_CORES"
        echo "Memory: $CP_RAM_GB GB"
        echo "Extra Storage: $extra_storage"
        echo "Disk Size: $DISK_SIZE GB"
        echo "---------------------"

        if [ "$extra_storage" == "true" ]; then
            if [ -f /var/lib/libvirt/images/"${CLUSTER_NAME}-${node_name}-odf.qcow2" ]; then
                sudo rm /var/lib/libvirt/images/"${CLUSTER_NAME}-${node_name}-odf.qcow2"
            fi
            sudo qemu-img create -f qcow2 /var/lib/libvirt/images/"${CLUSTER_NAME}-${node_name}-odf.qcow2" 400G || print_status "Failed to create extra storage" 1
            EXTRA_STORAGE_VAL="--disk size=400,path=/var/lib/libvirt/images/${CLUSTER_NAME}-${node_name}-odf.qcow2,cache=none,format=qcow2"
        else
            EXTRA_STORAGE_VAL=""
        fi

        export node="$node_name"
        mac_address1=$(yq -r '.nodes[] | select(.hostname == env(node)) | .interfaces[] | select(.name == "enp1s0") | .mac_address' "$yaml_file")
        # Assuming single network interface for now
        sudo virt-install -n "$node_name" --memory="$(expr "$CP_RAM_GB" \* 1024)" \
            --disk "size=${DISK_SIZE},path=/var/lib/libvirt/images/${CLUSTER_NAME}-${node_name}.qcow2,cache=none,format=qcow2" \
            "$EXTRA_STORAGE_VAL" \
            --cdrom=/var/lib/libvirt/images/agent.x86_64.iso \
            --network network=default,model=e1000e,mac="$mac_address1" \
            "${LIBVIRT_LIKE_OPTIONS}" --vcpus "sockets=1,cores=${CP_CPU_CORES},threads=1" --os-variant=rhel8.6 || print_status "Failed to create VM $node_name" 1

        ((counter++))
    done

    print_status "Test VMs deployed successfully" 0
}

monitor_test_vms() {
    print_section "Monitoring Test VMs"

    yaml_file="$1" # Assuming the first argument is the nodes.yml file
    : ${yaml_file:?"yaml_file is not set"}
    node_names=$(yq e '.nodes[].hostname' "$yaml_file")
    num_nodes=$(echo "$node_names" | wc -l)

    VM_ARR=($node_names)

    LOOP_ON="true"
    VIRSH_WATCH_CMD="sudo virsh list --state-shutoff --name"

    echo "===== Watching virsh to reboot Cluster VMs: ${VM_ARR[@]}"

    while [ "$LOOP_ON" = "true" ]; do
        currentPoweredOffVMs=$($VIRSH_WATCH_CMD)

        # loop through VMs that are powered off
        while IFS= read -r p || [ -n "$p" ]; do
            if [[ " ${VM_ARR[@]} " =~ " ${p} " ]]; then
                # Powered off VM matches the original list of VMs, turn it on and remove from array
                echo "  Starting VM: ${p} ..."
                sudo virsh start "$p" || print_status "Failed to start VM $p" 1
                # Remove from original array
                TMP_ARR=()
                for val in "${VM_ARR[@]}"; do
                    [[ "$val" != "$p" ]] && TMP_ARR+=("$val")
                done
                VM_ARR=("${TMP_ARR[@]}")
                unset TMP_ARR
            fi
        done < <(printf '%s\n' "${currentPoweredOffVMs}")

        if [ 0 -eq "${#VM_ARR[@]}" ]; then
            LOOP_ON="false"
            echo "  All Cluster VMs have been restarted!"
        else
            echo "  Still waiting on ${#VM_ARR[@]} VMs: ${VM_ARR[@]}"
            sleep 30
        fi
    done

    print_status "Test VMs monitored successfully" 0
}

cleanup_test_env() {
    print_section "Cleaning up Test Environment"

    yaml_file="$1" # Assuming the first argument is the nodes.yml file
    : ${yaml_file:?"yaml_file is not set"}
    : ${CLUSTER_NAME:?"CLUSTER_NAME is not set"}

    node_names=$(yq e '.nodes[].hostname' "$yaml_file")

    echo "===== Deleting OpenShift Libvirt Infrastructure..."

    for node_name in $node_names; do
        echo "Node Name: $node_name"
        # Check if the VM exists
        if sudo virsh domstate "$node_name" | grep -q running; then
            echo "  Deleting VM ${node_name} ..."
            sudo virsh shutdown "$node_name" || true # Allow shutdown to fail if VM is already stopped
            sudo virsh undefine "$node_name" || print_status "Failed to undefine VM $node_name" 1
        fi

        # See if the disk image exists
        if [ -f "/var/lib/libvirt/images/${CLUSTER_NAME}-${node_name}.qcow2" ]; then
            echo "  Deleting disk for VM ${node_name} at /var/lib/libvirt/images/${CLUSTER_NAME}-${node_name}.qcow2 ..."
            sudo rm "/var/lib/libvirt/images/${CLUSTER_NAME}-${node_name}.qcow2" || print_status "Failed to delete disk for VM $node_name" 1
        fi

        # Delete extra storage if it exists
        if [ -f "/var/lib/libvirt/images/${CLUSTER_NAME}-${node_name}-odf.qcow2" ]; then
            echo "  Deleting extra storage for VM ${node_name} at /var/lib/libvirt/images/${CLUSTER_NAME}-${node_name}-odf.qcow2 ..."
            sudo rm "/var/lib/libvirt/images/${CLUSTER_NAME}-${node_name}-odf.qcow2" || print_status "Failed to delete extra storage for VM $node_name" 1
        fi
    done

    # Remove ISO image
    if [ -f "/var/lib/libvirt/images/agent.x86_64.iso" ]; then
        echo "  Deleting agent ISO at /var/lib/libvirt/images/agent.x86_64.iso ..."
        sudo rm "/var/lib/libvirt/images/agent.x86_64.iso" || print_status "Failed to delete agent ISO" 1
    fi

    print_status "Test environment cleaned up successfully" 0
}

# --- Main Test Flow ---

print_section "Running End-to-End Tests"

# 1. Environment Validation (using e2e-tests/validate_env.sh)
source e2e-tests/validate_env.sh
validate_environment # Assuming validate_env.sh defines this function

# 2. ISO Creation
create_test_iso

# 3. VM Deployment
deploy_test_vms

# 4. Installation Monitoring
monitor_test_vms

# 5. Test Execution (add actual test commands here)
print_section "Executing Tests"
# Placeholder for test commands
echo "Implement actual test commands here"
print_status "Tests executed successfully (placeholder)" 0


# 6. Environment Cleanup
cleanup_test_env

print_section "End-to-End Tests Complete"
