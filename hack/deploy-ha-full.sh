#!/bin/bash
# deploy-ha-full.sh - One-shot HA deployment with HAProxy integration
#
# This script orchestrates a complete HA cluster deployment on KVM:
#   1. Environment validation
#   2. ISO generation
#   3. DNS configuration (dnsmasq/libvirt)
#   4. HAProxy forwarder setup (external access)
#   5. VM deployment
#   6. Installation monitoring
#   7. Post-deployment validation
#
# Usage: ./hack/deploy-ha-full.sh <example-folder>
# Example: ./hack/deploy-ha-full.sh examples/ha-4.21-disconnected
#
# Prerequisites:
#   - EXTERNAL_IP environment variable (for HAProxy)
#   - Sufficient resources (see resource calculator below)
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
DEPLOY_HAPROXY=${DEPLOY_HAPROXY:-true}        # Deploy HAProxy forwarder
CONFIGURE_DNS=${CONFIGURE_DNS:-true}          # Configure DNS (libvirt)
MONITOR_INSTALL=${MONITOR_INSTALL:-true}      # Monitor installation
VALIDATION_TIMEOUT=${VALIDATION_TIMEOUT:-3600} # 60 min installation timeout

VALIDATION_REPORT="${HOME}/ha-deployment-report-$(date +%Y%m%d-%H%M%S).md"

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

One-shot HA cluster deployment on KVM with HAProxy integration.

ARGUMENTS:
    <example-folder>    Path to example configuration directory
                       Examples: examples/ha-4.21-disconnected
                                examples/cnv-bond0-tagged

OPTIONS:
    --skip-haproxy     Skip HAProxy forwarder configuration
    --skip-dns         Skip DNS configuration
    --skip-monitor     Skip installation monitoring (deploy VMs only)
    --help, -h         Show this help message

ENVIRONMENT VARIABLES:
    EXTERNAL_IP              Host's external IP for HAProxy (required if using HAProxy)
    GENERATED_ASSET_PATH     ISO/manifest output directory (default: ~/generated_assets)
    CLUSTER_NAME             Override cluster name from cluster.yml
    DEPLOY_HAPROXY           Deploy HAProxy (default: true)
    CONFIGURE_DNS            Configure DNS (default: true)
    MONITOR_INSTALL          Monitor installation (default: true)
    VALIDATION_TIMEOUT       Installation timeout in seconds (default: 3600)

PREREQUISITES:
    - KVM/libvirt installed and running
    - Ansible installed (ansible-playbook, ansible-galaxy)
    - yq installed for YAML parsing
    - Sufficient resources:
        * HA (3 masters + 2 workers): 40 vCPUs, 96 GB RAM, 600 GB disk
        * 3-Node Compact: 24 vCPUs, 96 GB RAM, 360 GB disk
    - EXTERNAL_IP set (for HAProxy external access)

WORKFLOW:
    Phase 1: Environment validation
    Phase 2: ISO generation (create-iso.sh)
    Phase 3: DNS configuration (libvirt dnsmasq)
    Phase 4: HAProxy forwarder setup (optional)
    Phase 5: VM deployment (deploy-on-kvm.sh)
    Phase 6: Installation monitoring
    Phase 7: Post-deployment validation

EXAMPLES:
    # Full HA deployment with HAProxy
    export EXTERNAL_IP="192.168.1.100"
    $0 examples/ha-4.21-disconnected

    # 3-node compact without external access
    $0 examples/baremetal-example --skip-haproxy

    # Deploy VMs only (no monitoring)
    $0 examples/cnv-bond0-tagged --skip-monitor

