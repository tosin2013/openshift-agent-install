#!/bin/bash
# configure-haproxy-forwarder.sh - Deploy HAProxy using openshift-forwarder Ansible role
# This script configures HAProxy on the host to forward external traffic to cluster VIPs

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

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Script configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FORWARDER_REPO_URL="https://github.com/tosin2013/openshift-forwarder.git"
FORWARDER_DIR="${PROJECT_ROOT}/execution-environment/openshift-forwarder"

# Function to check prerequisites
check_prerequisites() {
    print_section "Checking Prerequisites"

    # Check for ansible-playbook
    if ! command -v ansible-playbook &>/dev/null; then
        print_error "ansible-playbook not found. Please install Ansible."
        echo "Install with: sudo dnf install -y ansible-core"
        exit 1
    fi
    print_status "Ansible is installed" 0

    # Check for ansible-galaxy
    if ! command -v ansible-galaxy &>/dev/null; then
        print_error "ansible-galaxy not found. Please install Ansible."
        exit 1
    fi
    print_status "ansible-galaxy is installed" 0

    # Check for yq
    if ! command -v yq &>/dev/null; then
        print_error "yq not found. Please install yq for YAML parsing."
        echo "Install with: sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && sudo chmod +x /usr/local/bin/yq"
        exit 1
    fi
    print_status "yq is installed" 0

    # Check for EXTERNAL_IP environment variable
    if [ -z "$EXTERNAL_IP" ]; then
        print_error "EXTERNAL_IP environment variable is not set"
        echo ""
        echo "Please set your host's external/public IP address:"
        echo "  export EXTERNAL_IP=\"203.0.113.10\""
        exit 1
    fi

    # Validate EXTERNAL_IP format (basic IP validation)
    if ! [[ $EXTERNAL_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        print_error "EXTERNAL_IP is not a valid IP address: ${EXTERNAL_IP}"
        exit 1
    fi
    print_status "EXTERNAL_IP is set: ${EXTERNAL_IP}" 0

    # Check if running as root or with sudo capability
    if [ "$EUID" -ne 0 ]; then
        if ! sudo -n true 2>/dev/null; then
            print_error "This script requires sudo privileges for HAProxy installation"
            echo "Please run with sudo or ensure passwordless sudo is configured"
            exit 1
        fi
    fi
    print_status "Root/sudo access available" 0
}

# Function to parse cluster configuration
parse_cluster_config() {
    local cluster_config=$1

    print_section "Parsing Cluster Configuration"

    if [ ! -f "$cluster_config" ]; then
        print_error "Cluster configuration file not found: ${cluster_config}"
        exit 1
    fi

    print_info "Reading: ${cluster_config}"

    # Parse cluster.yml using yq
    CLUSTER_NAME=$(yq eval '.cluster_name' "$cluster_config")
    BASE_DOMAIN=$(yq eval '.base_domain' "$cluster_config")
    API_VIP=$(yq eval '.api_vips[0]' "$cluster_config")
    APP_VIP=$(yq eval '.app_vips[0]' "$cluster_config")

    # Validate required fields
    if [ "$CLUSTER_NAME" == "null" ] || [ -z "$CLUSTER_NAME" ]; then
        print_error "cluster_name not found in ${cluster_config}"
        exit 1
    fi

    if [ "$BASE_DOMAIN" == "null" ] || [ -z "$BASE_DOMAIN" ]; then
        print_error "base_domain not found in ${cluster_config}"
        exit 1
    fi

    if [ "$API_VIP" == "null" ] || [ -z "$API_VIP" ]; then
        print_error "api_vips[0] not found in ${cluster_config}"
        exit 1
    fi

    if [ "$APP_VIP" == "null" ] || [ -z "$APP_VIP" ]; then
        print_error "app_vips[0] not found in ${cluster_config}"
        exit 1
    fi

    print_info "Cluster: ${CLUSTER_NAME}.${BASE_DOMAIN}"
    print_info "API VIP: ${API_VIP}"
    print_info "App VIP: ${APP_VIP}"
    print_status "Configuration parsed successfully" 0
}

# Function to install openshift-forwarder role
install_forwarder_role() {
    print_section "Installing openshift-forwarder Role"

    # Create execution-environment directory if it doesn't exist
    mkdir -p "${PROJECT_ROOT}/execution-environment"

    # Clone or update openshift-forwarder repository
    if [ -d "$FORWARDER_DIR" ]; then
        print_info "Updating existing openshift-forwarder repository..."
        cd "$FORWARDER_DIR"
        git pull || print_info "Failed to update, using existing version"
        cd "$PROJECT_ROOT"
    else
        print_info "Cloning openshift-forwarder repository..."
        git clone "$FORWARDER_REPO_URL" "$FORWARDER_DIR" || {
            print_error "Failed to clone openshift-forwarder repository"
            exit 1
        }
    fi

    print_status "openshift-forwarder role available" 0
}

# Function to generate Ansible inventory
generate_inventory() {
    print_section "Generating Ansible Inventory"

    INVENTORY_FILE="${PROJECT_ROOT}/execution-environment/haproxy-inventory.ini"

    cat > "$INVENTORY_FILE" << EOF
[openshift_forwarder]
localhost ansible_connection=local

[openshift_forwarder:vars]
external_ip=${EXTERNAL_IP}
api_vip=${API_VIP}
app_vip=${APP_VIP}
cluster_name=${CLUSTER_NAME}
base_domain=${BASE_DOMAIN}
EOF

    print_info "Inventory created: ${INVENTORY_FILE}"
    print_status "Inventory generated successfully" 0
}

# Function to generate Ansible playbook
generate_playbook() {
    print_section "Generating Ansible Playbook"

    PLAYBOOK_FILE="${PROJECT_ROOT}/execution-environment/configure-haproxy.yml"

    cat > "$PLAYBOOK_FILE" << 'EOF'
---
- name: Configure HAProxy for OpenShift External Access
  hosts: openshift_forwarder
  become: yes
  vars:
    haproxy_frontend_ip: "{{ external_ip }}"
    haproxy_api_backend: "{{ api_vip }}"
    haproxy_apps_backend: "{{ app_vip }}"
  tasks:
    - name: Install HAProxy
      package:
        name: haproxy
        state: present

    - name: Configure firewall for HAProxy
      firewalld:
        port: "{{ item }}"
        permanent: yes
        state: enabled
        immediate: yes
      loop:
        - 6443/tcp
        - 22623/tcp
        - 80/tcp
        - 443/tcp
      when: ansible_facts.services['firewalld.service'] is defined
      ignore_errors: yes

    - name: Create HAProxy configuration
      template:
        dest: /etc/haproxy/haproxy.cfg
        mode: '0644'
        content: |
          global
              log         127.0.0.1 local2
              chroot      /var/lib/haproxy
              pidfile     /var/run/haproxy.pid
              maxconn     4000
              user        haproxy
              group       haproxy
              daemon
              stats socket /var/lib/haproxy/stats

          defaults
              mode                    http
              log                     global
              option                  httplog
              option                  dontlognull
              option                  http-server-close
              option forwardfor       except 127.0.0.0/8
              option                  redispatch
              retries                 3
              timeout http-request    10s
              timeout queue           1m
              timeout connect         10s
              timeout client          1m
              timeout server          1m
              timeout http-keep-alive 10s
              timeout check           10s
              maxconn                 3000

          # API Server (6443)
          frontend api-server
              bind {{ haproxy_frontend_ip }}:6443
              mode tcp
              option tcplog
              default_backend api-server-backend

          backend api-server-backend
              mode tcp
              balance roundrobin
              server api {{ haproxy_api_backend }}:6443 check

          # Machine Config Server (22623)
          frontend machine-config-server
              bind {{ haproxy_frontend_ip }}:22623
              mode tcp
              option tcplog
              default_backend machine-config-server-backend

          backend machine-config-server-backend
              mode tcp
              balance roundrobin
              server mcs {{ haproxy_api_backend }}:22623 check

          # HTTP Ingress (80)
          frontend http-ingress
              bind {{ haproxy_frontend_ip }}:80
              mode tcp
              option tcplog
              default_backend http-ingress-backend

          backend http-ingress-backend
              mode tcp
              balance roundrobin
              server ingress-http {{ haproxy_apps_backend }}:80 check

          # HTTPS Ingress (443)
          frontend https-ingress
              bind {{ haproxy_frontend_ip }}:443
              mode tcp
              option tcplog
              default_backend https-ingress-backend

          backend https-ingress-backend
              mode tcp
              balance roundrobin
              server ingress-https {{ haproxy_apps_backend }}:443 check

    - name: Enable and start HAProxy
      systemd:
        name: haproxy
        enabled: yes
        state: restarted

    - name: Verify HAProxy is running
      systemd:
        name: haproxy
        state: started
      register: haproxy_status

    - name: Display HAProxy status
      debug:
        msg: "HAProxy is {{ haproxy_status.status.ActiveState }}"
EOF

    print_info "Playbook created: ${PLAYBOOK_FILE}"
    print_status "Playbook generated successfully" 0
}

# Function to run Ansible playbook
configure_haproxy() {
    print_section "Configuring HAProxy"

    print_info "Running Ansible playbook to configure HAProxy..."

    cd "$PROJECT_ROOT"

    # Run the playbook
    ansible-playbook \
        -i "${PROJECT_ROOT}/execution-environment/haproxy-inventory.ini" \
        "${PROJECT_ROOT}/execution-environment/configure-haproxy.yml" \
        || {
            print_error "Failed to configure HAProxy"
            exit 1
        }

    print_status "HAProxy configured successfully" 0
}

# Function to verify HAProxy configuration
verify_haproxy() {
    print_section "Verifying HAProxy Configuration"

    # Check if HAProxy service is running
    if sudo systemctl is-active --quiet haproxy; then
        print_status "HAProxy service is running" 0
    else
        print_error "HAProxy service is not running"
        sudo systemctl status haproxy --no-pager || true
        exit 1
    fi

    # Check if HAProxy is listening on expected ports
    print_info "Checking HAProxy listening ports..."
    for port in 6443 22623 80 443; do
        if sudo netstat -tlnp 2>/dev/null | grep -q ":${port}.*haproxy" || \
           sudo ss -tlnp 2>/dev/null | grep -q ":${port}.*haproxy"; then
            print_status "HAProxy listening on port ${port}" 0
        else
            print_error "HAProxy not listening on port ${port}"
        fi
    done

    print_section "HAProxy Configuration Summary"
    echo ""
    echo "External IP: ${EXTERNAL_IP}"
    echo "API VIP (backend): ${API_VIP}"
    echo "App VIP (backend): ${APP_VIP}"
    echo ""
    echo "Traffic forwarding configured:"
    echo "  ${EXTERNAL_IP}:6443 → ${API_VIP}:6443 (API Server)"
    echo "  ${EXTERNAL_IP}:22623 → ${API_VIP}:22623 (Machine Config)"
    echo "  ${EXTERNAL_IP}:80 → ${APP_VIP}:80 (HTTP Ingress)"
    echo "  ${EXTERNAL_IP}:443 → ${APP_VIP}:443 (HTTPS Ingress)"
    echo ""
}

# Usage function
usage() {
    cat << EOF
Usage: $0 <cluster_config.yml>

Configure HAProxy on the host to forward external traffic to OpenShift cluster VIPs.

Prerequisites:
  - Ansible installed (ansible-playbook, ansible-galaxy)
  - yq installed for YAML parsing
  - EXTERNAL_IP environment variable set to host's public IP
  - Root/sudo privileges

Example:
  export EXTERNAL_IP="203.0.113.10"
  $0 examples/sno-4.20-standard/cluster.yml

This will:
  1. Install HAProxy on the host
  2. Configure traffic forwarding from EXTERNAL_IP to cluster VIPs
  3. Enable and start HAProxy service
  4. Configure firewall rules (if firewalld is running)

For more information, see llm.txt "Phase 6.5: External Access Configuration"
EOF
}

# Main script execution
main() {
    # Check for help flag
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
        usage
        exit 0
    fi

    # Check for cluster config argument
    if [ -z "$1" ]; then
        print_error "No cluster configuration file specified"
        echo ""
        usage
        exit 1
    fi

    local cluster_config="$1"

    # Execute workflow
    check_prerequisites
    parse_cluster_config "$cluster_config"
    install_forwarder_role
    generate_inventory
    generate_playbook
    configure_haproxy
    verify_haproxy

    print_section "HAProxy Forwarder Configuration Complete"
    echo -e "${GREEN}External access forwarding is now configured${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Configure Route53 DNS to point to ${EXTERNAL_IP}"
    echo "  2. Obtain Let's Encrypt certificates"
    echo ""
    echo "Or run the orchestration script:"
    echo "  ./hack/configure-external-access.sh ${cluster_config}"
}

# Run main function
main "$@"
