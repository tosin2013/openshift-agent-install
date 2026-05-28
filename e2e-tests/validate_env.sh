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
        # Validate oc version (informational only, don't fail on newer versions)
        rhel_version=$(rpm -E %{rhel})
        if [ "$rhel_version" -eq 8 ]; then
            min_version="4.15"
        else
            min_version="4.18"
        fi

        # Extract major.minor version from oc output
        oc_version=$(oc version 2>&1 | grep "Client Version" | awk '{print $3}' | cut -d. -f1,2)

        if [ -n "$oc_version" ]; then
            print_status "oc version is $oc_version (minimum: $min_version)" 0
        else
            echo -e "${YELLOW}⚠ Could not determine oc version${NC}"
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

    # Check FreeIPA VM (optional - legacy DNS approach)
    if command_exists kcli; then
        if sudo kcli list vm 2>/dev/null | grep -q "freeipa"; then
            print_status "FreeIPA VM exists" 0

            # Check FreeIPA VM IP
            if ip_address=$(sudo kcli info vm freeipa freeipa 2>/dev/null | grep ip: | awk '{print $2}' | head -1) && [ -n "$ip_address" ]; then
                print_status "FreeIPA VM has IP address: $ip_address" 0
            else
                echo -e "${YELLOW}⚠ FreeIPA VM IP address not found${NC}"
            fi
        else
            echo -e "${YELLOW}⚠ FreeIPA VM not found (optional - using dnsmasq instead)${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ kcli not found - skipping FreeIPA check (optional)${NC}"
    fi
}

# --- Registry Auth Validation ---
validate_registry_auth() {
    print_section "Validating Registry Authentication"

    # Check pull secret in common locations
    PULL_SECRET_FOUND=false
    for path in "/home/lab-user/pullsecret.json" "$HOME/pullsecret.json" "$HOME/ocp-install-pull-secret.json"; do
        if [ -f "$path" ]; then
            print_status "Pull secret exists at $path" 0
            PULL_SECRET_FOUND=true
            break
        fi
    done

    if [ "$PULL_SECRET_FOUND" = false ]; then
        echo -e "${YELLOW}⚠ Pull secret not found in common locations${NC}"
        echo -e "${BLUE}Info: Pull secret required for deployment. Download from https://console.redhat.com/openshift/downloads${NC}"
    fi

    # Check docker config
    if [ -f "$HOME/.docker/config.json" ]; then
        print_status "Docker config exists" 0
    else
        echo -e "${YELLOW}⚠ Docker config not found (optional)${NC}"
    fi
}

# --- Ansible Vault Validation ---
validate_ansible_vault() {
    print_section "Validating Ansible Vault Setup"

    # Check vault password file (optional)
    VAULT_FOUND=false
    for path in "/home/lab-user/.vault_password" "$HOME/.vault_password"; do
        if [ -f "$path" ]; then
            # Verify permissions
            PERMS=$(stat -c "%a" "$path")
            if [ "$PERMS" = "600" ]; then
                print_status "Vault password file exists with correct permissions" 0
            else
                echo -e "${YELLOW}⚠ Vault password file has incorrect permissions (should be 600)${NC}"
            fi
            VAULT_FOUND=true
            break
        fi
    done

    if [ "$VAULT_FOUND" = false ]; then
        echo -e "${YELLOW}⚠ Vault password file not found (optional - only needed for encrypted vars)${NC}"
    fi

    # Check vault.yml (optional)
    if [ -f "vault.yml" ]; then
        # Verify if file is encrypted
        if grep -q "ANSIBLE_VAULT" "vault.yml"; then
            print_status "vault.yml exists and is encrypted" 0
        else
            echo -e "${YELLOW}⚠ vault.yml exists but is not encrypted${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ vault.yml not found (optional)${NC}"
    fi
}

# --- Operating System Validation ---
validate_os() {
    print_section "Validating Operating System"

    # Extract RHEL major and minor version
    RHEL_VERSION=$(rpm -E %{rhel})
    RHEL_MINOR=$(grep -oP 'release \K[0-9]+\.[0-9]+' /etc/redhat-release | cut -d. -f2)

    # Require RHEL >= 9.5, warn on RHEL 10+
    if [[ "$RHEL_VERSION" -lt 9 ]] || [[ "$RHEL_VERSION" -eq 9 && "$RHEL_MINOR" -lt 5 ]]; then
        print_status "Operating System requires RHEL >= 9.5 (found: $(cat /etc/redhat-release))" 1
    elif [[ "$RHEL_VERSION" -ge 10 ]]; then
        echo -e "${YELLOW}⚠ RHEL 10 support is experimental${NC}"
        print_status "Operating System is RHEL ${RHEL_VERSION}.${RHEL_MINOR} (experimental)" 0
    else
        print_status "Operating System is RHEL ${RHEL_VERSION}.${RHEL_MINOR}" 0
    fi
}

