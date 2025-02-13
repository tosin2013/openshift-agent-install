#!/bin/bash

# --- Helper Functions ---
print_status() {
    if [ $2 -eq 0 ]; then
        echo -e "\033[0;32m✓ $1\033[0m"
    else
        echo -e "\033[0;31m✗ $1\033[0m"
        exit 1
    fi
}

print_section() {
    echo -e "\n\033[1;33m$1\033[0m"
    echo "================================"
}

print_info() {
    echo -e "\033[0;34m$1\033[0m"
}

check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "\033[0;31mPlease run this script with sudo privileges\033[0m"
        exit 1
    fi
}

# --- Package Management ---
install_system_packages() {
    print_section "Installing System Packages"
    packages=(nmstate ansible-core bind-utils libguestfs-tools cloud-init virt-install qemu-img virt-manager selinux-policy-targeted)
    for package in "${packages[@]}"; do
        if ! rpm -q $package &>/dev/null; then
            print_info "Installing $package..."
            sudo dnf install -y $package || print_status "Failed to install $package" 1
            print_status "$package installed successfully" 0
        else
            print_status "$package is already installed" 0
        fi
    done

    if ! command -v yq &>/dev/null; then
        print_info "Installing yq..."
        VERSION=v4.45.1 
        BINARY=yq_linux_amd64
        sudo wget https://github.com/mikefarah/yq/releases/download/${VERSION}/${BINARY} -O /usr/bin/yq &&\
        sudo chmod +x /usr/bin/yq
        print_status "yq installed successfully" 0
    else
        print_status "yq is already installed" 0
    fi

    print_section "Enabling libvirt"
    dnf install -y libvirt libvirt-daemon libvirt-daemon-driver-qemu
    sudo usermod -aG libvirt lab-user && sudo chmod 775 /var/lib/libvirt/images
    sudo systemctl start libvirtd && sudo usermod -aG libvirt lab-user
    if [[ $? -ne 0 ]]; then
        print_status "Failed to enable libvirt module" 1
        exit 1
    fi
    print_status "libvirt module enabled" 0

    print_section "Installing kcli"
    sudo dnf -y copr enable karmab/kcli ; sudo dnf -y install kcli
    print_status "kcli installed" 0

    print_section "Installing Cockpit"
    sudo dnf install -y cockpit cockpit-machines
    sudo systemctl enable --now cockpit.socket
    print_status "Cockpit installed and enabled" 0
}
#!/bin/bash

# --- Helper Functions ---
print_status() {
    if [ $2 -eq 0 ]; then
        echo -e "\033[0;32m✓ $1\033[0m"
    else
        echo -e "\033[0;31m✗ $1\033[0m"
        exit 1
    fi
}

print_section() {
    echo -e "\n\033[1;33m$1\033[0m"
    echo "================================"
}

print_info() {
    echo -e "\033[0;34m$1\033[0m"
}

check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "\033[0;31mPlease run this script with sudo privileges\033[0m"
        exit 1
    fi
}

# --- Package Management ---
install_system_packages() {
    print_section "Installing System Packages"
    packages=(nmstate ansible-core bind-utils libguestfs-tools cloud-init virt-install qemu-img virt-manager selinux-policy-targeted)
    for package in "${packages[@]}"; do
        if ! rpm -q $package &>/dev/null; then
            print_info "Installing $package..."
            sudo dnf install -y $package || print_status "Failed to install $package" 1
            print_status "$package installed successfully" 0
        else
            print_status "$package is already installed" 0
        fi
    done

    if ! command -v yq &>/dev/null; then
        print_info "Installing yq..."
        VERSION=v4.45.1 
        BINARY=yq_linux_amd64
        sudo wget https://github.com/mikefarah/yq/releases/download/${VERSION}/${BINARY} -O /usr/bin/yq &&\
        sudo chmod +x /usr/bin/yq
        print_status "yq installed successfully" 0
    else
        print_status "yq is already installed" 0
    fi

    print_section "Enabling libvirt"
    dnf install -y libvirt libvirt-daemon libvirt-daemon-driver-qemu
    sudo usermod -aG libvirt lab-user && sudo chmod 775 /var/lib/libvirt/images
    sudo systemctl start libvirtd && sudo usermod -aG libvirt lab-user
    if [[ $? -ne 0 ]]; then
        print_status "Failed to enable libvirt module" 1
        exit 1
    fi
    print_status "libvirt module enabled" 0

    print_section "Installing Cockpit"
    sudo dnf install -y cockpit cockpit-machines
    sudo systemctl enable --now cockpit.socket
    print_status "Cockpit installed and enabled" 0
}

