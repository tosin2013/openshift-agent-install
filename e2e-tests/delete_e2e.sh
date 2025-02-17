#!/bin/bash

#  /opt/freeipa-workshop-deployer/1_kcli/destroy.sh 
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

cleanup_vyos_router() {
    print_section "Cleaning up VyOS Router"
    
    # Call the vyos-router.sh script with delete action
    export ACTION="delete"
    if [ -f hack/vyos-router.sh ]; then
        bash hack/vyos-router.sh
        print_status "VyOS router cleanup completed" $?
    else
        print_status "VyOS router script not found" 1
    fi
}

cleanup_test_env() {
    print_section "Cleaning up Test Environment"

    # Get site config directory
    SITE_CONFIG_DIR="${SITE_CONFIG_DIR:-examples}"

    # Check if a site config folder was specified
    if [ -z "$1" ]; then
        print_status "No site config folder specified" 1
        return 1
    fi

    # Check that the cluster config exists
    if [ ! -d "${SITE_CONFIG_DIR}/$1" ]; then
        print_info "No site config folder found for $1"
        print_info "Found these site config folders:"
        ls -1 "${SITE_CONFIG_DIR}"
        print_status "Invalid site config" 1
        return 1
    fi

    # Get cluster name from config
    export CLUSTER_NAME=$(grep "cluster_name" "${SITE_CONFIG_DIR}/${1}/cluster.yml" | awk '{print $2}' | tr -d '"')
    yaml_file="${SITE_CONFIG_DIR}/${1}/nodes.yml"

    # Call cleanup function from run_e2e.sh
    source e2e-tests/run_e2e.sh
    cleanup_test_env "$yaml_file"

    # Clean up generated assets
    GENERATED_ASSET_PATH="${GENERATED_ASSET_PATH:-"${HOME}/generated_assets"}"
    if [ -d "${GENERATED_ASSET_PATH}/${CLUSTER_NAME}" ]; then
        print_info "Cleaning up generated assets"
        sudo rm -rf "${GENERATED_ASSET_PATH}/${CLUSTER_NAME}"
        print_status "Generated assets cleanup completed" $?
    fi
}

cleanup_networks() {
    print_section "Cleaning up Virtual Networks"
    
    # Clean up the test networks
    for network in 1924 1925 1926 1927 1928; do
        if sudo virsh net-list --all | grep -q "^$network"; then
            print_info "Destroying network $network"
            sudo virsh net-destroy "$network" || true
            sudo virsh net-undefine "$network" || true
        fi
    done
    print_status "Network cleanup completed" 0
}

# --- Main Cleanup Flow ---

print_section "Starting E2E Environment Cleanup"

# 1. Cleanup VyOS Router
cleanup_vyos_router

# 2. Cleanup Test Environment
cleanup_test_env "$1"

# 3. Cleanup Networks
cleanup_networks

print_section "E2E Environment Cleanup Complete"
