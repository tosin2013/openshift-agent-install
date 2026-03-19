#!/bin/bash
# configure-external-access.sh - Orchestrate complete external access setup
# This script configures HAProxy, Route53 DNS, and Let's Encrypt certificates

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
    echo -e "\n${YELLOW}═══════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}$1${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
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

# Auto-source .env file if it exists (for credentials)
if [ -f "${PROJECT_ROOT}/.env" ]; then
    print_info "Loading environment variables from .env file..."
    # shellcheck disable=SC1091
    source "${PROJECT_ROOT}/.env"
elif [ -f "${HOME}/.env" ]; then
    print_info "Loading environment variables from ~/.env file..."
    # shellcheck disable=SC1091
    source "${HOME}/.env"
fi

# Function to wait for DNS propagation
wait_for_dns_propagation() {
    local cluster_name=$1
    local base_domain=$2
    local expected_ip=$3
    local max_wait=180  # 3 minutes
    local check_interval=10
    local elapsed=0

    print_section "Waiting for DNS Propagation"

    print_info "Waiting for DNS records to propagate..."
    print_info "This typically takes 1-3 minutes"
    echo ""

    local api_hostname="api.${cluster_name}.${base_domain}"
    local apps_hostname="test.apps.${cluster_name}.${base_domain}"

    while [ $elapsed -lt $max_wait ]; do
        # Check API hostname
        API_RESOLVED=$(dig +short "$api_hostname" @8.8.8.8 2>/dev/null | head -n 1)

        # Check wildcard apps hostname
        APPS_RESOLVED=$(dig +short "$apps_hostname" @8.8.8.8 2>/dev/null | head -n 1)

        # Display current status
        echo -ne "\r${BLUE}ℹ Checking DNS... API: ${API_RESOLVED:-pending} | Apps: ${APPS_RESOLVED:-pending} | Elapsed: ${elapsed}s${NC}"

        # Check if both resolved correctly
        if [ "$API_RESOLVED" == "$expected_ip" ] && [ "$APPS_RESOLVED" == "$expected_ip" ]; then
            echo ""  # New line after status
            print_status "DNS propagation complete" 0
            print_info "api.${cluster_name}.${base_domain} → ${API_RESOLVED}"
            print_info "*.apps.${cluster_name}.${base_domain} → ${APPS_RESOLVED}"
            return 0
        fi

        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done

    echo ""  # New line after status
    print_error "DNS propagation timed out after ${max_wait} seconds"
    echo ""
    echo "Current resolution:"
    echo "  API: ${API_RESOLVED:-not resolved}"
    echo "  Apps: ${APPS_RESOLVED:-not resolved}"
    echo "  Expected: ${expected_ip}"
    echo ""
    echo "You can continue manually once DNS propagates:"
    echo "  ./hack/configure-letsencrypt-certs.sh"
    exit 1
}

# Function to display setup summary
display_setup_summary() {
    local cluster_config=$1

    print_section "External Access Configuration Summary"

    # Parse config to get cluster info
    if command -v yq &>/dev/null && [ -f "$cluster_config" ]; then
        CLUSTER_NAME=$(yq eval '.cluster_name' "$cluster_config" 2>/dev/null)
        BASE_DOMAIN=$(yq eval '.base_domain' "$cluster_config" 2>/dev/null)
        API_VIP=$(yq eval '.api_vips[0]' "$cluster_config" 2>/dev/null)
        APP_VIP=$(yq eval '.app_vips[0]' "$cluster_config" 2>/dev/null)
    fi

    echo ""
    echo -e "${GREEN}External access is now fully configured!${NC}"
    echo ""
    echo "Configuration:"
    echo "  External IP: ${EXTERNAL_IP}"
    echo "  Cluster: ${CLUSTER_NAME}.${BASE_DOMAIN}"
    echo "  API VIP (internal): ${API_VIP}"
    echo "  App VIP (internal): ${APP_VIP}"
    echo ""
    echo "Traffic flow:"
    echo "  Internet → Route53 DNS → ${EXTERNAL_IP} → HAProxy → Cluster VIPs"
    echo ""
    echo "Access points:"
    echo "  API: https://api.${CLUSTER_NAME}.${BASE_DOMAIN}:6443"
    echo "  Console: https://console-openshift-console.apps.${CLUSTER_NAME}.${BASE_DOMAIN}/"
    echo "  Apps: https://*.apps.${CLUSTER_NAME}.${BASE_DOMAIN}/"
    echo ""
    echo "Verification:"
    echo "  1. Test API access:"
    echo "     curl -k https://api.${CLUSTER_NAME}.${BASE_DOMAIN}:6443/version"
    echo ""
    echo "  2. Access web console with Let's Encrypt certificate:"
    echo "     https://console-openshift-console.apps.${CLUSTER_NAME}.${BASE_DOMAIN}/"
    echo ""
    echo "  3. Check HAProxy status:"
    echo "     sudo systemctl status haproxy"
    echo ""
    echo "Cleanup:"
    echo "  To remove Route53 DNS records:"
    echo "    ./hack/configure-route53-dns.sh remove ${cluster_config}"
    echo ""
    echo "  To stop HAProxy:"
    echo "    sudo systemctl stop haproxy"
    echo ""
}

