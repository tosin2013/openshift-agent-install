#!/bin/bash
# configure-dnsmasq-entries.sh - Manage DNS entries for OpenShift clusters
# This script reads cluster.yml and adds/removes DNS entries to dnsmasq

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
print_status() {
    if [ $2 -eq 0 ]; then
        echo -e "${GREEN}✓ $1${NC}"
    else
        echo -e "${RED}✗ $1${NC}"
        exit 1
    fi
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run this script with sudo privileges${NC}"
    exit 1
fi

# Configuration
DNSMASQ_CONF_DIR="/etc/dnsmasq.d"
OPENSHIFT_DNSMASQ_CONF="${DNSMASQ_CONF_DIR}/openshift.conf"

# Check if dnsmasq is installed
if ! rpm -q dnsmasq &>/dev/null; then
    print_error "dnsmasq is not installed. Please run ./hack/setup-dnsmasq.sh first"
    exit 1
fi

# Check if configuration file exists
if [ ! -f "$OPENSHIFT_DNSMASQ_CONF" ]; then
    print_error "dnsmasq OpenShift configuration not found at ${OPENSHIFT_DNSMASQ_CONF}"
    print_error "Please run ./hack/setup-dnsmasq.sh first"
    exit 1
fi

# Function to check if yq is installed
check_yq() {
    if ! command -v yq &>/dev/null; then
        print_error "yq is not installed. Please install yq first."
        exit 1
    fi
}

# Function to add DNS entries for a cluster
add_cluster_dns_entries() {
    local cluster_config=$1

    if [ ! -f "$cluster_config" ]; then
        print_error "Cluster configuration file not found: ${cluster_config}"
        exit 1
    fi

    print_info "Reading cluster configuration from: ${cluster_config}"

    # Parse cluster.yml using yq
    cluster_name=$(yq eval '.cluster_name' "$cluster_config")
    base_domain=$(yq eval '.base_domain' "$cluster_config")
    api_vip=$(yq eval '.api_vips[0]' "$cluster_config")
    app_vip=$(yq eval '.app_vips[0]' "$cluster_config")

    # Validate required fields
    if [ "$cluster_name" == "null" ] || [ -z "$cluster_name" ]; then
        print_error "cluster_name not found in ${cluster_config}"
        exit 1
    fi

    if [ "$base_domain" == "null" ] || [ -z "$base_domain" ]; then
        print_error "base_domain not found in ${cluster_config}"
        exit 1
    fi

    if [ "$api_vip" == "null" ] || [ -z "$api_vip" ]; then
        print_error "api_vips[0] not found in ${cluster_config}"
        exit 1
    fi

    if [ "$app_vip" == "null" ] || [ -z "$app_vip" ]; then
        print_error "app_vips[0] not found in ${cluster_config}"
        exit 1
    fi

    print_info "Cluster: ${cluster_name}.${base_domain}"
    print_info "API VIP: ${api_vip}"
    print_info "App VIP: ${app_vip}"

    # Remove existing entries for this cluster (if any)
    remove_cluster_dns_entries "$cluster_name" "$base_domain"

    # Add DNS entries to dnsmasq configuration
    print_info "Adding DNS entries to ${OPENSHIFT_DNSMASQ_CONF}..."

    cat >> "$OPENSHIFT_DNSMASQ_CONF" << EOF

# DNS entries for cluster: ${cluster_name}.${base_domain}
# Added on: $(date)
address=/api.${cluster_name}.${base_domain}/${api_vip}
address=/api-int.${cluster_name}.${base_domain}/${api_vip}
address=/.apps.${cluster_name}.${base_domain}/${app_vip}

EOF

    print_status "DNS entries added successfully" 0

    # Reload dnsmasq
    print_info "Reloading dnsmasq..."
    systemctl reload dnsmasq

    if [ $? -eq 0 ]; then
        print_status "dnsmasq reloaded successfully" 0
    else
        print_status "Failed to reload dnsmasq" 1
    fi

    # Display added entries
    echo ""
    echo -e "${GREEN}DNS entries added:${NC}"
    echo "  api.${cluster_name}.${base_domain} -> ${api_vip}"
    echo "  api-int.${cluster_name}.${base_domain} -> ${api_vip}"
    echo "  *.apps.${cluster_name}.${base_domain} -> ${app_vip}"
    echo ""
    echo "Test DNS resolution with:"
    echo "  dig @localhost api.${cluster_name}.${base_domain}"
    echo "  dig @localhost test.apps.${cluster_name}.${base_domain}"
}

# Function to remove DNS entries for a cluster
remove_cluster_dns_entries() {
    local cluster_name=$1
    local base_domain=$2

    print_info "Removing existing DNS entries for ${cluster_name}.${base_domain}..."

    # Create a temporary file
    temp_file=$(mktemp)

    # Remove lines related to this cluster
    # This removes the comment block and the three address lines
    sed "/# DNS entries for cluster: ${cluster_name}\.${base_domain}/,/^$/d" "$OPENSHIFT_DNSMASQ_CONF" > "$temp_file"

    # Replace original file
    mv "$temp_file" "$OPENSHIFT_DNSMASQ_CONF"

    print_status "Existing entries removed (if any)" 0
}

# Function to list all DNS entries
list_dns_entries() {
    print_info "Current DNS entries in ${OPENSHIFT_DNSMASQ_CONF}:"
    echo ""
    grep -E "^address=/" "$OPENSHIFT_DNSMASQ_CONF" || echo "No DNS entries found"
}

# Main script logic
case "${1:-}" in
    add)
        if [ -z "$2" ]; then
            print_error "Usage: $0 add <cluster_config.yml>"
            exit 1
        fi
        check_yq
        add_cluster_dns_entries "$2"
        ;;
    remove)
        if [ -z "$2" ] || [ -z "$3" ]; then
            print_error "Usage: $0 remove <cluster_name> <base_domain>"
            exit 1
        fi
        remove_cluster_dns_entries "$2" "$3"
        systemctl reload dnsmasq
        print_status "DNS entries removed and dnsmasq reloaded" 0
        ;;
    list)
        list_dns_entries
        ;;
    *)
        # Default action: add entries from cluster config
        if [ -z "$1" ]; then
            echo "Usage: $0 {add|remove|list} [arguments]"
            echo ""
            echo "Commands:"
            echo "  add <cluster_config.yml>           Add DNS entries from cluster config"
            echo "  remove <cluster_name> <base_domain> Remove DNS entries for a cluster"
            echo "  list                                List all current DNS entries"
            echo ""
            echo "Shortcut: $0 <cluster_config.yml>    Same as 'add' command"
            exit 1
        fi
        # Shortcut: if first arg is a file, treat it as 'add'
        if [ -f "$1" ]; then
            check_yq
            add_cluster_dns_entries "$1"
        else
            print_error "File not found: $1"
            exit 1
        fi
        ;;
esac
