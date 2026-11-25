#!/bin/bash
# tune-etcd-kvm.sh - Apply etcd disk performance tuning for KVM/qcow2 deployments
#
# Problem: VM disks default to 4MB read-ahead which causes massive I/O amplification
# for etcd's small random reads on qcow2-backed storage, resulting in 99th percentile
# read latencies > 1s (observed up to 4s+ on IBM Cloud KVM).
#
# Fix: Set read-ahead to 0 on control plane VM disks via a persistent MachineConfig.
#
# Usage:
#   ./hack/tune-etcd-kvm.sh                        # Apply MachineConfig (requires KUBECONFIG)
#   ./hack/tune-etcd-kvm.sh --live <nodes-yml>     # Also apply immediately via SSH
#   ./hack/tune-etcd-kvm.sh --check                # Check current read-ahead values
#
# Only applies to KVM/qcow2 deployments — not needed on bare metal.

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$SCRIPT_DIR/.."

SITE_CONFIG_DIR="${SITE_CONFIG_DIR:-examples}"
MODE="${1:-apply}"
NODES_YML="${2:-}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERR]${NC} $1"; }

# NOTE: Use a udev rule (not a systemd service) for persistent read-ahead tuning.
# A systemd service fires before udev resets block device params, so udev overrides it.
# The udev rule fires on add/change events for vda, which always runs AFTER the kernel default.
# Rule content: ACTION=="add|change", KERNEL=="vda", ATTR{queue/read_ahead_kb}="0"
MACHINECONFIG_YAML='apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  name: 98-etcd-disk-tuning-master
  labels:
    machineconfiguration.openshift.io/role: master
spec:
  config:
    ignition:
      version: 3.4.0
    storage:
      files:
        - path: /etc/udev/rules.d/98-etcd-disk-tuning.rules
          mode: 0644
          contents:
            source: "data:text/plain;charset=utf-8,ACTION%3D%3D%22add%7Cchange%22%2C%20KERNEL%3D%3D%22vda%22%2C%20ATTR%7Bqueue%2Fread_ahead_kb%7D%3D%220%22%0A"'

apply_machineconfig() {
    log_info "Applying MachineConfig 98-etcd-disk-tuning-master..."

    if [ -z "$KUBECONFIG" ]; then
        log_error "KUBECONFIG not set. Export it before running this script."
        exit 1
    fi

    # Check if already exists
    if oc get machineconfig 98-etcd-disk-tuning-master &>/dev/null 2>&1; then
        log_success "MachineConfig 98-etcd-disk-tuning-master already exists"
        return 0
    fi

    echo "$MACHINECONFIG_YAML" | oc apply -f -
    log_success "MachineConfig applied — master nodes will update on next reconcile"
    log_info "Monitor rollout: oc get mcp master"
}

apply_live() {
    local nodes_yml="$1"
    local ssh_key
    # Find SSH key from generated assets
    ssh_key=$(find ~/generated_assets/ -name "ssh_key" -type f 2>/dev/null | head -1)

    if [ -z "$ssh_key" ]; then
        log_warn "No SSH key found in ~/generated_assets/ — skipping live apply"
        return 1
    fi

    log_info "Applying read-ahead=0 live via SSH..."
    # Extract master IPs from nodes.yml
    local master_ips
    master_ips=$(grep -A5 "role: master" "$nodes_yml" 2>/dev/null | grep "ip:" | awk '{print $2}' || \
                 yq eval '.nodes[] | select(.role == "master") | .networkConfig.interfaces[].ipv4.address[].ip' "$nodes_yml" 2>/dev/null | head -3)

    if [ -z "$master_ips" ]; then
        log_warn "Could not parse master IPs from $nodes_yml"
        return 1
    fi

    for ip in $master_ips; do
        log_info "  Applying to $ip..."
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 -i "$ssh_key" core@"$ip" \
          "sudo sh -c 'echo 0 > /sys/block/vda/queue/read_ahead_kb && echo \"read_ahead_kb on vda: \$(cat /sys/block/vda/queue/read_ahead_kb)\"'" 2>&1 || \
          log_warn "  Could not reach $ip via SSH"
    done
}

check_values() {
    local ssh_key
    ssh_key=$(find ~/generated_assets/ -name "ssh_key" -type f 2>/dev/null | head -1)

    if [ -z "$ssh_key" ]; then
        log_error "No SSH key found in ~/generated_assets/"
        exit 1
    fi

    log_info "Checking read-ahead values on control plane nodes..."
    for ip in 192.168.50.21 192.168.50.22 192.168.50.23; do
        result=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$ssh_key" core@"$ip" \
          "cat /sys/block/vda/queue/read_ahead_kb 2>/dev/null" 2>/dev/null || echo "unreachable")
        if [ "$result" = "0" ]; then
            log_success "  $ip: read_ahead_kb = $result ✅"
        elif [ "$result" = "unreachable" ]; then
            log_warn "  $ip: unreachable"
        else
            log_warn "  $ip: read_ahead_kb = $result ⚠️  (should be 0)"
        fi
    done
}

echo ""
echo "==========================================="
echo " etcd KVM Disk Tuning"
echo "==========================================="
echo ""

case "$MODE" in
    --check)
        check_values
        ;;
    --live)
        if [ -z "$NODES_YML" ]; then
            log_error "Usage: $0 --live <path-to-nodes.yml>"
            exit 1
        fi
        apply_live "$NODES_YML"
        apply_machineconfig
        ;;
    apply|--apply|"")
        apply_machineconfig
        log_info ""
        log_info "To also apply immediately (without waiting for MachineConfig rollout):"
        log_info "  $0 --live <nodes.yml>"
        ;;
    *)
        echo "Usage: $0 [--check | --live <nodes.yml> | apply]"
        exit 1
        ;;
esac

echo ""
log_success "Done. Verify etcd health in ~5 min:"
log_info "  oc -n openshift-etcd logs etcd-<node> -c etcd --tail=30 | grep -i 'slow\|latency'"
log_info "  oc get co etcd"
