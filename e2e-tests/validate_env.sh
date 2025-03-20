#!/bin/bash

# This script validates the environment for end-to-end tests targeting OpenShift 4.18
# export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
# set -x
# set -e


# Set script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

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
        exit 1 # Exit on failure to prevent further execution
    fi
}

print_section() {
    echo -e "\n${YELLOW}$1${NC}"
    echo "================================"
}

print_info() {
    echo -e "${BLUE}$1${NC}"
}

# Check if a command exists
command_exists() {
    type "$1" >/dev/null 2>&1
}

# --- System Package Validation ---
validate_system_packages() {
    print_section "Validating System Packages"
    packages=(nmstate ansible-core bind-utils cloud-init virt-install qemu-img virt-manager selinux-policy-targeted python3-pip)
    
    for package in "${packages[@]}"; do
        if rpm -q "$package" &>/dev/null; then
            print_status "$package is installed" 0
        else
            print_status "$package is not installed" 1
        fi
    done

    # Check Ansible collections
    print_info "Checking Ansible collections..."
    if [ -f "${SCRIPT_DIR}/../playbooks/collections/requirements.yml" ]; then
        # List installed collections and compare with requirements
        ansible-galaxy collection list > /tmp/installed_collections
        while IFS= read -r line; do
            if [[ $line =~ ^#.* ]] || [[ -z $line ]]; then
                continue
            fi
            if [[ "$line" =~ ^---$ ]]; then
                continue
            fi
            collection_name=$(echo "$line" | awk -F': ' '{print $2}')
            if grep -q "$collection_name" /tmp/installed_collections; then
                print_status "Ansible collection $collection_name is installed" 0
            else
                print_status "Ansible collection $collection_name is not installed" 1
            fi
        done < "${SCRIPT_DIR}/../playbooks/collections/requirements.yml"
        rm -f /tmp/installed_collections
    else
        print_status "Ansible collections requirements file not found" 1
    fi

    # Check yq installation
    if command_exists yq; then
        print_status "yq is installed" 0
    else
        print_status "yq is not installed" 1
    fi

    # Check kcli installation
    if command_exists kcli; then
        print_status "kcli is installed" 0
    else
        print_status "kcli is not installed" 1
    fi

    # Check libvirt installation
    if systemctl is-active libvirtd &>/dev/null; then
        print_status "libvirtd is running" 0
    else
        print_status "libvirtd is not running" 1
    fi

    # Check Cockpit installation
    if systemctl is-active cockpit.socket &>/dev/null; then
        print_status "Cockpit is running" 0
    else
        print_status "Cockpit is not running" 1
    fi
}

# --- OpenShift CLI Validation ---
validate_openshift_cli() {
    print_section "Validating OpenShift CLI Tools"
    
    # Check oc installation
    whereis oc
    if command_exists oc; then
        print_status "oc is installed" 0
        # Validate oc version
        rhel_version=$(rpm -E %{rhel})
        if [ "$rhel_version" -eq 8 ]; then
            expected_version="4.15"
        else
            expected_version="4.18"
        fi
        if oc version | grep -q "$expected_version"; then
            print_status "oc version is correct ($expected_version)" 0
        else
            print_status "oc version mismatch (expected $expected_version)" 1
        fi
    else
        print_status "oc is not installed" 1
    fi

    # Check openshift-install
    if command_exists openshift-install; then
        print_status "openshift-install is installed" 0
    else
        print_status "openshift-install is not installed" 1
    fi
}

# --- Container Tools Validation ---
validate_container_tools() {
    print_section "Validating Container Tools"
    if rpm -q podman &>/dev/null; then
        print_status "podman is installed" 0
    else
        print_status "podman is not installed" 1
    fi
}

# --- SELinux Validation ---
validate_selinux() {
    print_section "Validating SELinux Configuration"
    
    # Check if SELinux is permissive
    if [ "$(getenforce)" == "Permissive" ]; then
        print_status "SELinux is permissive" 0
    else
        print_status "SELinux is not permissive" 1
    fi

    # Check for policycoreutils-python-utils
    if rpm -q policycoreutils-python-utils &>/dev/null; then
        print_status "policycoreutils-python-utils is installed" 0
    else
        print_status "policycoreutils-python-utils is not installed" 1
    fi
}

# --- Infrastructure Validation ---
validate_infrastructure() {
    print_section "Validating Infrastructure"

    # Check FreeIPA VM
    if sudo kcli list vm | grep -q "freeipa"; then
        print_status "FreeIPA VM exists" 0
        
        # Check FreeIPA VM IP
        if ip_address=$(sudo kcli info vm freeipa freeipa | grep ip: | awk '{print $2}' | head -1) && [ -n "$ip_address" ]; then
            print_status "FreeIPA VM has IP address: $ip_address" 0
        else
            print_status "FreeIPA VM IP address not found" 1
        fi
    else
        print_status "FreeIPA VM not found" 1
    fi
}

# --- Registry Auth Validation ---
validate_registry_auth() {
    print_section "Validating Registry Authentication"
    
    # Check pull secret
    if [ -f "/home/lab-user/pullsecret.json" ]; then
        print_status "Pull secret exists" 0
    else
        print_status "Pull secret not found at /home/lab-user/pullsecret.json" 1
    fi

    # Check docker config
    if [ -f "/home/lab-user/.docker/config.json" ]; then
        print_status "Docker config exists" 0
    else
        print_status "Docker config not found" 1
    fi
}

# --- Ansible Vault Validation ---
validate_ansible_vault() {
    print_section "Validating Ansible Vault Setup"
    
    # Check vault password file
    if [ -f "/home/lab-user/.vault_password" ]; then
        # Verify permissions
        PERMS=$(stat -c "%a" /home/lab-user/.vault_password)
        OWNER=$(stat -c "%U:%G" /home/lab-user/.vault_password)
        if [ "$PERMS" = "600" ] && [ "$OWNER" = "lab-user:users" ]; then
            print_status "Vault password file exists with correct permissions" 0
        else
            print_status "Vault password file has incorrect permissions" 1
        fi
    else
        print_status "Vault password file not found" 1
    fi

    # Check vault.yml
    if [ -f "vault.yml" ]; then
        # Verify if file is encrypted
        if grep -q "ANSIBLE_VAULT" "vault.yml"; then
            print_status "vault.yml exists and is encrypted" 0
        else
            print_status "vault.yml exists but is not encrypted" 1
        fi
    else
        print_status "vault.yml not found" 1
    fi
}

# --- Operating System Validation ---
validate_os() {
    print_section "Validating Operating System"
    if [[ "$(cat /etc/redhat-release)" == *"Red Hat Enterprise Linux release 9.5 (Plow)"* ]]; then
        print_status "Operating System is Red Hat Enterprise Linux release 9.5 (Plow)" 0
    else
        print_status "Operating System is not Red Hat Enterprise Linux release 9.5 (Plow)" 1
    fi
}

# --- Main Validation ---
validate_environment() {
    print_section "Starting Environment Validation"

    validate_os
    validate_system_packages
    validate_openshift_cli
    validate_container_tools
    validate_selinux
    validate_infrastructure
    validate_registry_auth
    validate_ansible_vault

    print_section "Environment Validation Complete"
}

# Execute validation if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    validate_environment
fi