# Function to verify prerequisites
verify_prerequisites() {
    print_section "Verifying Prerequisites"

    local missing_prereqs=0

    # Check for required environment variables
    if [ -z "$EXTERNAL_IP" ]; then
        print_error "EXTERNAL_IP not set"
        missing_prereqs=1
    else
        print_status "EXTERNAL_IP: ${EXTERNAL_IP}" 0
    fi

    if [ -z "$AWS_ACCESS_KEY_ID" ]; then
        print_error "AWS_ACCESS_KEY_ID not set"
        missing_prereqs=1
    else
        print_status "AWS_ACCESS_KEY_ID configured" 0
    fi

    if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        print_error "AWS_SECRET_ACCESS_KEY not set"
        missing_prereqs=1
    else
        print_status "AWS_SECRET_ACCESS_KEY configured" 0
    fi

    if [ -z "$EMAIL" ]; then
        print_error "EMAIL not set"
        missing_prereqs=1
    else
        print_status "EMAIL: ${EMAIL}" 0
    fi

    if [ -z "$KUBECONFIG" ]; then
        print_info "KUBECONFIG not set (will attempt to auto-detect)"
    else
        print_status "KUBECONFIG: ${KUBECONFIG}" 0
    fi

    # Check for required tools
    for tool in ansible-playbook yq aws oc; do
        if ! command -v $tool &>/dev/null; then
            print_error "${tool} not found"
            missing_prereqs=1
        else
            print_status "${tool} found" 0
        fi
    done

    # Check for container runtime
    if command -v podman &>/dev/null; then
        print_status "Container runtime: podman" 0
    elif command -v docker &>/dev/null; then
        print_status "Container runtime: docker" 0
    else
        print_error "Neither podman nor docker found"
        missing_prereqs=1
    fi

    if [ $missing_prereqs -ne 0 ]; then
        echo ""
        print_error "Missing prerequisites detected"
        echo ""
        echo "Please ensure all requirements are met:"
        echo ""
        echo "Environment Variables:"
        echo "  export EXTERNAL_IP=\"your-public-ip\""
        echo "  export AWS_ACCESS_KEY_ID=\"your-aws-key\""
        echo "  export AWS_SECRET_ACCESS_KEY=\"your-aws-secret\""
        echo "  export EMAIL=\"admin@example.com\""
        echo "  export KUBECONFIG=~/generated_assets/<cluster>/auth/kubeconfig"
        echo ""
        echo "Tools:"
        echo "  - ansible-playbook (dnf install ansible-core)"
        echo "  - yq (wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64)"
        echo "  - aws CLI (https://aws.amazon.com/cli/)"
        echo "  - oc CLI (./download-openshift-cli.sh)"
        echo "  - podman or docker"
        exit 1
    fi

    print_status "All prerequisites verified" 0
}

# Function to auto-detect KUBECONFIG if not set
auto_detect_kubeconfig() {
    if [ -z "$KUBECONFIG" ]; then
        local cluster_config=$1

        if command -v yq &>/dev/null && [ -f "$cluster_config" ]; then
            local cluster_name=$(yq eval '.cluster_name' "$cluster_config" 2>/dev/null)
            local generated_path="${HOME}/generated_assets"

            if [ -f "${generated_path}/${cluster_name}/auth/kubeconfig" ]; then
                export KUBECONFIG="${generated_path}/${cluster_name}/auth/kubeconfig"
                print_info "Auto-detected KUBECONFIG: ${KUBECONFIG}"
            fi
        fi
    fi
}

