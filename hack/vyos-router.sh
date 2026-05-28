#!/bin/bash

# Source VyOS router functions
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# --- DNS Configuration Detection ---
# Prefer dnsmasq (modern, per ADR-019), fallback to FreeIPA (legacy)

USE_DNS="dnsmasq"  # Default to modern DNS approach

# Check if dnsmasq is available and running
if systemctl is-active --quiet dnsmasq; then
    echo "✓ Using dnsmasq for DNS (modern setup per ADR-019)"
    USE_DNS="dnsmasq"
    # Get DNS forwarder from system DNS or use common defaults
    DNS_FORWARDER=$(grep -m1 "^nameserver" /etc/resolv.conf | awk '{print $2}' || echo "8.8.8.8")
    echo "  DNS Forwarder: ${DNS_FORWARDER}"
else
    echo "⚠ dnsmasq not running, checking for FreeIPA configuration..."
    # Try to source FreeIPA variables (optional, for legacy setups)
    if [ -f ${SCRIPT_DIR}/../hack/freeipa_vars.sh ]; then
        source ${SCRIPT_DIR}/../hack/freeipa_vars.sh
        USE_DNS="freeipa"
        echo "✓ Using FreeIPA for DNS (legacy setup)"
        echo "  ZONE_NAME: ${ZONE_NAME}"
        echo "  DOMAIN: ${DOMAIN}"
    else
        echo "❌ ERROR: No DNS server found!"
        echo ""
        echo "VyOS router requires DNS for network configuration."
        echo "Please ensure dnsmasq is running:"
        echo "  sudo ./hack/setup-dnsmasq.sh"
        echo "  sudo systemctl status dnsmasq"
        echo ""
        echo "Or install FreeIPA (legacy, not recommended)"
        exit 1
    fi
fi

# Configure domain settings if using FreeIPA
if [ "$USE_DNS" = "freeipa" ] && [ ! -z ${ZONE_NAME} ]; then
  DOMAIN=${GUID}.${ZONE_NAME}
  ${USE_SUDO} yq e -i '.domain = "'${DOMAIN}'"' /opt/qubinode_navigator/inventories/${TARGET_SERVER}/group_vars/all.yml 2>/dev/null || true
  ${USE_SUDO} yq e -i '.base_domain = "'${DOMAIN}'"' ${CLUSTER_FILE_PATH} 2>/dev/null || true
  DNS_FORWARDER=$(yq eval '.dns_forwarder' "${ANSIBLE_ALL_VARIABLES}" 2>/dev/null || echo "8.8.8.8")
  ${USE_SUDO} yq e -i '.dns_servers[0] = "'${DNS_FORWARDER}'"' ${CLUSTER_FILE_PATH} 2>/dev/null || true
  ${USE_SUDO} yq e -i '.dns_search_domains[0] = "'${DOMAIN}'"' ${CLUSTER_FILE_PATH} 2>/dev/null || true
  ${USE_SUDO} yq e -i 'del(.dns_search_domains[1])' ${CLUSTER_FILE_PATH} 2>/dev/null || true
fi

echo "✓ DNS configuration ready (${USE_DNS})"

function create_livirt_networks(){
    array=( "1924" "1925" "1926" "1927"  "1928" )
    for i in "${array[@]}"
    do
        echo "Checking network $i..."

        # Check if network exists and is active using sudo for the entire pipeline
        if sudo bash -c "virsh net-list --all | grep -q '^[[:space:]]*$i[[:space:]]*active'"; then
            echo "Network $i exists and is active"
            continue
        fi

        echo "Creating network $i..."

        # Create network XML with proper permissions
        sudo bash -c "cat > /tmp/$i.xml << EOF
<network>
  <name>$i</name>
  <bridge name='virbr$(echo "${i:0-1}")' stp='on' delay='0'/>
  <domain name='$i' localOnly='yes'/>
</network>
EOF"

        # Define network with error handling
        if ! sudo virsh net-define /tmp/$i.xml; then
            echo "Error: Failed to define network $i"
            continue
        fi

        # Start network with error handling
        if ! sudo virsh net-start $i; then
            echo "Error: Failed to start network $i"
            continue
        fi

        # Enable autostart with error handling
        if ! sudo virsh net-autostart $i; then
            echo "Error: Failed to set autostart for network $i"
            continue
        fi

        echo "Successfully created and configured network $i"
        
        # Cleanup
        sudo rm -f /tmp/$i.xml
    done
}


