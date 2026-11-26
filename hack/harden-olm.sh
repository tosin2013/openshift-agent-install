#!/bin/bash
# harden-olm.sh - Proactive OLM hardening after cluster install
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
log_success "OLM hardening complete."
echo ""
echo "  It is now safe to:"
echo "  - Install operators from OperatorHub"
echo "  - Apply Let's Encrypt certificates (answer 'y' to API cert prompt)"
echo "  - Apply MachineConfigs (pause MCP first)"
echo ""
echo "  Reference: hack/skills/deploy-cluster-kvm/SKILL.md (Lessons Learned section)"
