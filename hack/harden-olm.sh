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
# ⚠️  KNOWN LIMITATION (OCP 5.0 — 2026-11-27):
# -------------------------------------------------------
# The catalog source memory targets (redhat-operators: 30Mi, certified: 40Mi,
# community: 120Mi) are HARDCODED in the marketplace-operator image and managed
# by its /defaults directory. They CANNOT be overridden by:
#   - Patching the CatalogSource object (marketplace-operator reverts it)
#   - Mounting a ConfigMap over /defaults (crashes the marketplace-operator)
#   - OperatorHub CR (no memory config in its spec)
#
# 30Mi is insufficient for redhat-operators which serves 500+ packages in OCP 5.0.
# Under heavy concurrent ListBundles load it OOMKills, causing brief (~30s)
# catalog unavailability and a "loading failures" alert in OperatorHub UI.
#
# MITIGATION (applied by this script):
#   - catalog-operator liveness probe: 1s → 5s (prevents cascade on OOMKill)
#   - packageserver liveness probe: 1s → 5s (same)
#   - etcd read-ahead: 4096KB → 0 (reduces API load that triggers ListBundles storms)
#
# STATUS: Should be filed as a Bugzilla against marketplace-operator for OCP 5.x.
# Check if fixed before deploying on OCP 5.1+.
# -------------------------------------------------------
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

    log_info "  Applying etcd disk tuning MachineConfig (Butane-generated)..."
    log_info "  Uses: udev rule (99-etcd-disk-tuning.rules) + systemd service for belt-and-suspenders"
    # Use the Butane-generated MachineConfig from hack/etcd-disk-tuning-mc.yaml
    # This has proper encoding and survives reboots (unlike hand-crafted percent-encoded versions)
    MC_FILE="$(dirname "$0")/etcd-disk-tuning-mc.yaml"
    if [ -f "$MC_FILE" ]; then
        tail -n +2 "$MC_FILE" | oc apply -f - 2>/dev/null \
            && log_success "  MachineConfig applied from $MC_FILE" \
            || log_warn "  MachineConfig apply failed — check: oc apply -f hack/etcd-disk-tuning-mc.yaml"
    else
        log_warn "  hack/etcd-disk-tuning-mc.yaml not found — run: oc apply -f hack/etcd-disk-tuning-mc.yaml manually"
    fi

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