function show_manual_config_instructions(){
    # Write instructions to file for user to read
    INSTRUCTIONS_FILE="/tmp/vyos-manual-config-instructions.txt"

    cat > "$INSTRUCTIONS_FILE" << 'EOFINSTRUCTIONS'
============================================================================
⚠️  MANUAL CONFIGURATION REQUIRED - VyOS Router
============================================================================

The VyOS router VM will be created and will require manual configuration
via Cockpit web console before deployment can continue.

📋 STEP 1: Access Cockpit Web Console
EOFINSTRUCTIONS

    echo "   URL: https://$(hostname -I | awk '{print $1}'):9090" >> "$INSTRUCTIONS_FILE"

    cat >> "$INSTRUCTIONS_FILE" << 'EOFINSTRUCTIONS'

   Credentials:
EOFINSTRUCTIONS

    # Check for Cockpit credentials file
    COCKPIT_CREDS="$HOME/cockpit-credentials.txt"
    if [ -f "$COCKPIT_CREDS" ]; then
        echo "   → View with: cat ~/cockpit-credentials.txt" >> "$INSTRUCTIONS_FILE"
    else
        echo "   → Use your system user credentials" >> "$INSTRUCTIONS_FILE"
    fi

    cat >> "$INSTRUCTIONS_FILE" << 'EOFINSTRUCTIONS'

📋 STEP 2: Open VyOS Console in Cockpit
   1. Click 'Virtual Machines' in left sidebar
   2. Click 'vyos-router'
   3. Click 'Console' tab

📋 STEP 3: Configure VyOS Router
   Login: vyos / vyos

   Commands to run:
   1. install image          (VM will restart - manually start it again)
   2. Configure network:
      configure
      set interfaces ethernet eth0 address 192.168.122.2/24
      set interfaces ethernet eth0 description Internet-Facing
      set protocols static route 0.0.0.0/0 next-hop 192.168.122.1
      commit
      save
   3. Enable SSH:
      configure
      set service ssh
      commit
      save
      exit
   4. Apply config script:
      scp ~/vyos-config.sh vyos@192.168.122.2:/tmp/
      ssh vyos@192.168.122.2
      chmod +x /tmp/vyos-config.sh
      vbash /tmp/vyos-config.sh

   Detailed guide:
   https://github.com/tosin2013/demo-virt/blob/rhpds/demo.redhat.com/docs/step1.md

⏱️  The script will wait up to 30 minutes (checking every 5 minutes)

============================================================================
EOFINSTRUCTIONS

    # Display to console
    cat "$INSTRUCTIONS_FILE"
    echo ""
    echo "Instructions saved to: $INSTRUCTIONS_FILE"
    echo ""

    # Pause for user acknowledgment
    echo "════════════════════════════════════════════════════════════════════════════"
    echo "⚠️  IMPORTANT: Please read the instructions above carefully"
    echo "════════════════════════════════════════════════════════════════════════════"
    echo ""
    read -p "Press ENTER to continue and start VyOS VM deployment..."
    echo ""
}

function create(){
    # Show instructions FIRST, before creating anything
    show_manual_config_instructions

    export ip_address="${DNS_FORWARDER}"
    create_livirt_networks
    # Vyos nightly builds
    # https://github.com/vyos/vyos-rolling-nightly-builds/releases
    # Auto-updated by .github/workflows/update-vyos-version.yml
    VYOS_VERSION=2026.05.28-0044-rolling
    ISO_LOC=https://github.com/vyos/vyos-nightly-build/releases/download/${VYOS_VERSION}/vyos-${VYOS_VERSION}-generic-amd64.iso
    if [ ! -f $HOME/vyos-${VYOS_VERSION}-generic-amd64.iso ];
    then
        cd $HOME
        curl -OL $ISO_LOC
    fi
  
    VM_NAME=vyos-router
    
    # Copy ISO for seed
    sudo cp $HOME/vyos-${VYOS_VERSION}-generic-amd64.iso $HOME/seed.iso
    sudo mv $HOME/seed.iso /var/lib/libvirt/images/seed.iso

    # Generate qcow2 blank image
    sudo qemu-img create -f qcow2 /var/lib/libvirt/images/$VM_NAME.qcow2 20G

    sudo virt-install -n ${VM_NAME} \
      --ram 4096 \
      --vcpus 2 \
      --cdrom /var/lib/libvirt/images/seed.iso \
      --os-variant debian10 \
      --network network=default,model=e1000e,mac=$(date +%s | md5sum | head -c 6 | sed -e 's/\([0-9A-Fa-f]\{2\}\)/\1:/g' -e 's/\(.*\):$/\1/' | sed -e 's/^/52:54:00:/') \
      --network network=1924,model=e1000e \
      --network network=1925,model=e1000e \
      --network network=1926,model=e1000e \
      --network network=1927,model=e1000e \
      --network network=1928,model=e1000e \
      --graphics vnc \
      --hvm \
      --virt-type kvm \
      --disk path=/var/lib/libvirt/images/$VM_NAME.qcow2,bus=virtio \
      --import \
      --noautoconsole

}

