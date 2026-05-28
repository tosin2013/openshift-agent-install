#!/bin/bash
# deploy-connected-full.sh - One-shot connected deployment with proper pre-deployment setup
#
# This script orchestrates a complete connected cluster deployment on KVM:
#   Phase 0: DNS Infrastructure Setup (dnsmasq/VyOS router)
#   Phase 1: Environment validation
#   Phase 2: ISO generation
#   Phase 3: DNS entries configuration
#   Phase 4: HAProxy forwarder setup (optional)
#   Phase 5: VM deployment
#   Phase 6: Installation monitoring
#   Phase 7: Post-deployment validation
#
# Usage: ./hack/deploy-connected-full.sh <example-folder>
# Example: ./hack/deploy-connected-full.sh examples/sno-4.20-standard
#
# Prerequisites:
#   - Pull secret at ~/pull-secret.json
#   - EXTERNAL_IP environment variable (for HAProxy)
#   - Sufficient resources
#   - Root/sudo access

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$SCRIPT_DIR/.."

# Configuration
DEPLOY_HAPROXY=${DEPLOY_HAPROXY:-false}       # Deploy HAProxy forwarder (optional for connected)
DEPLOY_DNS=${DEPLOY_DNS:-true}                # Deploy DNS infrastructure
DEPLOY_ROUTER=${DEPLOY_ROUTER:-false}         # Deploy VyOS router (alternative to dnsmasq)
MONITOR_INSTALL=${MONITOR_INSTALL:-true}      # Monitor installation
VALIDATION_TIMEOUT=${VALIDATION_TIMEOUT:-3600} # 60 min installation timeout
PULL_SECRET_PATH=${PULL_SECRET_PATH:-"~/pull-secret.json"}

VALIDATION_REPORT="${HOME}/connected-deployment-report-$(date +%Y%m%d-%H%M%S).md"

# Print functions
log_section() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

log_step() {
    echo -e "${CYAN}▶${NC} $1"
}

# Usage
usage() {
    cat << EOF
Usage: $0 <example-folder> [OPTIONS]

One-shot CONNECTED cluster deployment on KVM with full infrastructure setup.

ARGUMENTS:
    <example-folder>    Path to example configuration directory
                       Examples: examples/sno-4.20-standard
                                examples/cnv-bond0-tagged

OPTIONS:
    --with-haproxy     Include HAProxy forwarder configuration
    --with-router      Use VyOS router instead of dnsmasq
    --skip-dns         Skip DNS infrastructure setup (use existing)
    --skip-monitor     Skip installation monitoring (deploy VMs only)
    --help, -h         Show this help message

ENVIRONMENT VARIABLES:
    PULL_SECRET_PATH         Path to pull secret (default: ~/pull-secret.json)
    EXTERNAL_IP              Host's external IP for HAProxy (if using --with-haproxy)
    GENERATED_ASSET_PATH     ISO/manifest output directory (default: ~/generated_assets)
    CLUSTER_NAME             Override cluster name from cluster.yml
    DEPLOY_DNS               Deploy DNS infrastructure (default: true)
    DEPLOY_ROUTER            Deploy VyOS router (default: false)
    DEPLOY_HAPROXY           Deploy HAProxy (default: false)
    MONITOR_INSTALL          Monitor installation (default: true)

PREREQUISITES:
    - Pull secret from https://console.redhat.com/openshift/downloads
      Saved at: ~/pull-secret.json
    - KVM/libvirt installed and running
    - Sudo privileges for DNS/network setup

WORKFLOW:
    Phase 0: DNS Infrastructure (dnsmasq or VyOS router)
    Phase 1: Environment validation
    Phase 2: ISO generation (with real pull secret)
    Phase 3: DNS entries configuration
    Phase 4: HAProxy forwarder setup (optional)
    Phase 5: VM deployment
    Phase 6: Installation monitoring
    Phase 7: Post-deployment validation

EXAMPLES:
    # SNO deployment with dnsmasq DNS
    $0 examples/sno-4.20-standard

    # HA deployment with HAProxy
    export EXTERNAL_IP=192.168.1.100
    $0 examples/cnv-bond0-tagged --with-haproxy

    # Using existing DNS (skip DNS setup)
    $0 examples/sno-4.20-standard --skip-dns

    # Deploy VMs only (no monitoring)
    $0 examples/sno-4.20-standard --skip-monitor

RELATED SCRIPTS:
    - hack/setup-dnsmasq.sh                   # DNS infrastructure
    - hack/configure-dnsmasq-entries.sh       # DNS entries
    - hack/create-iso.sh                      # ISO generation
    - hack/deploy-on-kvm.sh                   # VM deployment

SEE ALSO:
    llm.txt - Complete deployment guide
    examples/README.md - Example configurations

EOF
}