RELATED SCRIPTS:
    - hack/create-iso.sh                      # ISO generation
    - hack/deploy-on-kvm.sh                   # VM deployment
    - hack/configure-haproxy-forwarder.sh     # HAProxy setup
    - hack/configure-dnsmasq-entries.sh       # DNS management

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
            --skip-haproxy)
                DEPLOY_HAPROXY=false
                shift
                ;;
            --skip-dns)
                CONFIGURE_DNS=false
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

    # Extract example name (last component of path)
    EXAMPLE_NAME=$(basename "$EXAMPLE_FOLDER")

    log_info "Example: $EXAMPLE_NAME"
    log_info "Config: $EXAMPLE_FOLDER"
}

# Initialize report
init_report() {
    cat > "$VALIDATION_REPORT" << EOF
# HA Cluster Deployment Report

**Date:** $(date '+%Y-%m-%d %H:%M:%S')
**Example:** $EXAMPLE_NAME
**Configuration:** $EXAMPLE_FOLDER
**Host:** $(hostname)
**System:** RHEL $(rpm -E %{rhel})

## Deployment Configuration

- **HAProxy Forwarder:** $([ "$DEPLOY_HAPROXY" = "true" ] && echo "Enabled" || echo "Disabled")
- **DNS Configuration:** $([ "$CONFIGURE_DNS" = "true" ] && echo "Enabled" || echo "Disabled")
- **Installation Monitoring:** $([ "$MONITOR_INSTALL" = "true" ] && echo "Enabled" || echo "Disabled")

---

## Deployment Phases

EOF
}

# =============================================================================
# Phase 1: Environment Validation
# =============================================================================
phase1_environment_validation() {
    log_section "Phase 1: Environment Validation"

    echo "### Phase 1: Environment Validation" >> "$VALIDATION_REPORT"
    echo "" >> "$VALIDATION_REPORT"

    log_step "Running validate_env.sh..."
    if ./e2e-tests/validate_env.sh 2>&1 | tee /tmp/env-validation.log; then
        log_success "Environment validation passed"
        echo "✅ **Status:** PASSED" >> "$VALIDATION_REPORT"
    else
        log_error "Environment validation failed"
        echo "❌ **Status:** FAILED" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"
        echo '```' >> "$VALIDATION_REPORT"
        tail -50 /tmp/env-validation.log >> "$VALIDATION_REPORT"
        echo '```' >> "$VALIDATION_REPORT"
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
    echo "" >> "$VALIDATION_REPORT"

    log_info "Total RAM: ${total_ram}G | Available RAM: ${avail_ram}G"
    log_info "Available Disk: ${avail_disk}G"

    # Resource recommendations
    local node_count=$(yq eval '.nodes | length' "$EXAMPLE_FOLDER/nodes.yml")
    local recommended_ram=96
    local recommended_disk=600

    if [ "$node_count" -lt 5 ]; then
        # 3-node compact or SNO
        recommended_ram=96
        recommended_disk=360
    fi

    if [ "$avail_ram" -lt "$recommended_ram" ]; then
        log_warning "Low RAM: ${avail_ram}G available, ${recommended_ram}G recommended"
        echo "⚠️ **RAM Warning:** Available RAM (${avail_ram}G) below recommended (${recommended_ram}G)" >> "$VALIDATION_REPORT"
    fi

    if [ "$avail_disk" -lt "$recommended_disk" ]; then
        log_warning "Low disk: ${avail_disk}G available, ${recommended_disk}G recommended"
        echo "⚠️ **Disk Warning:** Available disk (${avail_disk}G) below recommended (${recommended_disk}G)" >> "$VALIDATION_REPORT"
    fi

    # Check HAProxy prerequisites
    if [ "$DEPLOY_HAPROXY" = "true" ]; then
        log_step "Checking HAProxy prerequisites..."
        if [ -z "$EXTERNAL_IP" ]; then
            log_error "EXTERNAL_IP not set (required for HAProxy)"
            log_info "Set with: export EXTERNAL_IP=\"<your-host-ip>\""
            echo "❌ **HAProxy Error:** EXTERNAL_IP not set" >> "$VALIDATION_REPORT"
            return 1
        fi
        log_success "EXTERNAL_IP: $EXTERNAL_IP"
        echo "- EXTERNAL_IP: $EXTERNAL_IP" >> "$VALIDATION_REPORT"
    fi

    echo "" >> "$VALIDATION_REPORT"
}

