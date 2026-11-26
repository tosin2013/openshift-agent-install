#!/bin/bash
# harden-olm.sh - Proactive OLM hardening after cluster install
#
# NOTE: Was the OLM breakage caused by cert rotation?
# -------------------------------------------------------
# Both directly AND indirectly. The cert rotation itself does not change OLM
# settings — but it triggers a restart storm (29+ catalog-operator restarts)
# as OLM probes fail during the API server rolling update. Each restart
# hammers all catalog sources with concurrent gRPC ListBundles calls, which
# spikes the redhat-operators catalog pod memory above its 30Mi default limit
# → OOMKill → subscription resolution fails → OperatorHub broken.
#
# Under normal operation, 30Mi might have been fine — the catalog-operator
# makes gentle, spread-out queries. The cert rotation just stress-tested
# and exposed a pre-existing sizing limitation in OCP 5.0's catalog defaults.
#
# The 1s OLM liveness probe timeout is also too aggressive — any brief API
# server slowdown (cert rollout, MachineConfig reboot, etcd election) can
# exceed it, triggering unnecessary restarts that make the situation worse.
#
# This script fixes both issues proactively. Run it after every new install
# and before any cert changes, MachineConfig rollouts, or operator installs.
# -------------------------------------------------------
#
# Problem: OCP 5.0 default OLM component settings are too aggressive for clusters
# that undergo cert rotation or any significant API server disruption:
#   - OLM liveness probes have 1s timeout → mass restarts under API load
#   - Catalog source memory limits (30Mi) → OOMKilled under load
#
# This causes a cascade: restarts → catalog OOM → subscription resolution fails
# → OperatorHub broken → operators fail to install.
#
# Run this ONCE after cluster install and BEFORE applying any cert changes.
#
# Usage:
#   export KUBECONFIG=~/generated_assets/<cluster>/auth/kubeconfig
#   ./hack/harden-olm.sh
#
# Safe to re-run — uses patch merge so idempotent.

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo ""
echo "==========================================="
echo " OLM Hardening — Probe Timeouts + Catalog Memory"
echo "==========================================="
echo ""

# Check cluster access
if ! oc whoami &>/dev/null; then
    echo "ERROR: Not logged in. Set KUBECONFIG or run oc login first."
    exit 1
fi

log_info "Cluster: $(oc whoami --show-server 2>/dev/null)"
echo ""

# 1. Increase OLM component liveness/readiness probe timeouts
log_info "Step 1: Increasing OLM probe timeouts (1s → 5s)..."

