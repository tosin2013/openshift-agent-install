#!/bin/bash 

if [ "$EUID" -ne 0 ]
then 
  export USE_SUDO="sudo"
fi

if [ ! -z "$CICD_PIPELINE" ]; then
  export USE_SUDO="sudo"
fi


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
  DOMAIN=$(yq eval '.domain' "${ANSIBLE_ALL_VARIABLES}")
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
    IPADDR=$(sudo virsh net-dhcp-leases default | grep vyos-builder  | sort -k1 -k2 | tail -1 | awk '{print $5}' | sed 's/\/24//g')
    # Vyos nightly builds 
    # https://github.com/vyos/vyos-rolling-nightly-builds/releases
    VYOS_VERSION=1.5-rolling-202409250007
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
  if [ ! -f $HOME/vyos-config.sh ]; then 
    cd $HOME
    curl -OL https://raw.githubusercontent.com/tosin2013/demo-virt/rhpds/demo.redhat.com/vyos-config-1.5.sh
    mv vyos-config-1.5.sh vyos-config.sh
    chmod +x vyos-config.sh
    sed -i "s/1.1.1.1/${ip_address}/g" vyos-config.sh
    sed -i "s/example.com/${DOMAIN}/g" vyos-config.sh
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
  create
elif [ $ACTION == "delete" ]; 
then 
  destroy
else 
  echo "help"
fi