# Usage function
usage() {
    cat << EOF
Usage: $0 <cluster_config.yml>

Orchestrated setup for OpenShift external access with Route53 and Let's Encrypt.

This script performs the complete external access configuration:
  1. Deploy HAProxy to forward traffic from EXTERNAL_IP to cluster VIPs
  2. Create Route53 DNS records pointing to EXTERNAL_IP
  3. Wait for DNS propagation
  4. Obtain and install Let's Encrypt certificates

Prerequisites:
  - All tools installed (ansible, yq, aws, oc, podman/docker)
  - Environment variables set (see below)
  - AWS Route53 hosted zone for base_domain
  - OpenShift cluster running and accessible

CRITICAL - Domain Configuration:
  The base_domain in cluster.yml MUST be a real domain you own with a
  Route53 hosted zone (e.g., "mycompany.com", NOT "example.com").

  Both local dnsmasq and external Route53 use the SAME domain names:
  - Internal: api.cluster.domain → VIP (direct access)
  - External: api.cluster.domain → EXTERNAL_IP (HAProxy forwards to VIP)

  This is split-horizon DNS with the same hostnames but different IPs.

Required Environment Variables:
  EXTERNAL_IP             - Host's external/public IP address
  AWS_ACCESS_KEY_ID       - AWS access key for Route53
  AWS_SECRET_ACCESS_KEY   - AWS secret key for Route53
  EMAIL                   - Email for Let's Encrypt notifications
  KUBECONFIG              - Path to cluster kubeconfig (optional, auto-detected)

Optional Environment Variables:
  CERT_STAGING            - Use Let's Encrypt staging (default: false)
  ROUTE53_HOSTED_ZONE_ID  - Route53 zone ID (optional, auto-detected)

Example (with .env file - recommended):
  # 1. Copy and edit .env file
  cp .env.example .env
  vim .env  # Fill in your credentials
  chmod 600 .env

  # 2. Run script (.env is auto-loaded)
  $0 examples/sno-4.20-standard/cluster.yml

Example (with manual environment variables):
  export EXTERNAL_IP="203.0.113.10"
  export AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
  export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
  export EMAIL="admin@example.com"
  export KUBECONFIG=~/generated_assets/sno-4-20/auth/kubeconfig

  $0 examples/sno-4.20-standard/cluster.yml

For testing with Let's Encrypt staging:
  echo 'CERT_STAGING="true"' >> .env
  $0 examples/sno-4.20-standard/cluster.yml

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

    # Verify file exists
    if [ ! -f "$cluster_config" ]; then
        print_error "Cluster configuration file not found: ${cluster_config}"
        exit 1
    fi

    # Display banner
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  OpenShift External Access Configuration     ║${NC}"
    echo -e "${GREEN}║  Route53 DNS + HAProxy + Let's Encrypt      ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════╝${NC}"
    echo ""

    # Verify prerequisites
    verify_prerequisites

    # Auto-detect KUBECONFIG if not set
    auto_detect_kubeconfig "$cluster_config"

    # Parse cluster config for DNS propagation check
    if command -v yq &>/dev/null; then
        CLUSTER_NAME=$(yq eval '.cluster_name' "$cluster_config" 2>/dev/null)
        BASE_DOMAIN=$(yq eval '.base_domain' "$cluster_config" 2>/dev/null)
    fi

    # Phase 1: Configure HAProxy Forwarder
    print_section "Phase 1: Deploy HAProxy Forwarder"
    echo ""
    print_info "Configuring HAProxy to forward traffic from ${EXTERNAL_IP} to cluster VIPs..."
    echo ""

    "${SCRIPT_DIR}/configure-haproxy-forwarder.sh" "$cluster_config" || {
        print_error "HAProxy configuration failed"
        exit 1
    }

    # Phase 2: Configure Route53 DNS
    print_section "Phase 2: Configure Route53 DNS Records"
    echo ""
    print_info "Creating Route53 DNS records pointing to ${EXTERNAL_IP}..."
    echo ""

    "${SCRIPT_DIR}/configure-route53-dns.sh" add "$cluster_config" || {
        print_error "Route53 DNS configuration failed"
        exit 1
    }

    # Phase 3: Wait for DNS Propagation
    if [ -n "$CLUSTER_NAME" ] && [ -n "$BASE_DOMAIN" ]; then
        wait_for_dns_propagation "$CLUSTER_NAME" "$BASE_DOMAIN" "$EXTERNAL_IP"
    else
        print_info "Skipping DNS propagation check (could not parse cluster info)"
        print_info "Waiting 60 seconds for DNS propagation..."
        sleep 60
    fi

    # Phase 4: Obtain Let's Encrypt Certificates
    print_section "Phase 4: Obtain Let's Encrypt Certificates"
    echo ""
    print_info "Obtaining and installing Let's Encrypt certificates..."
    echo ""

    "${SCRIPT_DIR}/configure-letsencrypt-certs.sh" || {
        print_error "Let's Encrypt certificate configuration failed"
        exit 1
    }

    # Display summary
    display_setup_summary "$cluster_config"

    echo -e "${GREEN}╔═══════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         Configuration Complete!               ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════╝${NC}"
    echo ""
}

# Run main function
main "$@"