# =============================================================================
# Phase 2: ISO Generation
# =============================================================================
phase2_iso_generation() {
    log_section "Phase 2: ISO Generation"

    echo "### Phase 2: ISO Generation" >> "$VALIDATION_REPORT"
    echo "" >> "$VALIDATION_REPORT"

    log_step "Generating Agent-Based Installer ISO..."
    log_info "Command: ./hack/create-iso.sh $EXAMPLE_NAME"

    if ./hack/create-iso.sh "$EXAMPLE_NAME" 2>&1 | tee /tmp/iso-generation.log; then
        log_success "ISO generated successfully"
        echo "✅ **Status:** PASSED" >> "$VALIDATION_REPORT"

        # Extract cluster name for later use
        CLUSTER_NAME=$(yq eval '.cluster_name' "$EXAMPLE_FOLDER/cluster.yml")
        CLUSTER_NAME=$(echo "$CLUSTER_NAME" | tr '.' '-' | tr '_' '-')
        export CLUSTER_NAME

        log_info "Cluster name: $CLUSTER_NAME"

        # Verify ISO exists
        local iso_path="${GENERATED_ASSET_PATH:-$HOME/generated_assets}/${CLUSTER_NAME}/agent.x86_64.iso"
        if [ -f "$iso_path" ]; then
            local iso_size=$(du -h "$iso_path" | cut -f1)
            log_success "ISO created: $iso_path ($iso_size)"
            echo "" >> "$VALIDATION_REPORT"
            echo "**ISO Details:**" >> "$VALIDATION_REPORT"
            echo "- Path: \`$iso_path\`" >> "$VALIDATION_REPORT"
            echo "- Size: $iso_size" >> "$VALIDATION_REPORT"
        else
            log_error "ISO file not found: $iso_path"
            echo "❌ **Error:** ISO file not found" >> "$VALIDATION_REPORT"
            return 1
        fi

    else
        log_error "ISO generation failed"
        echo "❌ **Status:** FAILED" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"
        echo '```' >> "$VALIDATION_REPORT"
        tail -100 /tmp/iso-generation.log >> "$VALIDATION_REPORT"
        echo '```' >> "$VALIDATION_REPORT"
        return 1
    fi

    echo "" >> "$VALIDATION_REPORT"
}

# =============================================================================
# Phase 3: DNS Configuration
# =============================================================================
phase3_dns_configuration() {
    if [ "$CONFIGURE_DNS" != "true" ]; then
        log_section "Phase 3: DNS Configuration (SKIPPED)"
        echo "### Phase 3: DNS Configuration" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"
        echo "⊘ **Status:** SKIPPED (--skip-dns)" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"
        return 0
    fi

    log_section "Phase 3: DNS Configuration (libvirt)"

    echo "### Phase 3: DNS Configuration" >> "$VALIDATION_REPORT"
    echo "" >> "$VALIDATION_REPORT"

    log_step "Configuring DNS entries in libvirt network..."
    log_info "Command: ./hack/configure-dnsmasq-entries.sh add $EXAMPLE_FOLDER/cluster.yml"

    if ./hack/configure-dnsmasq-entries.sh add "$EXAMPLE_FOLDER/cluster.yml" 2>&1 | tee /tmp/dns-config.log; then
        log_success "DNS entries configured"
        echo "✅ **Status:** PASSED" >> "$VALIDATION_REPORT"

        # Extract DNS info
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
        log_warning "DNS configuration failed (non-critical)"
        echo "⚠️ **Status:** WARNING (failed but non-critical)" >> "$VALIDATION_REPORT"
    fi

    echo "" >> "$VALIDATION_REPORT"
}

