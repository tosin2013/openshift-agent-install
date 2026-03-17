#!/bin/bash
# ./hack/deploy-on-kvm.sh examples/bond0-signal-vlan/nodes.yml
#set -xe

# Check if the argument is provided
if [ $# -lt 1 ]; then
    echo "Usage: $0 <yaml_file> [--redfish]"
    exit 1
fi

yaml_file=$1
LIBVIRT_NETWORK="network=1924,model=e1000e"
LIBVIRT_NETWORK_TWO="network=1924,model=e1000e"
LIBVIRT_VM_PATH="/var/lib/libvirt/images"
MULTI_NETWORK=true
if [  -z $CLUSTER_NAME ]; then
    CLUSTER_NAME="ocp4"
fi

USE_REDFISH=true
# Use GENERATED_ASSET_PATH as an environment variable, default to "playbooks/generated_manifests" if not set
if [ -z "${GENERATED_ASSET_PATH}" ]; then
    GENERATED_ASSET_PATH="${HOME}/generated_assets"
else 
    echo "GENERATED_ASSET_PATH is set to ${GENERATED_ASSET_PATH}"
fi


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

# Function to configure DNS entries in libvirt network
configure_cluster_dns() {
    local cluster_config=$1

    echo "============================================================="
    echo "Configuring DNS entries in libvirt network..."
    echo "============================================================="

    # Parse cluster configuration
    local cluster_name=$(yq eval '.cluster_name' "$cluster_config")
    local base_domain=$(yq eval '.base_domain' "$cluster_config")
    local api_vip=$(yq eval '.api_vips[0]' "$cluster_config")
    local app_vip=$(yq eval '.app_vips[0]' "$cluster_config")

    # Validate
    if [ -z "$cluster_name" ] || [ -z "$base_domain" ] || [ -z "$api_vip" ] || [ -z "$app_vip" ]; then
        echo "Error: Missing required cluster configuration"
        return 1
    fi

    echo "Cluster: ${cluster_name}.${base_domain}"
    echo "API VIP: ${api_vip}"
    echo "App VIP: ${app_vip}"

    # Add API DNS entries
    echo "Adding API DNS entries..."
    sudo virsh net-update default add dns-host \
      "<host ip='${api_vip}'><hostname>api.${cluster_name}.${base_domain}</hostname><hostname>api-int.${cluster_name}.${base_domain}</hostname></host>" \
      --live --config 2>&1 | grep -v "already exists" || true

    # Add common app hostnames (libvirt dnsmasq doesn't support wildcards)
    echo "Adding application DNS entries..."
    local apps="console-openshift-console oauth-openshift grafana-openshift-monitoring prometheus-k8s-openshift-monitoring alertmanager-main-openshift-monitoring thanos-querier-openshift-monitoring downloads-openshift-console"
    for app in $apps; do
        sudo virsh net-update default add dns-host \
          "<host ip='${app_vip}'><hostname>${app}.apps.${cluster_name}.${base_domain}</hostname></host>" \
          --live --config 2>&1 | grep -v "already exists" || true
    done

    echo "DNS entries configured successfully"
    echo "Test with: dig @192.168.122.1 api.${cluster_name}.${base_domain}"
    echo ""
}

# Function to configure host DNS to use libvirt
configure_host_dns() {
    echo "============================================================="
    echo "Configuring host to use libvirt DNS..."
    echo "============================================================="

    # Detect primary connection (exclude loopback and libvirt bridges)
    local primary_conn=$(nmcli -t -f NAME,DEVICE connection show --active | grep -v "lo\|virbr" | head -1 | cut -d: -f1)

    if [ -z "$primary_conn" ]; then
        echo "Warning: Could not detect primary network connection"
        return 1
    fi

    echo "Primary connection: $primary_conn"

    # Get current DNS servers
    local current_dns=$(nmcli -g ipv4.dns connection show "$primary_conn" | tr ',' ' ')

    # Check if 192.168.122.1 is already first
    if echo "$current_dns" | grep -q "^192.168.122.1"; then
        echo "Host DNS already configured with libvirt DNS as primary"
        return 0
    fi

    # Build new DNS list: 192.168.122.1 first, then existing servers
    local new_dns="192.168.122.1"
    for dns in $current_dns; do
        if [ "$dns" != "192.168.122.1" ]; then
            new_dns="$new_dns $dns"
        fi
    done

    echo "Setting DNS servers: $new_dns"

    # Update connection
    sudo nmcli connection modify "$primary_conn" ipv4.dns "$new_dns"
    sudo nmcli connection up "$primary_conn"

    echo "Host DNS configured successfully"
    echo "  Primary: 192.168.122.1 (libvirt - cluster DNS)"
    echo "  Backup: ${current_dns// /, } (upstream)"
    echo ""
}

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
    elif [ "$num" -eq 5 ]; then
            CP_CPU_CORES=6
            CP_RAM_GB=24
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
    echo "Installing required packages..."
    sudo dnf install bind-utils libguestfs-tools cloud-init virt-install -yy
    sudo dnf module install virt -yy
    sudo systemctl enable libvirtd --now

    echo "Installing Podman..."
    sudo dnf install podman -yy
    
    echo "Configuring sushy-tools..."
    sudo mkdir -p /etc/sushy/
    cat << "EOF" | sudo tee /etc/sushy/sushy-emulator.conf
SUSHY_EMULATOR_LISTEN_IP = '0.0.0.0'
SUSHY_EMULATOR_LISTEN_PORT = 8000
SUSHY_EMULATOR_SSL_CERT = None
SUSHY_EMULATOR_SSL_KEY = None
SUSHY_EMULATOR_OS_CLOUD = None
SUSHY_EMULATOR_LIBVIRT_URI = 'qemu:///system'
SUSHY_EMULATOR_IGNORE_BOOT_DEVICE = True
SUSHY_EMULATOR_BOOT_LOADER_MAP = {
    'UEFI': {
        'x86_64': '/usr/share/OVMF/OVMF_CODE.secboot.fd'
    },
    'Legacy': {
        'x86_64': None
    }
}
EOF
    
    echo "Running sushy-tools container..."
    export SUSHY_TOOLS_IMAGE=${SUSHY_TOOLS_IMAGE:-"quay.io/metal3-io/sushy-tools"}
    sudo podman create --net host --privileged --name sushy-emulator -v "/etc/sushy":/etc/sushy -v "/var/run/libvirt":/var/run/libvirt "${SUSHY_TOOLS_IMAGE}" sushy-emulator -i :: -p 8000 --config /etc/sushy/sushy-emulator.conf
    
    echo "Creating systemd service for sushy-emulator..."
    sudo sh -c 'podman generate systemd --restart-policy=always -t 1 sushy-emulator > /etc/systemd/system/sushy-emulator.service'
    sudo systemctl daemon-reload
    sudo systemctl restart sushy-emulator.service
    sudo systemctl enable sushy-emulator.service

    echo "Configuring firewall..."
    sudo systemctl start firewalld
    sudo firewall-cmd --add-port=8000/tcp

    # Test Redfish API
    echo "Testing Redfish API..."
    sleep 10  # Give some time for sushy-emulator to start properly
    if curl -s http://localhost:8000/redfish/v1/Managers | grep -q "ManagerCollection"; then
        echo "Redfish API is up and running."
    else
        echo "Failed to start Redfish API. Exiting..."
        exit 1
    fi
fi

# Configure DNS entries for the cluster
echo "============================================================="
echo "Setting up DNS configuration..."
echo "============================================================="

# Determine cluster config file path
CLUSTER_CONFIG_FILE="${yaml_file%/nodes.yml}/cluster.yml"
if [ ! -f "$CLUSTER_CONFIG_FILE" ]; then
    # Try alternate path format
    CLUSTER_CONFIG_FILE="examples/$(basename $(dirname ${yaml_file}))/cluster.yml"
fi

if [ -f "$CLUSTER_CONFIG_FILE" ]; then
    echo "Using cluster config: $CLUSTER_CONFIG_FILE"

    # Configure libvirt DNS entries
    configure_cluster_dns "$CLUSTER_CONFIG_FILE" || echo "Warning: DNS configuration failed but continuing deployment"

    # Configure host to use libvirt DNS
    configure_host_dns || echo "Warning: Host DNS configuration failed but continuing deployment"
else
    echo "Warning: cluster.yml not found at $CLUSTER_CONFIG_FILE, skipping DNS configuration"
fi

echo "============================================================="
echo ""

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
        if [ -f /var/lib/libvirt/images/${CLUSTER_NAME}-${node_name}-odf.qcow2 ]; then
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

    # Increment counter for differentiating resources for first 3 nodes
    ((counter++))

    # Reset counter to 0 after processing first 3 nodes
    #[ "$counter" -eq 6 ] && counter=0
done

# Verify the installation if Redfish is enabled
if [ "$USE_REDFISH" == true ]; then
    echo "Verifying Redfish registration..."
    registered_systems=$(curl -s http://localhost:8000/redfish/v1/Systems)
    echo "Registered systems:"
    echo "$registered_systems"

    # Print the name of each registered system
    echo "Details of Registered Systems:"
    echo "$registered_systems" | jq -r '.Members[]."@odata.id"' | while read system; do
        system_details=$(curl -s http://localhost:8000"$system")
        system_name=$(echo "$system_details" | jq -r '.Name')
        echo "System Name: $system_name, System ID: $system"
    done
fi