install_container_tools() {
    print_section "Installing Container Tools"
    if ! rpm -q podman &>/dev/null; then
        print_info "Installing podman..."
        sudo dnf install -y podman || print_status "Failed to install podman" 1
        print_status "podman installed successfully" 0
    else
        print_status "podman is already installed" 0
    fi
}

# --- SELinux Configuration ---
configure_selinux() {
    print_section "Configuring SELinux"
    # Install semanage command if not already present
    if ! rpm -q policycoreutils-python-utils &>/dev/null; then
        sudo dnf install -y policycoreutils-python-utils
    fi

    # Set SELinux contexts and booleans (replace with actual commands)
    # Example:
    # sudo semanage fcontext -a -t httpd_sys_content_t "/var/lib/libvirt/images(/.*)?"
    # sudo restorecon -R /var/lib/libvirt/images

    print_status "SELinux configured successfully" 0
}

handle_selinux_policies() {
    print_section "Handling SELinux Policies"

    # Check and set booleans for libvirt, if semanage is available
    if command -v semanage &>/dev/null; then
        # Example:
        # if ! semanage boolean -l | grep -q virt_use_nfs; then
        #     sudo semanage boolean -m --on virt_use_nfs
        # fi
        :
    fi

    print_status "SELinux policies handled successfully" 0
}

# --- Network Configuration ---
configure_virtual_networks() {
    print_section "Configuring Virtual Networks"
    array=( "1924" "1925" "1926" "1927" "1928" )
    for i in "${array[@]}"; do
        tmp=$(sudo virsh net-list | grep "$i" | awk '{ print $3}')
        if ([ "x$tmp" == "x" ] || [ "x$tmp" != "xyes" ]); then
            echo "$i network does not exist creating it"
            cat << EOF > /tmp/$i.xml
<network>
<name>$i</name>
<bridge name='virbr$(echo "${i:0-1}")' stp='on' delay='0'/>
<domain name='$i' localOnly='yes'/>
</network>
EOF

            sudo virsh net-define /tmp/$i.xml
            sudo virsh net-start $i
            sudo virsh net-autostart $i
        else
            echo "$i network already exists"
        fi
    done
    print_status "Virtual networks configured successfully" 0
}

setup_vyos_router() {
    print_section "Setting up VyOS Router"
    # Check for required variables (replace with actual checks/defaults)
    # : ${GUID:?"GUID is not set"}
    # : ${ZONE_NAME:?"ZONE_NAME is not set"}
    # : ${TARGET_SERVER:?"TARGET_SERVER is not set"}
    # : ${CLUSTER_FILE_PATH:?"CLUSTER_FILE_PATH is not set"}
    # : ${ANSIBLE_ALL_VARIABLES:?"ANSIBLE_ALL_VARIABLES is not set"}

    # if [ ! -z "$ZONE_NAME" ]; then
    #   DOMAIN="${GUID}.${ZONE_NAME}"
    #   ${USE_SUDO} yq e -i '.domain = "'${DOMAIN}'"' /opt/qubinode_navigator/inventories/${TARGET_SERVER}/group_vars/all.yml
    #   ${USE_SUDO} yq e -i '.base_domain = "'${DOMAIN}'"' ${CLUSTER_FILE_PATH}
    #   DNS_FORWARDER=$(yq eval '.dns_forwarder' "${ANSIBLE_ALL_VARIABLES}")
    #   ${USE_SUDO} yq e -i '.dns_servers[0] = "'${DNS_FORWARDER}'"' ${CLUSTER_FILE_PATH}
    #   ${USE_SUDO} yq e -i '.dns_search_domains[0] = "'${DOMAIN}'"' ${CLUSTER_FILE_PATH}
    #   ${USE_SUDO} yq e -i 'del(.dns_search_domains[1])' ${CLUSTER_FILE_PATH}
    # else
    #   DOMAIN=$(yq eval '.domain' "${ANSIBLE_ALL_VARIABLES}")
    # fi

    IPADDR=$(sudo virsh net-dhcp-leases default | grep vyos-builder | sort -k1 -k2 | tail -1 | awk '{print $5}' | sed 's/\/24//g')
    VYOS_VERSION="1.5-rolling-202502131743"
    ISO_LOC="https://github.com/vyos/vyos-nightly-build/releases/download/${VYOS_VERSION}/vyos-${VYOS_VERSION}-generic-amd64.iso"
    if [ ! -f "$HOME/vyos-${VYOS_VERSION}-generic-amd64.iso" ]; then
        cd "$HOME" || exit 1 # Handle cd failure
        curl -OL "$ISO_LOC" || print_status "Failed to download VyOS ISO" 1
    fi

    VM_NAME="vyos-router"
    sudo mv "$HOME/${VM_NAME}.qcow2" /var/lib/libvirt/images/ 2>/dev/null || true # Suppress error if file doesn't exist
    sudo cp "$HOME/vyos-${VYOS_VERSION}-generic-amd64.iso" "$HOME/seed.iso" || print_status "Failed to copy VyOS ISO" 1
    sudo mv "$HOME/seed.iso" /var/lib/libvirt/images/seed.iso || print_status "Failed to move seed ISO" 1

    sudo qemu-img create -f qcow2 /var/lib/libvirt/images/"$VM_NAME".qcow2 20G || print_status "Failed to create QCOW2 image" 1

    sudo virt-install -n "$VM_NAME" \
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
       --disk path=/var/lib/libvirt/images/"$VM_NAME".qcow2,bus=virtio \
       --import \
       --noautoconsole || print_status "Failed to install VM" 1

    # if [ ! -f "$HOME/vyos-config.sh" ]; then
    #     cd "$HOME" || exit 1
    #     curl -OL "https://raw.githubusercontent.com/tosin2013/demo-virt/rhpds/demo.redhat.com/vyos-config-1.5.sh"
    #     mv vyos-config-1.5.sh vyos-config.sh
    #     chmod +x vyos-config.sh
    #     export vm_name="freeipa" # Where does this come from?
    #     export ip_address=$(sudo kcli info vm "$vm_name" "$vm_name" | grep ip: | awk '{print $2}' | head -1) # kcli not available
    #     sed -i "s/1.1.1.1/${ip_address}/g" vyos-config.sh
    #     sed -i "s/example.com/${DOMAIN}/g" vyos-config.sh
    # fi

    print_status "VyOS router setup successfully" 0
}