# =============================================================================
# Phase 4: HAProxy Forwarder Setup
# =============================================================================
phase4_haproxy_forwarder() {
    if [ "$DEPLOY_HAPROXY" != "true" ]; then
        log_section "Phase 4: HAProxy Forwarder (SKIPPED)"
        echo "### Phase 4: HAProxy Forwarder" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"
        echo "⊘ **Status:** SKIPPED (--skip-haproxy or DEPLOY_HAPROXY=false)" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"
        return 0
    fi

    log_section "Phase 4: HAProxy Forwarder Setup"

    echo "### Phase 4: HAProxy Forwarder" >> "$VALIDATION_REPORT"
    echo "" >> "$VALIDATION_REPORT"

    log_step "Configuring HAProxy for external access..."
    log_info "Command: ./hack/configure-haproxy-forwarder.sh $EXAMPLE_FOLDER/cluster.yml"
    log_info "External IP: $EXTERNAL_IP"

    if ./hack/configure-haproxy-forwarder.sh "$EXAMPLE_FOLDER/cluster.yml" 2>&1 | tee /tmp/haproxy-config.log; then
        log_success "HAProxy configured successfully"
        echo "✅ **Status:** PASSED" >> "$VALIDATION_REPORT"

        # Extract VIP info
        local api_vip=$(yq eval '.api_vips[0]' "$EXAMPLE_FOLDER/cluster.yml")
        local app_vip=$(yq eval '.app_vips[0]' "$EXAMPLE_FOLDER/cluster.yml")

        echo "" >> "$VALIDATION_REPORT"
        echo "**HAProxy Forwarder Configuration:**" >> "$VALIDATION_REPORT"
        echo "- External IP: $EXTERNAL_IP" >> "$VALIDATION_REPORT"
        echo "- API Backend: $api_vip:6443" >> "$VALIDATION_REPORT"
        echo "- Apps Backend: $app_vip:443" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"
        echo "**Traffic Forwarding:**" >> "$VALIDATION_REPORT"
        echo "- ${EXTERNAL_IP}:6443 → ${api_vip}:6443 (API Server)" >> "$VALIDATION_REPORT"
        echo "- ${EXTERNAL_IP}:22623 → ${api_vip}:22623 (Machine Config)" >> "$VALIDATION_REPORT"
        echo "- ${EXTERNAL_IP}:80 → ${app_vip}:80 (HTTP Ingress)" >> "$VALIDATION_REPORT"
        echo "- ${EXTERNAL_IP}:443 → ${app_vip}:443 (HTTPS Ingress)" >> "$VALIDATION_REPORT"

        log_success "Traffic forwarding: ${EXTERNAL_IP} → VIPs"

    else
        log_error "HAProxy configuration failed"
        echo "❌ **Status:** FAILED" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"
        echo '```' >> "$VALIDATION_REPORT"
        tail -50 /tmp/haproxy-config.log >> "$VALIDATION_REPORT"
        echo '```' >> "$VALIDATION_REPORT"
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

    log_step "Deploying VMs to KVM..."
    log_info "Command: ./hack/deploy-on-kvm.sh $EXAMPLE_FOLDER/nodes.yml --redfish"

    if ./hack/deploy-on-kvm.sh "$EXAMPLE_FOLDER/nodes.yml" --redfish 2>&1 | tee /tmp/vm-deployment.log; then
        log_success "VMs deployed successfully"
        echo "✅ **Status:** PASSED" >> "$VALIDATION_REPORT"

        # List deployed VMs
        log_info "Deployed VMs:"
        virsh list --all | grep "$CLUSTER_NAME" | while read line; do
            log_success "  $line"
        done

        echo "" >> "$VALIDATION_REPORT"
        echo "**Deployed VMs:**" >> "$VALIDATION_REPORT"
        echo '```' >> "$VALIDATION_REPORT"
        virsh list --all | grep -E "Id.*Name.*State|$CLUSTER_NAME" >> "$VALIDATION_REPORT"
        echo '```' >> "$VALIDATION_REPORT"

        # Start watch-and-reboot script in background (CRITICAL for Agent-Based Installer)
        log_step "Starting VM auto-reboot watcher..."
        log_info "Agent-Based Installer VMs will shut down after writing image to disk"
        log_info "The watch script will automatically restart them"

        ./hack/watch-and-reboot-kvm-vms.sh "$EXAMPLE_FOLDER/nodes.yml" > /tmp/vm-reboot-watcher.log 2>&1 &
        WATCH_PID=$!

        log_success "VM watcher started (PID: $WATCH_PID)"
        echo "" >> "$VALIDATION_REPORT"
        echo "**VM Auto-Reboot Watcher:** Started (PID: $WATCH_PID)" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"
        echo "⚠️ **Important:** VMs will automatically shut down and restart during installation" >> "$VALIDATION_REPORT"

    else
        log_error "VM deployment failed"
        echo "❌ **Status:** FAILED" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"
        echo '```' >> "$VALIDATION_REPORT"
        tail -100 /tmp/vm-deployment.log >> "$VALIDATION_REPORT"
        echo '```' >> "$VALIDATION_REPORT"
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
        echo "⊘ **Status:** SKIPPED (--skip-monitor)" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"
        log_info "VMs deployed. Monitor manually with:"
        log_info "  ./bin/openshift-install agent wait-for install-complete --dir ${GENERATED_ASSET_PATH:-$HOME/generated_assets}/${CLUSTER_NAME}/"
        return 0
    fi

    log_section "Phase 6: Installation Monitoring"

    echo "### Phase 6: Installation Monitoring" >> "$VALIDATION_REPORT"
    echo "" >> "$VALIDATION_REPORT"

    local install_dir="${GENERATED_ASSET_PATH:-$HOME/generated_assets}/${CLUSTER_NAME}"

    log_step "Monitoring OpenShift installation..."
    log_info "Timeout: $VALIDATION_TIMEOUT seconds (~$((VALIDATION_TIMEOUT/60)) minutes)"
    log_info "Install dir: $install_dir"

    if timeout "$VALIDATION_TIMEOUT" ./bin/openshift-install agent wait-for install-complete --dir "$install_dir" 2>&1 | tee /tmp/install-monitor.log; then
        log_success "Installation completed successfully!"
        echo "✅ **Status:** COMPLETED" >> "$VALIDATION_REPORT"

        # Extract kubeconfig and credentials
        local kubeconfig="${install_dir}/auth/kubeconfig"
        local kubeadmin_password="${install_dir}/auth/kubeadmin-password"

        if [ -f "$kubeconfig" ]; then
            echo "" >> "$VALIDATION_REPORT"
            echo "**Cluster Access:**" >> "$VALIDATION_REPORT"
            echo '```bash' >> "$VALIDATION_REPORT"
            echo "export KUBECONFIG=${kubeconfig}" >> "$VALIDATION_REPORT"
            echo "oc get nodes" >> "$VALIDATION_REPORT"
            echo '```' >> "$VALIDATION_REPORT"

            log_success "KUBECONFIG: $kubeconfig"
        fi

        if [ -f "$kubeadmin_password" ]; then
            log_success "kubeadmin password: $kubeadmin_password"
        fi

        # Extract console URL from logs
        local console_url=$(grep -o "https://console-openshift-console\.apps\.[^ ]*" /tmp/install-monitor.log | head -1)
        if [ -n "$console_url" ]; then
            echo "" >> "$VALIDATION_REPORT"
            echo "**OpenShift Console:** $console_url" >> "$VALIDATION_REPORT"
            log_success "Console: $console_url"
        fi

        # Stop watch-and-reboot script (installation complete)
        if [ -n "$WATCH_PID" ] && kill -0 "$WATCH_PID" 2>/dev/null; then
            log_step "Stopping VM auto-reboot watcher..."
            kill "$WATCH_PID" 2>/dev/null || true
            wait "$WATCH_PID" 2>/dev/null || true
            log_success "VM watcher stopped"
        fi

    else
        log_error "Installation failed or timed out"
        echo "❌ **Status:** FAILED/TIMEOUT" >> "$VALIDATION_REPORT"
        echo "" >> "$VALIDATION_REPORT"
        echo '```' >> "$VALIDATION_REPORT"
        tail -200 /tmp/install-monitor.log >> "$VALIDATION_REPORT"
        echo '```' >> "$VALIDATION_REPORT"

        # Stop watch-and-reboot script on failure
        if [ -n "$WATCH_PID" ] && kill -0 "$WATCH_PID" 2>/dev/null; then
            kill "$WATCH_PID" 2>/dev/null || true
            wait "$WATCH_PID" 2>/dev/null || true
        fi

        return 1
    fi

    echo "" >> "$VALIDATION_REPORT"
}

