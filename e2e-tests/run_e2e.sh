#!/bin/bash

# This script runs end-to-end tests targeting OpenShift 4.17

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

function check_freeipa() {
    export vm_name="freeipa"
    export ip_address=$(sudo kcli info vm "$vm_name" "$vm_name" | grep ip: | awk '{print $2}' | head -1)
    if [ -z "$ip_address" ]; then
        echo "Error: FreeIPA VM IP address not found"
        exit 1
    fi
    echo "FreeIPA IP address: $ip_address"
}
# --- Core Test Functions ---

create_test_iso() {
    print_section "Creating Test ISO"
    local config_dir="$1"

    # Call hack/create-iso.sh with the provided site config
    if [ -z "$config_dir" ]; then
        echo "No site config folder specified"
        exit 1
    fi

    # Prepend examples/ if the path doesn't start with it or site-config/
    if [[ ! "$config_dir" =~ ^(examples|site-config)/ ]]; then
        config_dir="$config_dir"
    fi

    # updating dns server in the config
    check_freeipa
    yq e -i '.dns_servers[0] = "'${ip_address}'"' "examples/${config_dir}/cluster.yml" || print_status "Failed to update dns server in cluster.yml" 1
    yq e -i 'del(.dns_servers[1])' "examples/${config_dir}/cluster.yml" || print_status "Failed to delete dns server in cluster.yml" 1

    ./hack/create-iso.sh "$config_dir" || print_status "Failed to create ISO" 1

    print_status "Test ISO created successfully" 0
    echo "Config dir used: $config_dir"
}

deploy_test_vms() {
    print_section "Deploying Test VMs"
    local yaml_file="$1"
    local cluster_yaml="${yaml_file%/*}/cluster.yml"

    # Call hack/deploy-on-kvm.sh with the provided nodes.yml
    if [ -z "$yaml_file" ]; then
        echo "No nodes.yml file specified"
        exit 1
    fi

    # Extract and export CLUSTER_NAME from cluster.yml
    export CLUSTER_NAME=$(grep "cluster_name" "$cluster_yaml" | awk '{print $2}' | tr -d '"')
    if [ -z "$CLUSTER_NAME" ]; then
        print_status "Failed to extract cluster_name from $cluster_yaml" 1
        exit 1
    fi
    echo "Using cluster name: $CLUSTER_NAME"

    ./hack/deploy-on-kvm.sh "$yaml_file" || print_status "Failed to deploy VMs" 1

    print_status "Test VMs deployed successfully" 0
}

monitor_test_vms() {
    print_section "Monitoring Test VMs"
    local yaml_file="$1"

    # Call hack/watch-and-reboot-kvm-vms.sh to monitor the VMs
    if [ -z "$yaml_file" ]; then
        echo "No nodes.yml file specified"
        exit 1
    fi

    ./hack/watch-and-reboot-kvm-vms.sh "$yaml_file" || print_status "Failed to monitor VMs" 1

    print_status "Test VMs monitored successfully" 0
}

cleanup_test_env() {
    print_section "Cleaning up Test Environment"
    local yaml_file="$1"
    local cluster_yaml="${yaml_file%/*}/cluster.yml"

    # Call hack/destroy-on-kvm.sh to clean up the environment
    if [ -z "$yaml_file" ]; then
        echo "No nodes.yml file specified"
        exit 1
    fi

    # Extract and export CLUSTER_NAME from cluster.yml if not already set
    if [ -z "$CLUSTER_NAME" ]; then
        export CLUSTER_NAME=$(grep "cluster_name" "$cluster_yaml" | awk '{print $2}' | tr -d '"')
        if [ -z "$CLUSTER_NAME" ]; then
            print_status "Failed to extract cluster_name from $cluster_yaml" 1
            exit 1
        fi
        echo "Using cluster name: $CLUSTER_NAME"
    fi

    ./hack/destroy-on-kvm.sh "$yaml_file" || print_status "Failed to clean up environment" 1

    print_status "Test environment cleaned up successfully" 0
}

# --- Main Test Flow ---

print_section "Running End-to-End Tests"

# Check if site config argument is provided
if [ $# -lt 1 ]; then
    echo "Usage: $0 <site_config_dir>"
    exit 1
fi

site_config="$1"
# Prepend examples/ if the path doesn't start with it or site-config/
if [[ ! "$site_config" =~ ^(examples|site-config)/ ]]; then
    nodes_yaml="examples/${site_config}/nodes.yml"
else
    nodes_yaml="${site_config}/nodes.yml"
fi

# Verify nodes.yml exists
if [ ! -f "$nodes_yaml" ]; then
    echo "Error: nodes.yml not found at $nodes_yaml"
    exit 1
fi

# Verify cluster.yml exists
cluster_yaml="${nodes_yaml%/*}/cluster.yml"
if [ ! -f "$cluster_yaml" ]; then
    echo "Error: cluster.yml not found at $cluster_yaml"
    exit 1
fi

# 1. Environment Validation
source e2e-tests/validate_env.sh
validate_environment # Assuming validate_env.sh defines this function

export GENERATED_ASSET_PATH="/home/lab-user/generated_assets"
# 2. ISO Creation
create_test_iso "$site_config"

# 3. VM Deployment
deploy_test_vms "$nodes_yaml"

# 4. Installation Monitoring
monitor_test_vms "$nodes_yaml"

# 5. Test Execution (add actual test commands here)
print_section "Executing Tests"
# Placeholder for test commands
echo "Implement actual test commands here"
print_status "Tests executed successfully (placeholder)" 0

# 6. Environment Cleanup
cleanup_test_env "$nodes_yaml"

print_section "End-to-End Tests Complete"