for dep in packageserver catalog-operator package-server-manager; do
    CURRENT=$(oc get deployment $dep \
        -n openshift-operator-lifecycle-manager \
        -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.timeoutSeconds}' 2>/dev/null || echo "")

    if [ "$CURRENT" = "5" ]; then
        log_success "  $dep: already at 5s"
        continue
    fi

    oc patch deployment $dep \
        -n openshift-operator-lifecycle-manager \
        --type=json \
        -p='[
            {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/timeoutSeconds","value":5},
            {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/timeoutSeconds","value":5}
        ]' 2>/dev/null && log_success "  $dep: patched to 5s" || log_warn "  $dep: patch failed (may not exist)"
done

echo ""

# 2. Increase catalog source memory targets
log_info "Step 2: Increasing catalog source memory targets..."

declare -A CATALOG_MEMORY=(
    ["redhat-operators"]="200Mi"
    ["certified-operators"]="100Mi"
    ["community-operators"]="100Mi"
)

for catalog in "${!CATALOG_MEMORY[@]}"; do
    target="${CATALOG_MEMORY[$catalog]}"
    CURRENT=$(oc get catalogsource $catalog \
        -n openshift-marketplace \
        -o jsonpath='{.spec.grpcPodConfig.memoryTarget}' 2>/dev/null || echo "")

    if [ "$CURRENT" = "$target" ]; then
        log_success "  $catalog: already at $target"
        continue
    fi

    oc patch catalogsource $catalog \
        -n openshift-marketplace \
        --type=merge \
        -p="{\"spec\":{\"grpcPodConfig\":{\"memoryTarget\":\"${target}\"}}}" 2>/dev/null \
        && log_success "  $catalog: set to $target (was: ${CURRENT:-not set})" \
        || log_warn "  $catalog: patch failed (may not exist)"
done

echo ""

# 3. Wait for OLM rollout to stabilize
log_info "Step 3: Waiting for OLM deployments to stabilize..."
for dep in packageserver catalog-operator; do
    oc rollout status deployment/$dep \
        -n openshift-operator-lifecycle-manager \
        --timeout=120s 2>/dev/null \
        && log_success "  $dep: rolled out" \
        || log_warn "  $dep: rollout status check failed"
done

echo ""

# 4. Verify
log_info "Step 4: Verification..."
echo ""
echo "  OLM component probe timeouts:"
for dep in packageserver catalog-operator package-server-manager; do
    TIMEOUT=$(oc get deployment $dep \
        -n openshift-operator-lifecycle-manager \
        -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.timeoutSeconds}' 2>/dev/null || echo "N/A")
    echo "    $dep: ${TIMEOUT}s"
done

echo ""
echo "  Catalog source memory targets:"
for catalog in redhat-operators certified-operators community-operators; do
    MEM=$(oc get catalogsource $catalog \
        -n openshift-marketplace \
        -o jsonpath='{.spec.grpcPodConfig.memoryTarget}' 2>/dev/null || echo "N/A")
    echo "    $catalog: $MEM"
done

echo ""

# 5. Apply etcd KVM disk tuning MachineConfig
# IMPORTANT: Must be done BEFORE deploying ArgoCD/operators on KVM.
# High read-ahead (4096KB default) on qcow2 disks causes etcd latency spikes
# that cascade into kube-apiserver timeouts and operator install failures.
log_info "Step 5: Applying KVM etcd disk tuning MachineConfig..."
echo ""

EXISTING_MC=$(oc get machineconfig 98-etcd-disk-tuning-master 2>/dev/null | wc -l)
if [ "$EXISTING_MC" -gt 1 ]; then
    log_success "  MachineConfig 98-etcd-disk-tuning-master already exists"
else
    log_info "  Pausing master MCP to batch MachineConfig into one rollout pass..."
    oc patch mcp/master --type=merge -p '{"spec":{"paused":true}}' 2>/dev/null \
        && log_success "  master MCP paused" \
        || log_warn "  could not pause MCP (may already be paused or inaccessible)"

    log_info "  Applying etcd disk tuning MachineConfig (udev rule: read_ahead_kb=0 on /dev/vda)..."
    cat <<'MCEOF' | oc apply -f - 2>/dev/null \
        && log_success "  MachineConfig applied" \
        || log_warn "  MachineConfig apply failed — apply manually: hack/tune-etcd-kvm.sh"
apiVersion: machineconfiguration.openshift.io/v1
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
            source: "data:text/plain;charset=utf-8,ACTION%3D%3D%22add%7Cchange%22%2C%20KERNEL%3D%3D%22vda%22%2C%20ATTR%7Bqueue%2Fread_ahead_kb%7D%3D%220%22%0A"
MCEOF

    log_info "  Unpausing master MCP — single rollout pass will begin..."
    oc patch mcp/master --type=merge -p '{"spec":{"paused":false}}' 2>/dev/null \
        && log_success "  master MCP unpaused — watch: oc get mcp master -w" \
        || log_warn "  could not unpause MCP"

    echo ""
    log_warn "  NOTE: MachineConfig rollout will reboot each control plane node (~15-20 min)."
    log_warn "  Wait for 'oc get mcp master' to show UPDATED=True before deploying ArgoCD."
fi

echo ""
log_success "OLM hardening complete."
echo ""
echo "  NEXT STEPS (in order):"
echo "  1. Wait for MCP rollout: watch oc get mcp master"
echo "  2. Apply Let's Encrypt INGRESS cert (answer N to API cert on KVM):"
echo "       INSTALL_API_CERT=n ./hack/configure-letsencrypt-certs.sh"
echo "  3. Configure HAProxy: EXTERNAL_IP=<ip> ./hack/configure-haproxy-forwarder.sh <cluster.yml>"
echo "  4. THEN deploy ArgoCD/operators (etcd will be stable)"
echo ""
echo "  Reference: hack/skills/deploy-cluster-kvm/SKILL.md (Lessons Learned section)"