# =============================================================================
# Phase 7: Post-Deployment Validation
# =============================================================================
phase7_post_deployment_validation() {
    if [ "$MONITOR_INSTALL" != "true" ]; then
        log_section "Phase 7: Post-Deployment Validation (SKIPPED)"
        return 0
    fi

    log_section "Phase 7: Post-Deployment Validation"

    echo "### Phase 7: Post-Deployment Validation" >> "$VALIDATION_REPORT"
    echo "" >> "$VALIDATION_REPORT"

    local kubeconfig="${GENERATED_ASSET_PATH:-$HOME/generated_assets}/${CLUSTER_NAME}/auth/kubeconfig"

    if [ ! -f "$kubeconfig" ]; then
        log_warning "KUBECONFIG not found, skipping validation"
        echo "⚠️ **Status:** SKIPPED (KUBECONFIG not available)" >> "$VALIDATION_REPORT"
        return 0
    fi

    export KUBECONFIG="$kubeconfig"

    log_step "Checking cluster nodes..."
    if oc get nodes 2>&1 | tee /tmp/nodes.log; then
        log_success "Nodes retrieved"
        echo "" >> "$VALIDATION_REPORT"
        echo "**Cluster Nodes:**" >> "$VALIDATION_REPORT"
        echo '```' >> "$VALIDATION_REPORT"
        cat /tmp/nodes.log >> "$VALIDATION_REPORT"
        echo '```' >> "$VALIDATION_REPORT"
    fi

    log_step "Checking cluster operators..."
    if oc get co 2>&1 | tee /tmp/operators.log; then
        log_success "Operators retrieved"
        echo "" >> "$VALIDATION_REPORT"
        echo "**Cluster Operators:**" >> "$VALIDATION_REPORT"
        echo '```' >> "$VALIDATION_REPORT"
        cat /tmp/operators.log >> "$VALIDATION_REPORT"
        echo '```' >> "$VALIDATION_REPORT"
    fi

    log_step "Checking cluster version..."
    if oc get clusterversion 2>&1 | tee /tmp/version.log; then
        log_success "Cluster version retrieved"
        echo "" >> "$VALIDATION_REPORT"
        echo "**Cluster Version:**" >> "$VALIDATION_REPORT"
        echo '```' >> "$VALIDATION_REPORT"
        cat /tmp/version.log >> "$VALIDATION_REPORT"
        echo '```' >> "$VALIDATION_REPORT"
    fi

    echo "" >> "$VALIDATION_REPORT"
}