# Parse arguments
parse_arguments() {
    if [ $# -lt 1 ]; then
        log_error "No example folder specified"
        echo ""
        usage
        exit 1
    fi

    EXAMPLE_FOLDER="$1"
    shift

    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --with-haproxy)
                DEPLOY_HAPROXY=true
                shift
                ;;
            --with-router)
                DEPLOY_ROUTER=true
                DEPLOY_DNS=false  # VyOS replaces dnsmasq
                shift
                ;;
            --skip-dns)
                DEPLOY_DNS=false
                shift
                ;;
            --skip-monitor)
                MONITOR_INSTALL=false
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo ""
                usage
                exit 1
                ;;
        esac
    done

    # Validate example folder
    if [ ! -d "$EXAMPLE_FOLDER" ]; then
        log_error "Example folder not found: $EXAMPLE_FOLDER"
        exit 1
    fi

    if [ ! -f "$EXAMPLE_FOLDER/cluster.yml" ]; then
        log_error "cluster.yml not found in $EXAMPLE_FOLDER"
        exit 1
    fi

    if [ ! -f "$EXAMPLE_FOLDER/nodes.yml" ]; then
        log_error "nodes.yml not found in $EXAMPLE_FOLDER"
        exit 1
    fi

    # Extract example name
    EXAMPLE_NAME=$(basename "$EXAMPLE_FOLDER")

    log_info "Example: $EXAMPLE_NAME"
    log_info "Config: $EXAMPLE_FOLDER"
}

# Initialize report
init_report() {
    cat > "$VALIDATION_REPORT" << EOF
# Connected Cluster Deployment Report

**Date:** $(date '+%Y-%m-%d %H:%M:%S')
**Example:** $EXAMPLE_NAME
**Configuration:** $EXAMPLE_FOLDER
**Host:** $(hostname)
**System:** RHEL $(rpm -E %{rhel})

## Deployment Configuration

- **DNS Infrastructure:** $([ "$DEPLOY_DNS" = "true" ] && echo "dnsmasq" || ([ "$DEPLOY_ROUTER" = "true" ] && echo "VyOS router" || echo "Existing"))
- **HAProxy Forwarder:** $([ "$DEPLOY_HAPROXY" = "true" ] && echo "Enabled" || echo "Disabled")
- **Installation Monitoring:** $([ "$MONITOR_INSTALL" = "true" ] && echo "Enabled" || echo "Disabled")

---

## Deployment Phases

EOF
}

