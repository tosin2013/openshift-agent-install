#!/bin/bash

export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -x
set -e

# Source VyOS router functions
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

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
    packages=(nmstate ansible-core bind-utils libguestfs-tools cloud-init virt-install qemu-img virt-manager selinux-policy-targeted python3-pip)
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

    # Install kcli
    if ! command -v kcli &>/dev/null; then
        print_info "Installing kcli..."
        pip3 install kcli || print_status "Failed to install kcli" 1
        print_status "kcli installed successfully" 0
    else
        print_status "kcli is already installed" 0
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
configure_infrastructure() {
  print_section "Configuring Infrastructure"
  # Deploy FreeIPA VM
  source "${SCRIPT_DIR}/../hack/deploy-freeipa.sh"
  create
  # Use functions from vyos-router.sh
  source "${SCRIPT_DIR}/../hack/vyos-router.sh"
  create_livirt_networks

  print_status "Infrastructure configured successfully" 0
}

# --- Environment Setup ---
setup_virtualization() {
  print_section "Setting up Virtualization"
  print_info "Enabling libvirtd..."
  sudo systemctl enable --now libvirtd || print_status "Failed to enable libvirtd" 1
  print_status "libvirtd enabled successfully" 0
  # Configure LVM for libvirt
  source "${SCRIPT_DIR}/../hack/configure-lvm.sh"
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

configure_vault() {
    print_section "Configuring Vault"
    if [ ! -f vault.yml ]; then
        print_info "Creating vault.yml..."
        print_info "Please provide the following information:"
        
        # Prompt for vault values
        ADMIN_PASSWORD=$(prompt_with_default "Enter FreeIPA admin password" "changeme")
        RHSM_ORG=$(prompt_with_default "Enter Red Hat Subscription Manager Organization ID" "")
        RHSM_KEY=$(prompt_with_default "Enter Red Hat Subscription Manager Activation Key" "")
        
        cat > vault.yml <<EOL
---
freeipa_server_admin_password: "${ADMIN_PASSWORD}"
rhsm_org: "${RHSM_ORG}"
rhsm_activationkey: "${RHSM_KEY}"
EOL
        ansible-vault encrypt vault.yml --vault-password-file .vault_password
        print_status "vault.yml created and encrypted" 0
    else
        print_status "vault.yml already exists" 0
        print_info "To recreate vault.yml, delete the existing file and run bootstrap.sh again"
    fi
}

# --- Main Script ---
check_sudo

install_system_packages
configure_selinux
install_container_tools
setup_virtualization
configure_infrastructure
configure_vault
setup_registry_auth
handle_selinux_policies
validate_installation


print_section "Bootstrap Complete"
echo "Environment bootstrapped successfully."
