#!/bin/bash 

# Source VyOS router functions
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
#ls -lath .

if [ -f ${SCRIPT_DIR}/../hack/freeipa_vars.sh ]; then
  source ${SCRIPT_DIR}/../hack/freeipa_vars.sh
else 
  exit 1
fi

echo "ZONE_NAME: ${ZONE_NAME}"
echo "DOMAIN: ${DOMAIN}"

if [ ! -z ${ZONE_NAME} ];
then
  DOMAIN=${GUID}.${ZONE_NAME}
  ${USE_SUDO} yq e -i '.domain = "'${DOMAIN}'"' /opt/qubinode_navigator/inventories/${TARGET_SERVER}/group_vars/all.yml
  ${USE_SUDO} yq e -i '.base_domain = "'${DOMAIN}'"' ${CLUSTER_FILE_PATH}
  DNS_FORWARDER=$(yq eval '.dns_forwarder' "${ANSIBLE_ALL_VARIABLES}")
  ${USE_SUDO} yq e -i '.dns_servers[0] = "'${DNS_FORWARDER}'"' ${CLUSTER_FILE_PATH}
  ${USE_SUDO} yq e -i '.dns_search_domains[0] = "'${DOMAIN}'"' ${CLUSTER_FILE_PATH}
  ${USE_SUDO} yq e -i 'del(.dns_search_domains[1])' ${CLUSTER_FILE_PATH}
else
  echo "ZONE_NAME is not set"
  echo $DOMAIN
  echo $TARGET_SERVER
fi

function create_livirt_networks(){
    array=( "1924" "1925" "1926" "1927"  "1928" )
    for i in "${array[@]}"
    do
        echo "$i"

        tmp=$(sudo virsh net-list | grep "$i" | awk '{ print $3}')
        if ([ "x$tmp" == "x" ] || [ "x$tmp" != "xyes" ])
        then
            echo "$i network does not exist creating it"
            # Try additional commands here...

            cat << EOF > /tmp/$i.xml
<network>
<name>$i</name>
<bridge name='virbr$(echo "${i:0-1}")' stp='on' delay='0'/>
<domain name='$i' localOnly='yes'/>
</network>
EOF

            sudo virsh net-define /tmp/$i.xml
            sudo virsh net-start $i
            sudo virsh net-autostart  $i
    else
            echo "$i network already exists"
    fi
    done
}

function check_freeipa() {
    export vm_name="freeipa"
    export ip_address=$(sudo kcli info vm "$vm_name" "$vm_name" | grep ip: | awk '{print $2}' | head -1)
    if [ -z "$ip_address" ]; then
        echo "Error: FreeIPA VM IP address not found"
        exit 1
    fi
    echo "FreeIPA IP address: $ip_address"
}

function create(){
    check_freeipa
    create_livirt_networks
    # Vyos nightly builds 
    # https://github.com/vyos/vyos-rolling-nightly-builds/releases
    VYOS_VERSION=1.5-rolling-202502170007
    ISO_LOC=https://github.com/vyos/vyos-nightly-build/releases/download/${VYOS_VERSION}/vyos-${VYOS_VERSION}-generic-amd64.iso
    if [ ! -f $HOME/vyos-${VYOS_VERSION}-amd64.iso ];
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
    if [ ! -f $HOME/vyos-config.sh ]; then 
      cd $HOME
      curl -OL https://raw.githubusercontent.com/tosin2013/demo-virt/rhpds/demo.redhat.com/vyos-config-1.5.sh
      mv vyos-config-1.5.sh vyos-config.sh
      chmod +x vyos-config.sh
      sed -i "s/1.1.1.1/${ip_address}/g" vyos-config.sh
      sed -i "s/example.com/${DOMAIN}/g" vyos-config.sh
    fi

    echo "Waiting for VyOS to boot"
    MAX_WAIT_TIME=1800
    WAIT_INTERVAL=300
    IP_ADDRESS=192.168.122.2
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