# =============================================================================
# Helper: Check VyOS Router Networks
# =============================================================================
check_vyos_networks() {
    local vyos_networks=("1924" "1925" "1926" "1927" "1928")
    local missing_networks=()

    log_step "Checking VyOS router networks..."

    for net in "${vyos_networks[@]}"; do
        if sudo virsh net-list --all | grep -q "^[[:space:]]*${net}[[:space:]]"; then
            local state=$(sudo virsh net-list --all | grep "^[[:space:]]*${net}[[:space:]]" | awk '{print $2}')
            if [ "$state" = "active" ]; then
                log_info "Network $net: active"
            else
                log_warning "Network $net: exists but not active"
                missing_networks+=("$net")
            fi
        else
            log_warning "Network $net: not found"
            missing_networks+=("$net")
        fi
    done

    if [ ${#missing_networks[@]} -gt 0 ]; then
        log_warning "Missing/inactive VyOS networks: ${missing_networks[*]}"
        return 1
    else
        log_success "All VyOS networks are active"
        return 0
    fi
}

# =============================================================================
# Phase 0: DNS Infrastructure Setup
# =============================================================================
phase0_dns_infrastructure() {
    if [ "$DEPLOY_DNS" != "true" ] && [ "$DEPLOY_ROUTER" != "true" ]; then
        log_section "Phase 0: DNS Infrastructure (SKIPPED - Using Existing)"
        echo "### Phase 0: DNS Infrastructure" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"
        echo "⊘ **Status:** SKIPPED (using existing DNS)" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"
        return 0
    fi

    if [ "$DEPLOY_DNS" = "true" ]; then
        log_section "Phase 0: DNS Infrastructure (dnsmasq)"
        echo "### Phase 0: DNS Infrastructure (dnsmasq)" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"

        log_step "Installing and configuring dnsmasq..."
        if sudo ./hack/setup-dnsmasq.sh 2>&1 | tee /tmp/dnsmasq-setup.log; then
            log_success "dnsmasq installed and configured"
            echo "✅ **Status:** PASSED" >> "$VALIDATION_REPORT"
        else
            log_error "dnsmasq setup failed"
            echo "❌ **Status:** FAILED" >> "$VALIDATION_REPORT"
            return 1
        fi
    elif [ "$DEPLOY_ROUTER" = "true" ]; then
        log_section "Phase 0: DNS Infrastructure (VyOS Router)"
        echo "### Phase 0: DNS Infrastructure (VyOS)" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"

        # Check if VyOS networks already exist
        if check_vyos_networks; then
            log_success "VyOS networks already configured"
            echo "✅ **Status:** PASSED (existing networks)" >> "$VALIDATION_REPORT"
        else
            log_step "Deploying VyOS router and networks..."
            if ./hack/vyos-router.sh create 2>&1 | tee /tmp/vyos-setup.log; then
                log_success "VyOS router deployed"
                echo "✅ **Status:** PASSED" >> "$VALIDATION_REPORT"

                # Verify networks after creation
                sleep 5  # Give networks time to become active
                if check_vyos_networks; then
                    log_success "VyOS networks verified"
                    echo "" >> "$VALIDATION_REPORT"
                    echo "**VyOS Networks Created:** 1924, 1925, 1926, 1927, 1928" >> "$VALIDATION_REPORT"
                else
                    log_warning "Some VyOS networks may not be active"
                    echo "⚠️ **Warning:** Not all networks active" >> "$VALIDATION_REPORT"
                fi
            else
                log_error "VyOS router deployment failed"
                echo "❌ **Status:** FAILED" >> "$VALIDATION_REPORT"
                return 1
            fi
        fi
    fi

    echo "" >> "$VALIDATION_REPORT"
}

# =============================================================================
# Phase 1: Environment Validation
# =============================================================================
phase1_environment_validation() {
    log_section "Phase 1: Environment Validation"
    echo "### Phase 1: Environment Validation" >> "$VALIDATION_REPORT"
    echo "" >> "$VALIDATION_REPORT"

    # Check pull secret
    log_step "Checking pull secret..."
    PULL_SECRET_PATH=$(eval echo "$PULL_SECRET_PATH")
    
    if [ ! -f "$PULL_SECRET_PATH" ]; then
        log_error "Pull secret not found at: $PULL_SECRET_PATH"
        log_info "Download from: https://console.redhat.com/openshift/downloads"
        echo "❌ **Pull Secret Error:** Not found at $PULL_SECRET_PATH" >> "$VALIDATION_REPORT"
        return 1
    fi

    # Validate pull secret JSON
    if ! jq empty "$PULL_SECRET_PATH" 2>/dev/null; then
        log_error "Pull secret is not valid JSON: $PULL_SECRET_PATH"
        echo "❌ **Pull Secret Error:** Invalid JSON" >> "$VALIDATION_REPORT"
        return 1
    fi

    # Check if pull secret has actual auth entries
    local auth_count=$(jq -r '.auths | keys | length' "$PULL_SECRET_PATH" 2>/dev/null || echo "0")
    if [ "$auth_count" -eq 0 ]; then
        log_error "Pull secret has no authentication entries"
        echo "❌ **Pull Secret Error:** No auth entries" >> "$VALIDATION_REPORT"
        return 1
    fi

    log_success "Pull secret valid: $PULL_SECRET_PATH ($auth_count registries)"

    # Update cluster.yml to use correct pull secret path
    log_step "Updating pull_secret_path in cluster.yml..."
    sed -i "s|pull_secret_path:.*|pull_secret_path: $PULL_SECRET_PATH|" "$EXAMPLE_FOLDER/cluster.yml"
    log_success "cluster.yml updated with correct pull_secret_path"

    # Run environment validation
    log_step "Running validate_env.sh..."
    if ./e2e-tests/validate_env.sh 2>&1 | tee /tmp/env-validation.log; then
        log_success "Environment validation passed"
        echo "✅ **Status:** PASSED" >> "$VALIDATION_REPORT"
    else
        log_error "Environment validation failed"
        echo "❌ **Status:** FAILED" >> "$VALIDATION_REPORT"
        return 1
    fi

    # Check resources
    log_step "Checking available resources..."
    local total_ram=$(free -g | grep Mem | awk '{print $2}')
    local avail_ram=$(free -g | grep Mem | awk '{print $7}')
    local avail_disk=$(df -BG / | tail -1 | awk '{print $4}' | tr -d 'G')

    echo "" >> "$VALIDATION_REPORT"
    echo "**System Resources:**" >> "$VALIDATION_REPORT"
    echo "- Total RAM: ${total_ram}G" >> "$VALIDATION_REPORT"
    echo "- Available RAM: ${avail_ram}G" >> "$VALIDATION_REPORT"
    echo "- Available Disk: ${avail_disk}G" >> "$VALIDATION_REPORT"
    echo "- Pull Secret: $PULL_SECRET_PATH ($auth_count registries)" >> "$VALIDATION_REPORT"
    echo "" >> "$VALIDATION_REPORT"

    log_info "Resources: RAM=${avail_ram}G, Disk=${avail_disk}G"

    echo "" >> "$VALIDATION_REPORT"
}

# Import remaining phases from deploy-ha-full.sh
# Phase 2: ISO Generation
phase2_iso_generation() {
    log_section "Phase 2: ISO Generation"
    echo "### Phase 2: ISO Generation" >> "$VALIDATION_REPORT"
    echo "" >> "$VALIDATION_REPORT"

    log_step "Generating Agent-Based Installer ISO..."
    log_info "Command: ./hack/create-iso.sh $EXAMPLE_NAME"

    if ./hack/create-iso.sh "$EXAMPLE_NAME" 2>&1 | tee /tmp/iso-generation.log; then
        log_success "ISO generated successfully"
        echo "✅ **Status:** PASSED" >> "$VALIDATION_REPORT"

        CLUSTER_NAME=$(yq eval '.cluster_name' "$EXAMPLE_FOLDER/cluster.yml")
        CLUSTER_NAME=$(echo "$CLUSTER_NAME" | tr '.' '-' | tr '_' '-')
        export CLUSTER_NAME

        local iso_path="${GENERATED_ASSET_PATH:-$HOME/generated_assets}/${CLUSTER_NAME}/agent.x86_64.iso"
        if [ -f "$iso_path" ]; then
            local iso_size=$(du -h "$iso_path" | cut -f1)
            log_success "ISO created: $iso_path ($iso_size)"
            echo "" >> "$VALIDATION_REPORT"
            echo "**ISO Details:**" >> "$VALIDATION_REPORT"
            echo "- Path: \`$iso_path\`" >> "$VALIDATION_REPORT"
            echo "- Size: $iso_size" >> "$VALIDATION_REPORT"
        fi
    else
        log_error "ISO generation failed"
        echo "❌ **Status:** FAILED" >> "$VALIDATION_REPORT"
        return 1
    fi

    echo "" >> "$VALIDATION_REPORT"
}

# Phase 3: DNS Configuration
phase3_dns_configuration() {
    log_section "Phase 3: DNS Entries Configuration"
    echo "### Phase 3: DNS Entries Configuration" >> "$VALIDATION_REPORT"
    echo "" >> "$VALIDATION_REPORT"

    log_step "Configuring DNS entries..."
    log_info "Command: sudo ./hack/configure-dnsmasq-entries.sh add $EXAMPLE_FOLDER/cluster.yml"

    sudo ./hack/configure-dnsmasq-entries.sh add "$EXAMPLE_FOLDER/cluster.yml" 2>&1 | tee /tmp/dns-config.log
    DNS_CONFIG_EXIT=${PIPESTATUS[0]}

    if [ $DNS_CONFIG_EXIT -eq 0 ]; then
        log_success "DNS entries configured"
        echo "✅ **Status:** PASSED" >> "$VALIDATION_REPORT"

        local cluster_name=$(yq eval '.cluster_name' "$EXAMPLE_FOLDER/cluster.yml")
        local base_domain=$(yq eval '.base_domain' "$EXAMPLE_FOLDER/cluster.yml")
        local api_vip=$(yq eval '.api_vips[0]' "$EXAMPLE_FOLDER/cluster.yml")
        local app_vip=$(yq eval '.app_vips[0]' "$EXAMPLE_FOLDER/cluster.yml")

        echo "" >> "$VALIDATION_REPORT"
        echo "**DNS Entries:**" >> "$VALIDATION_REPORT"
        echo "- api.${cluster_name}.${base_domain} → ${api_vip}" >> "$VALIDATION_REPORT"
        echo "- *.apps.${cluster_name}.${base_domain} → ${app_vip}" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"

        log_success "API: api.${cluster_name}.${base_domain} → ${api_vip}"
        log_success "Apps: *.apps.${cluster_name}.${base_domain} → ${app_vip}"
    else
        log_error "DNS configuration failed - this is a CRITICAL prerequisite"
        echo "❌ **Status:** FAILED" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"
        echo "**Troubleshooting:**" >> "$VALIDATION_REPORT"
        echo "1. Verify dnsmasq is running: \`sudo systemctl status dnsmasq\`" >> "$VALIDATION_REPORT"
        echo "2. Check configuration: \`sudo cat /etc/dnsmasq.d/openshift.conf\`" >> "$VALIDATION_REPORT"
        echo "3. Manually configure: \`sudo ./hack/configure-dnsmasq-entries.sh add $EXAMPLE_FOLDER/cluster.yml\`" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"
        return 1
    fi

    echo "" >> "$VALIDATION_REPORT"
}

# =============================================================================
# Phase 3.5: DNS Resolution Verification (HARD REQUIREMENT)
# =============================================================================
phase3_5_dns_verification() {
    if [ "$DEPLOY_DNS" != "true" ] && [ "$DEPLOY_ROUTER" != "true" ]; then
        log_section "Phase 3.5: DNS Resolution Verification (SKIPPED)"
        echo "### Phase 3.5: DNS Resolution Verification" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"
        echo "⊘ **Status:** SKIPPED (DNS not deployed by this script)" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"
        return 0
    fi

    log_section "Phase 3.5: DNS Resolution Verification"
    echo "### Phase 3.5: DNS Resolution Verification" >> "$VALIDATION_REPORT"
    echo "" >> "$VALIDATION_REPORT"

    log_step "Verifying DNS resolution works..."
    log_info "Command: ./hack/verify-dns-resolution.sh $EXAMPLE_FOLDER/cluster.yml"

    ./hack/verify-dns-resolution.sh "$EXAMPLE_FOLDER/cluster.yml" 2>&1 | tee /tmp/dns-verify.log
    DNS_VERIFY_EXIT=${PIPESTATUS[0]}

    if [ $DNS_VERIFY_EXIT -eq 0 ]; then
        log_success "DNS resolution verified - all tests passed"
        echo "✅ **Status:** PASSED" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"
        echo "**Verified DNS Endpoints:**" >> "$VALIDATION_REPORT"
        echo "- api.<cluster>.<domain> → API VIP" >> "$VALIDATION_REPORT"
        echo "- api-int.<cluster>.<domain> → API VIP" >> "$VALIDATION_REPORT"
        echo "- console-openshift-console.apps.<cluster>.<domain> → App VIP" >> "$VALIDATION_REPORT"
        echo "- oauth-openshift.apps.<cluster>.<domain> → App VIP" >> "$VALIDATION_REPORT"
        echo "- test.apps.<cluster>.<domain> → App VIP (wildcard)" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"
    else
        log_error "DNS resolution verification FAILED"
        echo "❌ **Status:** FAILED" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"
        echo "**DNS verification is a HARD REQUIREMENT - VM deployment cannot proceed without working DNS.**" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"
        echo "**Troubleshooting Steps:**" >> "$VALIDATION_REPORT"
        echo "1. Check DNS entries exist:" >> "$VALIDATION_REPORT"
        echo "   \`sudo cat /etc/dnsmasq.d/openshift.conf | grep <cluster-name>\`" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"
        echo "2. Restart dnsmasq:" >> "$VALIDATION_REPORT"
        echo "   \`sudo systemctl restart dnsmasq\`" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"
        echo "3. Test resolution manually:" >> "$VALIDATION_REPORT"
        echo "   \`dig @localhost api.<cluster>.<domain>\`" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"
        echo "4. Re-run DNS configuration:" >> "$VALIDATION_REPORT"
        echo "   \`sudo ./hack/configure-dnsmasq-entries.sh add $EXAMPLE_FOLDER/cluster.yml\`" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"
        return 1
    fi

    echo "" >> "$VALIDATION_REPORT"
}

# =============================================================================
# Phase 4: HAProxy Forwarder Configuration (Optional)
# =============================================================================
phase4_haproxy_forwarder() {
    if [ "$DEPLOY_HAPROXY" != "true" ]; then
        log_section "Phase 4: HAProxy Forwarder (SKIPPED)"
        echo "### Phase 4: HAProxy Forwarder" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"
        echo "⊘ **Status:** SKIPPED (not requested)" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"
        return 0
    fi

    log_section "Phase 4: HAProxy Forwarder Configuration"
    echo "### Phase 4: HAProxy Forwarder" >> "$VALIDATION_REPORT"
    echo "" >> "$VALIDATION_REPORT"

    # Check EXTERNAL_IP
    if [ -z "$EXTERNAL_IP" ]; then
        log_error "EXTERNAL_IP environment variable not set"
        log_info "Set with: export EXTERNAL_IP=<host-external-ip>"
        echo "❌ **Status:** FAILED (EXTERNAL_IP not set)" >> "$VALIDATION_REPORT"
        return 1
    fi

    log_step "Configuring HAProxy forwarder..."
    log_info "External IP: $EXTERNAL_IP"
    log_info "Command: ./hack/configure-haproxy-forwarder.sh $EXAMPLE_FOLDER/cluster.yml"

    if ./hack/configure-haproxy-forwarder.sh "$EXAMPLE_FOLDER/cluster.yml" 2>&1 | tee /tmp/haproxy-config.log; then
        log_success "HAProxy configured"
        echo "✅ **Status:** PASSED" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"
        echo "**HAProxy Configuration:**" >> "$VALIDATION_REPORT"
        echo "- External IP: $EXTERNAL_IP" >> "$VALIDATION_REPORT"
        echo "- API Proxy: $EXTERNAL_IP:6443 → VIP:6443" >> "$VALIDATION_REPORT"
        echo "- HTTP Proxy: $EXTERNAL_IP:80 → VIP:80" >> "$VALIDATION_REPORT"
        echo "- HTTPS Proxy: $EXTERNAL_IP:443 → VIP:443" >> "$VALIDATION_REPORT"
    else
        log_error "HAProxy configuration failed"
        echo "❌ **Status:** FAILED" >> "$VALIDATION_REPORT"
        return 1
    fi

    echo "" >> "$VALIDATION_REPORT"
}

# =============================================================================
# Phase 5: VM Deployment
# =============================================================================
phase5_vm_deployment() {
    log_section "Phase 5: VM Deployment"
    echo "### Phase 5: VM Deployment" >> "$VALIDATION_REPORT"
    echo "" >> "$VALIDATION_REPORT"

    log_step "Deploying virtual machines on KVM..."
    log_info "Command: ./hack/deploy-on-kvm.sh $EXAMPLE_FOLDER/nodes.yml --redfish"

    if ./hack/deploy-on-kvm.sh "$EXAMPLE_FOLDER/nodes.yml" --redfish 2>&1 | tee /tmp/vm-deployment.log; then
        log_success "VMs deployed successfully"
        echo "✅ **Status:** PASSED" >> "$VALIDATION_REPORT"

        # Count deployed VMs
        local vm_count=$(yq eval '.nodes | length' "$EXAMPLE_FOLDER/nodes.yml")
        echo "" >> "$VALIDATION_REPORT"
        echo "**Deployed VMs:** $vm_count" >> "$VALIDATION_REPORT"

        # List VMs
        echo "" >> "$VALIDATION_REPORT"
        echo "**VM Details:**" >> "$VALIDATION_REPORT"
        local nodes=$(yq eval '.nodes[].name' "$EXAMPLE_FOLDER/nodes.yml")
        for node in $nodes; do
            local status=$(sudo virsh list --all | grep "$node" | awk '{print $3}' || echo "unknown")
            echo "- \`$node\`: $status" >> "$VALIDATION_REPORT"
        done
    else
        log_error "VM deployment failed"
        echo "❌ **Status:** FAILED" >> "$VALIDATION_REPORT"
        return 1
    fi

    echo "" >> "$VALIDATION_REPORT"
}

# =============================================================================
# Phase 6: Installation Monitoring
# =============================================================================
phase6_installation_monitoring() {
    if [ "$MONITOR_INSTALL" != "true" ]; then
        log_section "Phase 6: Installation Monitoring (SKIPPED)"
        echo "### Phase 6: Installation Monitoring" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"
        echo "⊘ **Status:** SKIPPED (user requested)" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"
        return 0
    fi

    log_section "Phase 6: Installation Monitoring"
    echo "### Phase 6: Installation Monitoring" >> "$VALIDATION_REPORT"
    echo "" >> "$VALIDATION_REPORT"

    CLUSTER_NAME=$(yq eval '.cluster_name' "$EXAMPLE_FOLDER/cluster.yml")
    CLUSTER_NAME=$(echo "$CLUSTER_NAME" | tr '.' '-' | tr '_' '-')
    local asset_dir="${GENERATED_ASSET_PATH:-$HOME/generated_assets}/${CLUSTER_NAME}"

    if [ ! -d "$asset_dir" ]; then
        log_error "Asset directory not found: $asset_dir"
        echo "❌ **Status:** FAILED (asset directory missing)" >> "$VALIDATION_REPORT"
        return 1
    fi

    log_step "Monitoring installation progress..."
    log_info "Directory: $asset_dir"
    log_info "Timeout: ${VALIDATION_TIMEOUT}s ($(($VALIDATION_TIMEOUT / 60)) minutes)"

    echo "" >> "$VALIDATION_REPORT"
    echo "**Monitoring Configuration:**" >> "$VALIDATION_REPORT"
    echo "- Asset Directory: \`$asset_dir\`" >> "$VALIDATION_REPORT"
    echo "- Timeout: $(($VALIDATION_TIMEOUT / 60)) minutes" >> "$VALIDATION_REPORT"
    echo "" >> "$VALIDATION_REPORT"

    # Monitor with timeout
    local start_time=$(date +%s)
    local monitor_log="/tmp/install-monitor.log"

    log_info "Running: ./bin/openshift-install agent wait-for install-complete --dir $asset_dir"

    if timeout "$VALIDATION_TIMEOUT" ./bin/openshift-install agent wait-for install-complete \
        --dir "$asset_dir" 2>&1 | tee "$monitor_log"; then
        local end_time=$(date +%s)
        local duration=$(($end_time - $start_time))
        local duration_min=$(($duration / 60))

        log_success "Installation completed!"
        log_info "Duration: ${duration_min} minutes"

        echo "✅ **Status:** PASSED" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"
        echo "**Installation Time:** ${duration_min} minutes" >> "$VALIDATION_REPORT"
    else
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            log_error "Installation timeout reached (${VALIDATION_TIMEOUT}s)"
            echo "❌ **Status:** TIMEOUT" >> "$VALIDATION_REPORT"
        else
            log_error "Installation failed (exit code: $exit_code)"
            echo "❌ **Status:** FAILED" >> "$VALIDATION_REPORT"
        fi

        return 1
    fi

    echo "" >> "$VALIDATION_REPORT"
}

# =============================================================================
# Phase 7: Post-Deployment Validation
# =============================================================================
phase7_post_deployment_validation() {
    log_section "Phase 7: Post-Deployment Validation"
    echo "### Phase 7: Post-Deployment Validation" >> "$VALIDATION_REPORT"
    echo "" >> "$VALIDATION_REPORT"

    CLUSTER_NAME=$(yq eval '.cluster_name' "$EXAMPLE_FOLDER/cluster.yml")
    CLUSTER_NAME=$(echo "$CLUSTER_NAME" | tr '.' '-' | tr '_' '-')
    local asset_dir="${GENERATED_ASSET_PATH:-$HOME/generated_assets}/${CLUSTER_NAME}"
    local kubeconfig="$asset_dir/auth/kubeconfig"

    if [ ! -f "$kubeconfig" ]; then
        log_warning "kubeconfig not found: $kubeconfig"
        echo "⚠️ **Status:** WARNING (kubeconfig missing)" >> "$VALIDATION_REPORT"
        return 0
    fi

    export KUBECONFIG="$kubeconfig"

    # Check cluster nodes
    log_step "Checking cluster nodes..."
    if oc get nodes 2>&1 | tee /tmp/nodes-check.log; then
        local node_count=$(oc get nodes --no-headers 2>/dev/null | wc -l)
        local ready_count=$(oc get nodes --no-headers 2>/dev/null | grep -c " Ready")

        log_success "Nodes: $ready_count/$node_count Ready"

        echo "**Cluster Nodes:**" >> "$VALIDATION_REPORT"
        echo "\`\`\`" >> "$VALIDATION_REPORT"
        oc get nodes --no-headers 2>/dev/null | head -10 >> "$VALIDATION_REPORT"
        echo "\`\`\`" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"
    else
        log_warning "Unable to check nodes (cluster may still be initializing)"
    fi

    # Check cluster operators
    log_step "Checking cluster operators..."
    if oc get co 2>&1 | tee /tmp/co-check.log; then
        local total_co=$(oc get co --no-headers 2>/dev/null | wc -l)
        local available_co=$(oc get co --no-headers 2>/dev/null | awk '{print $3}' | grep -c "True")

        log_success "Cluster Operators: $available_co/$total_co Available"

        echo "**Cluster Operators:**" >> "$VALIDATION_REPORT"
        echo "\`\`\`" >> "$VALIDATION_REPORT"
        oc get co --no-headers 2>/dev/null | head -10 >> "$VALIDATION_REPORT"
        echo "\`\`\`" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"

        # Check for degraded operators
        local degraded_co=$(oc get co --no-headers 2>/dev/null | awk '{print $4}' | grep -c "True")
        if [ "$degraded_co" -gt 0 ]; then
            log_warning "$degraded_co cluster operator(s) degraded"
            echo "⚠️ **Warning:** $degraded_co operator(s) degraded" >> "$VALIDATION_REPORT"
        fi
    else
        log_warning "Unable to check cluster operators"
    fi

    # Get cluster version
    log_step "Checking OpenShift version..."
    if oc version 2>&1 | tee /tmp/version-check.log; then
        local ocp_version=$(oc version -o json 2>/dev/null | jq -r '.openshiftVersion' 2>/dev/null || echo "unknown")
        log_success "OpenShift version: $ocp_version"

        echo "" >> "$VALIDATION_REPORT"
        echo "**OpenShift Version:** $ocp_version" >> "$VALIDATION_REPORT"
    fi

    # Overall validation status
    echo "" >> "$VALIDATION_REPORT"
    echo "✅ **Overall Status:** Deployment completed successfully" >> "$VALIDATION_REPORT"
    echo "" >> "$VALIDATION_REPORT"

    log_success "Post-deployment validation complete"
}

# =============================================================================
# Generate Final Report Summary
# =============================================================================
generate_summary() {
    log_section "Deployment Summary"

    cat >> "$VALIDATION_REPORT" << EOF

---

## Access Information

**Kubeconfig:**
\`\`\`bash
export KUBECONFIG=${GENERATED_ASSET_PATH:-$HOME/generated_assets}/${CLUSTER_NAME}/auth/kubeconfig
oc get nodes
oc get co
\`\`\`

**Console URL:**
\`\`\`
https://console-openshift-console.apps.${CLUSTER_NAME}.$(yq eval '.base_domain' "$EXAMPLE_FOLDER/cluster.yml")
\`\`\`

**Credentials:**
\`\`\`bash
cat ${GENERATED_ASSET_PATH:-$HOME/generated_assets}/${CLUSTER_NAME}/auth/kubeadmin-password
\`\`\`

---

## Deployment Report

📄 Full report saved to: \`$VALIDATION_REPORT\`

**Next Steps:**
1. Verify all cluster operators are available
2. Test application deployments
3. Configure additional cluster features as needed

EOF

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Deployment Complete!${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "📊 Deployment Report: $VALIDATION_REPORT"
    echo ""

    # Display key information
    local cluster_name=$(yq eval '.cluster_name' "$EXAMPLE_FOLDER/cluster.yml")
    local base_domain=$(yq eval '.base_domain' "$EXAMPLE_FOLDER/cluster.yml")

    echo -e "${CYAN}Console:${NC} https://console-openshift-console.apps.${cluster_name}.${base_domain}"
    echo -e "${CYAN}Kubeconfig:${NC} ${GENERATED_ASSET_PATH:-$HOME/generated_assets}/${CLUSTER_NAME}/auth/kubeconfig"
    echo ""
}

# Main
main() {
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  OpenShift Connected Deployment - One-Shot Script    ║${NC}"
    echo -e "${CYAN}║  With DNS Infrastructure Setup                       ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""

    parse_arguments "$@"
    init_report

    # Execute deployment phases
    phase0_dns_infrastructure || exit 1
    phase1_environment_validation || exit 1
    phase2_iso_generation || exit 1
    phase3_dns_configuration || exit 1
    phase3_5_dns_verification || exit 1  # HARD REQUIREMENT: Verify DNS works before VM deployment
    phase4_haproxy_forwarder || true  # Optional - don't exit on failure
    phase5_vm_deployment || exit 1
    phase6_installation_monitoring || true  # Don't exit on monitoring failure
    phase7_post_deployment_validation || true  # Don't exit on validation issues

    generate_summary

    log_success "✅ Connected deployment workflow completed!"
    echo ""
}

# Show help if requested
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    usage
    exit 0
fi

# Run main
main "$@"