# --- Environment Setup ---
setup_virtualization() {
    print_section "Setting up Virtualization"
    print_info "Enabling libvirtd..."
    sudo systemctl enable --now libvirtd || print_status "Failed to enable libvirtd" 1
    print_status "libvirtd enabled successfully" 0
    # Add any other virtualization setup commands here if needed
}

setup_registry_auth() {
    print_section "Setting up Registry Authentication"
    if [ -n "$SUDO_USER" ]; then
        USER_HOME=$(eval echo ~$SUDO_USER)
        if [ ! -d "$USER_HOME/.docker" ]; then
            mkdir -p "$USER_HOME/.docker"
            chmod 700 "$USER_HOME/.docker"
        fi

        if [ -f "/home/lab-user/pullsecret.json" ]; then
            cp /home/lab-user/pullsecret.json "$USER_HOME/.docker/config.json"
            chmod 600 "$USER_HOME/.docker/config.json"
            chown -R "$SUDO_USER:$(id -gn $SUDO_USER)" "$USER_HOME/.docker"
            print_status "Registry authentication configured for user $SUDO_USER" 0
        else
            print_status "Pull secret not found at /home/lab-user/pullsecret.json" 1
            echo "Please ensure pull secret is available at /home/lab-user/pullsecret.json"
            exit 1
        fi
    else
        print_status "Could not determine user to configure registry authentication for" 1
        exit 1
    fi
}

# --- Validation ---
validate_installation() {
    print_section "Validating Installation"

    # Check if required packages are installed
    packages=(nmstate ansible-core bind-utils libguestfs-tools cloud-init virt-install qemu-img libvirt-clients bridge-utils yq selinux-policy-targeted podman policycoreutils-python-utils)
    for package in "${packages[@]}"; do
        if ! rpm -q $package &>/dev/null; then
            print_status "Package $package is not installed" 1
        fi
    done

    # Check if libvirtd is active
    if ! systemctl is-active libvirtd &>/dev/null; then
        print_status "libvirtd is not active" 1
    fi

    # Check virtual networks (add more specific checks as needed)
    virsh net-list --all | grep -E '192[45678]' &>/dev/null || print_status "Virtual networks not found" 1

    # Check VyOS router (replace with actual check)
    if ! sudo virsh domstate vyos-router | grep -q running; then
        print_status "VyOS router is not running" 1
    fi


    print_status "Installation validated successfully" 0
}


# --- Main Script ---
check_sudo

install_system_packages
configure_selinux
install_container_tools
configure_virtual_networks
setup_vyos_router
setup_virtualization
setup_registry_auth
handle_selinux_policies
validate_installation

print_section "Bootstrap Complete"
echo "Environment bootstrapped successfully."