# =============================================================================
# Generate Summary
# =============================================================================
generate_summary() {
    log_section "Deployment Summary"

    cat >> "$VALIDATION_REPORT" << EOF

---

## Deployment Summary

**Example:** $EXAMPLE_NAME
**Cluster Name:** ${CLUSTER_NAME:-N/A}
**Date:** $(date '+%Y-%m-%d %H:%M:%S')

### Phase Results
EOF

    # Count results
    local phases_passed=$(grep -c "✅.*PASSED\|✅.*COMPLETED" "$VALIDATION_REPORT" || echo 0)
    local phases_failed=$(grep -c "❌.*FAILED" "$VALIDATION_REPORT" || echo 0)
    local phases_skipped=$(grep -c "⊘.*SKIPPED" "$VALIDATION_REPORT" || echo 0)

    echo "" >> "$VALIDATION_REPORT"
    echo "- ✅ Passed/Completed: $phases_passed" >> "$VALIDATION_REPORT"
    echo "- ❌ Failed: $phases_failed" >> "$VALIDATION_REPORT"
    echo "- ⊘ Skipped: $phases_skipped" >> "$VALIDATION_REPORT"
    echo "" >> "$VALIDATION_REPORT"

    if [ "$phases_failed" -eq 0 ] && [ "$MONITOR_INSTALL" = "true" ]; then
        cat >> "$VALIDATION_REPORT" << EOF
### ✅ Deployment Status: SUCCESS

HA cluster deployed and validated successfully!

**Next Steps:**
1. Access cluster: \`export KUBECONFIG=${GENERATED_ASSET_PATH:-$HOME/generated_assets}/${CLUSTER_NAME}/auth/kubeconfig\`
2. Test applications: \`oc new-project test && oc new-app httpd\`
3. Review operators: \`oc get co\`

EOF
        log_success "HA deployment completed successfully!"

    elif [ "$phases_failed" -eq 0 ]; then
        cat >> "$VALIDATION_REPORT" << EOF
### ✅ Deployment Status: VMS DEPLOYED

VMs deployed successfully. Installation monitoring was skipped.

**Next Steps:**
1. Monitor installation: \`./bin/openshift-install agent wait-for install-complete --dir ${GENERATED_ASSET_PATH:-$HOME/generated_assets}/${CLUSTER_NAME}/\`
2. Check VM status: \`virsh list --all | grep ${CLUSTER_NAME}\`

EOF
        log_success "VMs deployed successfully (monitoring skipped)"

    else
        cat >> "$VALIDATION_REPORT" << EOF
### ❌ Deployment Status: FAILED

$phases_failed phase(s) failed. Review the logs above for details.

**Troubleshooting:**
1. Check logs in /tmp/*-log
2. Review cluster.yml and nodes.yml configuration
3. Verify system resources meet requirements
4. Check libvirt/KVM status: \`sudo systemctl status libvirtd\`

**Cleanup:**
\`./hack/destroy-on-kvm.sh $EXAMPLE_FOLDER/nodes.yml\`

EOF
        log_error "$phases_failed deployment phase(s) failed"
    fi

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Deployment Complete${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "📊 Phases: $phases_passed passed, $phases_failed failed, $phases_skipped skipped"
    echo "📄 Full report: $VALIDATION_REPORT"
    echo ""

    # Display report
    cat "$VALIDATION_REPORT"

    # Exit with appropriate code
    [ "$phases_failed" -eq 0 ]
}

# =============================================================================
# Main
# =============================================================================
main() {
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  OpenShift HA Deployment - One-Shot Script           ║${NC}"
    echo -e "${CYAN}║  With HAProxy Forwarder Integration                  ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""

    parse_arguments "$@"
    init_report

    # Execute deployment phases
    phase1_environment_validation || exit 1
    phase2_iso_generation || exit 1
    phase3_dns_configuration || exit 1
    phase4_haproxy_forwarder || exit 1
    phase5_vm_deployment || exit 1
    phase6_installation_monitoring || true  # Non-fatal
    phase7_post_deployment_validation || true  # Non-fatal

    generate_summary
}

# Run main
main "$@"
