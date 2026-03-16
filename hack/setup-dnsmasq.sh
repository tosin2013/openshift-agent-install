#!/bin/bash
# setup-dnsmasq.sh - Install and configure dnsmasq for OpenShift DNS resolution
# This replaces the heavyweight FreeIPA solution with a lightweight DNS-only approach

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

print_section() {
    echo -e "\n${YELLOW}$1${NC}"
    echo "================================"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run this script with sudo privileges${NC}"
    exit 1
fi

# Detect the actual user (works even with sudo)
if [ -n "$SUDO_USER" ]; then
    ACTUAL_USER="$SUDO_USER"
    ACTUAL_USER_HOME=$(eval echo ~$SUDO_USER)
else
    ACTUAL_USER="$USER"
    ACTUAL_USER_HOME="$HOME"
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
DNSMASQ_CONF_DIR="/etc/dnsmasq.d"
OPENSHIFT_DNSMASQ_CONF="${DNSMASQ_CONF_DIR}/openshift.conf"

print_section "Installing dnsmasq"

# Install dnsmasq if not already installed
if ! rpm -q dnsmasq &>/dev/null; then
    print_info "Installing dnsmasq package..."
    dnf install -y dnsmasq
    print_status "dnsmasq installed successfully" 0
else
    print_status "dnsmasq is already installed" 0
fi

print_section "Configuring dnsmasq"

# Create dnsmasq.d directory if it doesn't exist
mkdir -p "$DNSMASQ_CONF_DIR"

# Create initial OpenShift DNS configuration
print_info "Creating OpenShift DNS configuration at ${OPENSHIFT_DNSMASQ_CONF}..."
cat > "$OPENSHIFT_DNSMASQ_CONF" << 'EOF'
# OpenShift DNS Configuration
# This file is managed by openshift-agent-install
# DNS entries are added dynamically by configure-dnsmasq-entries.sh

# Listen on all interfaces
bind-interfaces
listen-address=127.0.0.1

# Upstream DNS servers (can be customized)
# server=8.8.8.8
# server=1.1.1.1

# Don't read /etc/resolv.conf
no-resolv

# Enable logging for debugging (comment out for production)
log-queries
log-facility=/var/log/dnsmasq.log

# Cache size
cache-size=1000

# OpenShift DNS entries will be added below
# Format: address=/hostname/IP

EOF

print_status "Initial dnsmasq configuration created" 0

# Configure firewall if firewalld is running
if systemctl is-active --quiet firewalld; then
    print_info "Configuring firewall for DNS..."
    firewall-cmd --permanent --add-service=dns 2>/dev/null || true
    firewall-cmd --reload 2>/dev/null || true
    print_status "Firewall configured for DNS" 0
fi

print_section "Enabling and starting dnsmasq"

# Enable and start dnsmasq
systemctl enable dnsmasq
systemctl restart dnsmasq

# Check if dnsmasq started successfully
if systemctl is-active --quiet dnsmasq; then
    print_status "dnsmasq is running" 0
else
    print_status "Failed to start dnsmasq" 1
fi

# Display status
print_section "dnsmasq Status"
systemctl status dnsmasq --no-pager -l || true

print_section "Setup Complete"
echo -e "${GREEN}dnsmasq has been installed and configured successfully${NC}"
echo ""
echo "Next steps:"
echo "1. Run './hack/configure-dnsmasq-entries.sh <cluster_config.yml>' to add DNS entries"
echo "2. Test DNS resolution: dig @localhost api.<cluster_name>.<base_domain>"
echo "3. Update your cluster configuration to use this DNS server"
echo ""
echo "Logs: /var/log/dnsmasq.log"
echo "Config: ${OPENSHIFT_DNSMASQ_CONF}"
