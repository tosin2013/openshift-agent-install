#!/bin/bash
# ./hack/deploy-on-kvm.sh examples/bond0-signal-vlan/nodes.yml
#set -xe

# Check if the argument is provided
if [ $# -lt 1 ]; then
    echo "Usage: $0 <yaml_file> [--redfish]"
    exit 1
fi

yaml_file=$1
# Use GENERATED_ASSET_PATH as an environment variable, default to "${GENERATED_ASSET_PATH}" if not set
GENERATED_ASSET_PATH="${GENERATED_ASSET_PATH:-"${HOME}"}"
LIBVIRT_NETWORK="network=1924,model=virtio"
LIBVIRT_NETWORK_TWO="network=1924,model=virtio"
LIBVIRT_VM_PATH="/var/lib/libvirt/images"
MULTI_NETWORK=true
CLUSTER_NAME="ocp4"
USE_REDFISH=${USE_REDFISH:-true}

# Check if Redfish option is enabled
if [ "$2" == "--redfish" ]; then
    USE_REDFISH=true
fi

if [ ! -f ${GENERATED_ASSET_PATH}/${CLUSTER_NAME}/agent.x86_64.iso ]; then
    echo "Please generate the agent.iso first"
    exit 1
else 
    echo "Agent ISO exists"
    if [ ! -f /var/lib/libvirt/images/agent.x86_64.iso ]; then
        sudo cp ${GENERATED_ASSET_PATH}/${CLUSTER_NAME}/agent.x86_64.iso /var/lib/libvirt/images/agent.x86_64.iso
    elif [ -f /var/lib/libvirt/images/agent.x86_64.iso ]; then
        sudo rm /var/lib/libvirt/images/agent.x86_64.iso
        sudo cp ${GENERATED_ASSET_PATH}/${CLUSTER_NAME}/agent.x86_64.iso /var/lib/libvirt/images/agent.x86_64.iso
    fi
fi

LIBVIRT_LIKE_OPTIONS="--connect=qemu:///system -v --memballoon none --cpu host-passthrough --autostart --noautoconsole --virt-type kvm --features kvm_hidden=on --controller type=scsi,model=virtio-scsi --cdrom=/var/lib/libvirt/images/agent.x86_64.iso --os-variant=fedora-coreos-stable --events on_reboot=restart --graphics vnc,listen=0.0.0.0,tlsport=,defaultMode='insecure' --console pty,target_type=serial"

# Extract node names using yq
node_names=$(yq e '.nodes[].hostname' "$yaml_file")

num_nodes=$(echo "$node_names" | wc -l)

# Function to calculate vCPU, memory, and storage based on node count
calculate_resources() {
    local num=$1
    echo "$counter and $num line 36"
    if [ "$num" -eq 1 ]; then
        CP_CPU_CORES=8
        CP_RAM_GB=32
        extra_storage="true"
        DISK_SIZE=130
        break
    elif [ "$num" -eq 3 ]; then
        CP_CPU_CORES=6
        CP_RAM_GB=32
        extra_storage="true"
        DISK_SIZE=130
    elif [ "$num" -eq 6 ]; then
        if [ "$counter" -lt 3 ] && [ "$num" -gt 3 ]; then
            CP_CPU_CORES=6
            CP_RAM_GB=24
            DISK_SIZE=130
        else
            CP_CPU_CORES=12
            CP_RAM_GB=32
            extra_storage="true"
            DISK_SIZE=130
        fi
    elif [ "$num" -gt 6 ]; then
         if [ "$counter" -lt 3 ] && [ "$num" -gt 3 ]; then
            CP_CPU_CORES=6
            CP_RAM_GB=24
            DISK_SIZE=130
        elif [ "$counter" -ge 3 ] && [ "$counter" -lt 6 ]; then
            CP_CPU_CORES=12
            CP_RAM_GB=48
            extra_storage="true"
            DISK_SIZE=130
        else
            CP_CPU_CORES=12
            CP_RAM_GB=48
            extra_storage=""
            DISK_SIZE=130
        fi
    fi
}

# Initialize counter for differentiating resources for first 3 nodes
counter=0

# Install and configure sushy-tools if Redfish is enabled
if [ "$USE_REDFISH" == true ]; then
    echo "Installing sushy-tools..."
    sudo pip install sushy-tools
    
    echo "Configuring sushy-tools..."
    sudo tee /etc/sushy-tools.conf <<EOF
[sushy]
# Bind IP address, 0.0.0.0 for all available interfaces
SUSHY_EMULATOR_LISTEN_IP = 0.0.0.0
# Bind port
SUSHY_EMULATOR_LISTEN_PORT = 8000

[default]
# Map libvirt domains to BMCs
SUSHY_EMULATOR_LIBVIRT_URI = qemu:///system
EOF
    
    echo "Starting sushy-tools..."
    sudo systemctl enable sushy-tools
    sudo systemctl start sushy-tools
fi

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
        if [ -f /var/lib/libvirt/images/${CLUSTER_NAME}-${node_name}-odf.qcow2]; then
            sudo rm /var/lib/libvirt/images/${CLUSTER_NAME}-${node_name}-odf.qcow2
        fi
        sudo qemu-img create -f qcow2 /var/lib/libvirt/images/${CLUSTER_NAME}-${node_name}-odf.qcow2 400G
        EXTRA_STORAGE_VAL="--disk size=400,path=/var/lib/libvirt/images/${CLUSTER_NAME}-${node_name}-odf.qcow2,cache=none,format=qcow2"
    else
        EXTRA_STORAGE_VAL=""
    fi

    # Check the value of MULTI_NETWORK and execute commands accordingly
    if [ "$MULTI_NETWORK" == false ]; then
        export node=$node_name
        mac_address1=$(yq -r '.nodes[] | select(.hostname == env(node)) | .interfaces[] | select(.name == "enp1s0") | .mac_address' $yaml_file)
        nohup sudo virt-install ${LIBVIRT_LIKE_OPTIONS} --mac="$mac_address1" --name=$node_name --vcpus "sockets=1,cores=${CP_CPU_CORES},threads=1" --memory="$(expr ${CP_RAM_GB} \* 1024)" --disk "size=${DISK_SIZE},path=${LIBVIRT_VM_PATH}/${CLUSTER_NAME}-${node_name}.qcow2,cache=none,format=qcow2" --os-variant=rhel8.6 &
    elif [ "$MULTI_NETWORK" == true ]; then
        export node=$node_name
        mac_address1=$(yq -r '.nodes[] | select(.hostname == env(node)) | .interfaces[] | select(.name == "enp1s0") | .mac_address' $yaml_file)
        mac_address2=$(yq -r '.nodes[] | select(.hostname ==  env(node)) | .interfaces[] | select(.name == "enp2s0") | .mac_address' $yaml_file)
        echo "MAC Address 1: $mac_address1"
        echo "MAC Address 2: $mac_address2"
        echo "---------------------"
        sudo virt-install -n $node_name --memory="$(expr ${CP_RAM_GB} \* 1024)" \
            --disk "size=${DISK_SIZE},path=${LIBVIRT_VM_PATH}/${CLUSTER_NAME}-${node_name}.qcow2,cache=none,format=qcow2" \
            $EXTRA_STORAGE_VAL \
            --cdrom=/var/lib/libvirt/images/agent.x86_64.iso \
            --network ${LIBVIRT_NETWORK},mac=${mac_address1} \
            --network ${LIBVIRT_NETWORK_TWO},mac=${mac_address2} \
            --connect=qemu:///system -v --memballoon none --cpu host-passthrough --autostart --noautoconsole --virt-type kvm --features kvm_hidden=on --controller type=scsi,model=virtio-scsi \
            --graphics vnc,listen=0.0.0.0 --noautoconsole -v --vcpus "sockets=1,cores=${CP_CPU_CORES},threads=1" --os-variant=rhel8.6 || exit $?
    fi

    # If Redfish option is enabled, register the VM with sushy-tools
    if [ "$USE_REDFISH" == true ]; then
        echo "Redfish is enabled for node: $node_name"
        # Notify sushy-tools of the new VM
        sudo sushy-emulator-manager register ${node_name}
    fi

    # Increment counter for differentiating resources for first 3 nodes
    ((counter++))

    # Reset counter to 0 after processing first 3 nodes
    #[ "$counter" -eq 6 ] && counter=0
done