# --- Main Validation ---
validate_dns_infrastructure() {
    print_section "Validating DNS Infrastructure"

    # Check if dnsmasq is installed
    if ! rpm -q dnsmasq &>/dev/null; then
        print_status "dnsmasq package is installed" 1
        return
    fi
    print_status "dnsmasq package is installed" 0

    # Check if dnsmasq service is running
    if ! sudo systemctl is-active --quiet dnsmasq; then
        print_status "dnsmasq service is running" 1
        echo -e "${RED}ERROR: dnsmasq service is not running${NC}"
        echo -e "${BLUE}Fix: sudo systemctl start dnsmasq${NC}"
        return
    fi
    print_status "dnsmasq service is running" 0

    # Check if dnsmasq service is enabled
    if sudo systemctl is-enabled --quiet dnsmasq; then
        print_status "dnsmasq service is enabled (will start on boot)" 0
    else
        echo -e "${YELLOW}⚠ dnsmasq service is not enabled - it won't start on reboot${NC}"
        echo -e "${BLUE}Fix: sudo systemctl enable dnsmasq${NC}"
    fi

    # Test localhost DNS resolution
    print_info "Testing localhost DNS resolution..."
    if dig @localhost localhost +short | grep -q "127.0.0.1"; then
        print_status "Localhost DNS resolution works" 0
    else
        print_status "Localhost DNS resolution works" 1
        echo -e "${RED}ERROR: DNS server on localhost not responding${NC}"
        echo -e "${BLUE}Fix: sudo systemctl restart dnsmasq${NC}"
        return
    fi

    # Check if OpenShift DNS config exists
    if [ -f /etc/dnsmasq.d/openshift.conf ]; then
        print_status "OpenShift DNS configuration file exists" 0

        # Count configured clusters
        local cluster_count=$(sudo grep -c "^address=" /etc/dnsmasq.d/openshift.conf 2>/dev/null || echo "0")
        if [ "$cluster_count" -gt 0 ]; then
            print_info "Found $cluster_count DNS entry(ies) configured"
        else
            echo -e "${YELLOW}⚠ No OpenShift DNS entries configured yet${NC}"
            echo -e "${BLUE}Info: DNS entries will be added during deployment${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ OpenShift DNS configuration file not found${NC}"
        echo -e "${BLUE}Info: Run ./hack/setup-dnsmasq.sh to initialize${NC}"
    fi
}

validate_vyos_router() {
    print_section "Validating VyOS Router Infrastructure"

    # Check if libvirt is running
    if ! sudo systemctl is-active --quiet libvirtd; then
        echo -e "${YELLOW}⚠ libvirtd service is not running - cannot check VyOS networks${NC}"
        echo -e "${BLUE}Fix: sudo systemctl start libvirtd${NC}"
        return
    fi

    # Check for VyOS networks (1924-1928)
    print_info "Checking for VyOS VLAN networks..."
    local vyos_networks=(1924 1925 1926 1927 1928)
    local network_count=0

    for net in "${vyos_networks[@]}"; do
        if sudo virsh net-list --all | grep -qw "$net"; then
            if sudo virsh net-list | grep -w "$net" | grep -q "active"; then
                ((network_count++))
                print_status "Network $net is active" 0
            else
                echo -e "${YELLOW}⚠ Network $net exists but is not active${NC}"
                echo -e "${BLUE}Fix: sudo virsh net-start $net${NC}"
            fi
        fi
    done

    if [ "$network_count" -eq 5 ]; then
        print_status "All 5 VyOS VLAN networks (1924-1928) are active" 0
    elif [ "$network_count" -gt 0 ]; then
        echo -e "${YELLOW}⚠ Only $network_count/5 VyOS networks are active${NC}"
        echo -e "${RED}ERROR: VyOS router infrastructure is incomplete${NC}"
        echo -e "${BLUE}Fix: Deploy/reconfigure VyOS router with all VLAN networks${NC}"
        exit 1
    else
        echo -e "${RED}ERROR: No VyOS VLAN networks found${NC}"
        echo -e "${BLUE}Fix: Deploy VyOS router with ./hack/vyos-router.sh${NC}"
        exit 1
    fi

    # Test VyOS router connectivity
    print_info "Testing VyOS router connectivity..."
    if ping -c 1 -W 2 192.168.122.2 &>/dev/null; then
        print_status "VyOS router is reachable (192.168.122.2)" 0
    else
        echo -e "${YELLOW}⚠ VyOS router not reachable at 192.168.122.2${NC}"
        echo -e "${BLUE}Info: Verify VyOS VM is running${NC}"
    fi

    # Check VLAN gateway connectivity
    print_info "Testing VLAN gateway connectivity..."
    local vlan_gateways=(192.168.50.1 192.168.51.1 192.168.52.1 192.168.58.1)
    local gateway_count=0

    for gw in "${vlan_gateways[@]}"; do
        if ping -c 1 -W 1 "$gw" &>/dev/null 2>&1; then
            ((gateway_count++))
        fi
    done

    if [ "$gateway_count" -gt 0 ]; then
        print_status "VyOS VLAN gateways are reachable ($gateway_count/4 tested)" 0
    else
        echo -e "${YELLOW}⚠ VyOS VLAN gateways not reachable${NC}"
        echo -e "${BLUE}Info: This may be normal if VLANs are not yet configured${NC}"
    fi
}

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
    validate_dns_infrastructure
    validate_vyos_router

    print_section "Environment Validation Complete"
    echo -e "${GREEN}✅ All critical prerequisites validated${NC}"
    echo ""
    echo -e "${BLUE}IMPORTANT: Before deploying OpenShift clusters:${NC}"
    echo "1. Ensure VyOS router is configured with networks 1924-1928 active"
    echo "2. Ensure DNS is configured AND verified with ./hack/verify-dns-resolution.sh"
    echo ""
}

# Execute validation if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    validate_environment
fi