function configure_router(){
    # Download VyOS configuration script template
    if [ ! -f $HOME/vyos-config.sh ]; then
      cd $HOME
      curl -OL https://raw.githubusercontent.com/tosin2013/demo-virt/rhpds/demo.redhat.com/vyos-config-1.5.sh
      mv vyos-config-1.5.sh vyos-config.sh
      chmod +x vyos-config.sh
      sed -i "s/1.1.1.1/${ip_address}/g" vyos-config.sh
      sed -i "s/example.com/${DOMAIN}/g" vyos-config.sh
    fi

    # Instructions already shown by show_manual_config_instructions()
    # No need to repeat them here - just start waiting

    MAX_WAIT_TIME=1800
    WAIT_INTERVAL=300
    IP_ADDRESS=192.168.122.2
    start_time=$(date +%s)
    end_time=$((start_time + $MAX_WAIT_TIME))

    echo "⏳ Waiting for VyOS router to become accessible at $IP_ADDRESS..."
    echo ""

    router_accessible=false
    check_count=0
    while [ "$router_accessible" = false ]; do
      if ping -c 1 "$IP_ADDRESS" > /dev/null 2>&1; then
        echo ""
        echo "✅ Router is accessible now at $IP_ADDRESS"
        echo "✅ Continuing with deployment..."
        router_accessible=true
      else
        current_time=$(date +%s)
        remaining_time=$((end_time - current_time))

        if [ $remaining_time -gt 0 ]; then
          check_count=$((check_count + 1))
          echo "⏳ Check #$check_count: VyOS not yet accessible (still configuring?)"
          echo "   Remaining time: $((remaining_time / 60)) minutes"
          echo "   If you haven't started configuration yet, access Cockpit now:"
          echo "   → https://$(hostname -I | awk '{print $1}'):9090"
          echo ""
          sleep "$WAIT_INTERVAL"
        else
          echo ""
          echo "============================================================================"
          echo "❌ Timeout reached after 30 minutes"
          echo "============================================================================"
          echo ""
          echo "VyOS router is still not accessible at $IP_ADDRESS"
          echo ""
          echo "Troubleshooting:"
          echo "1. Check VyOS VM is running: sudo virsh list"
          echo "2. Access Cockpit console to check VyOS status"
          echo "3. Verify you completed all configuration steps"
          echo "4. Check VyOS console for errors"
          echo ""
          echo "You can manually retry configuration:"
          echo "   sudo virsh console vyos-router"
          echo ""
          echo "Or re-run this script:"
          echo "   ACTION=create ./hack/vyos-router.sh"
          echo ""
          echo "============================================================================"
          return 1
        fi
      fi
    done
    networks=(
              "192.168.49.0/24"
              "192.168.50.0/24"
              "192.168.51.0/24"
              "192.168.52.0/24"
              "192.168.53.0/24"
              "192.168.54.0/24"
              "192.168.55.0/24"
              "192.168.56.0/24"
              "192.168.57.0/24"
              "192.168.58.0/24"
          )

    gateway="192.168.122.2"

    for net in "${networks[@]}"; do
        if ! ip route show | grep -q "$net"; then
            sudo ip route add "$net" via "$gateway"
            echo "Route for $net added."
        else
            echo "Route for $net already exists."
        fi
    done

    IP_ADDRESS=192.168.50.1
    MAX_WAIT_TIME=1800
    WAIT_INTERVAL=300
    start_time=$(date +%s)
    end_time=$((start_time + $MAX_WAIT_TIME))

    echo "Waiting for $IP_ADDRESS to be accessible..."

    router_accessible=false
    while [ "$router_accessible" = false ]; do
      if ping -c 1 "$IP_ADDRESS" > /dev/null 2>&1; then
        echo "Router is accessible now. Continuing..."
        router_accessible=true
      else
        current_time=$(date +%s)
        remaining_time=$((end_time - current_time))

        if [ $remaining_time -gt 0 ]; then
          echo "Router is not accessible yet. Please access this page to manually configure the router: https://github.com/tosin2013/demo-virt/blob/rhpds/demo.redhat.com/docs/step1.md"
          echo "Remaining time: $((remaining_time / 60)) minutes"
          sleep "$WAIT_INTERVAL"
        else
          echo "Timeout reached. Router is still not accessible."
          return 1
        fi
      fi
    done

    echo "Validate Router Deployment"
    if ! ping -c 1 $IP_ADDRESS > /dev/null 2>&1; then
      echo "Router deployment failed. Manual intervention required."
      exit 1 # Fail only if the router is not accessible at this point
    else
      echo "Router is accessible."
    fi
}

function destroy(){
    VM_NAME=vyos-router
    sudo virsh destroy ${VM_NAME}
    sudo virsh undefine ${VM_NAME}
    sudo rm -rf /var/lib/libvirt/images/$VM_NAME.qcow2
    sudo rm -rf /var/lib/libvirt/images/seed.iso
}

if [ $ACTION == "create" ];
then 

  if ping -c 1 192.168.122.2 > /dev/null 2>&1; then
    echo "Router is accessible now. Continuing..."
  else
    create
  fi

  if ping -c 1 192.168.150.1  > /dev/null 2>&1; then
    echo "Router vlan is accessible now. Continuing..."
  else
    configure_router
  fi
elif [ $ACTION == "delete" ]; 
then 
  destroy
else 
  echo "help"
fi
