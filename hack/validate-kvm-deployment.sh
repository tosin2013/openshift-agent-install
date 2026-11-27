#!/bin/bash
# validate-kvm-deployment.sh - Post-install health validation for KVM deployments
#
# Checks cluster health, KVM-specific settings, and known issue mitigations.
# Run after: openshift-install agent wait-for install-complete
#
# Usage:
#   export KUBECONFIG=~/generated_assets/<cluster>/auth/kubeconfig
#   ./hack/validate-kvm-deployment.sh [--control-plane-ips "192.168.50.21 192.168.50.22 192.168.50.23"]
#   ./hack/validate-kvm-deployment.sh --ssh-key ~/generated_assets/<cluster>/ssh_key
#
# Exit codes: 0=all checks passed, 1=warnings only, 2=failures found

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SSH_KEY="${SSH_KEY:-}"
CONTROL_PLANE_IPS="${CONTROL_PLANE_IPS:-}"

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --ssh-key) SSH_KEY="$2"; shift 2 ;;
        --control-plane-ips) CONTROL_PLANE_IPS="$2"; shift 2 ;;
        *) echo "Unknown arg: $1"; shift ;;
    esac
done

# Auto-detect SSH key if not provided
if [ -z "$SSH_KEY" ]; then
    SSH_KEY=$(find ~/generated_assets/ -name "ssh_key" -type f 2>/dev/null | head -1)
fi

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
PASS=0; WARN=0; FAIL=0

pass() { echo -e "${GREEN}  ✅ PASS${NC} $1"; ((PASS++)); }
warn() { echo -e "${YELLOW}  ⚠️  WARN${NC} $1"; ((WARN++)); }
fail() { echo -e "${RED}  ❌ FAIL${NC} $1"; ((FAIL++)); }
section() { echo -e "\n${BLUE}══ $1 ══${NC}"; }

echo ""
echo "============================================="
echo " KVM Deployment Validation"
echo "============================================="
echo ""

# ─── 1. KUBECONFIG ───────────────────────────────────────────────────────────
section "Cluster Access"

if [ -z "${KUBECONFIG:-}" ]; then
    fail "KUBECONFIG not set — export KUBECONFIG=~/generated_assets/<cluster>/auth/kubeconfig"
elif ! oc whoami &>/dev/null 2>&1; then
    fail "Cannot connect to cluster — check KUBECONFIG and cluster state"
else
    pass "Connected as: $(oc whoami 2>/dev/null)"
fi

# ─── 2. NODES ────────────────────────────────────────────────────────────────
section "Node Health"

NOT_READY=$(oc get nodes --no-headers 2>/dev/null | grep -v " Ready" | grep -v "^$" | wc -l)
TOTAL=$(oc get nodes --no-headers 2>/dev/null | wc -l)
if [ "$NOT_READY" -eq 0 ]; then
    pass "All $TOTAL nodes Ready"
else
    fail "$NOT_READY/$TOTAL nodes NotReady"
    oc get nodes 2>/dev/null | grep -v "Ready " | grep -v "^NAME"
fi

# ─── 3. CLUSTER OPERATORS ────────────────────────────────────────────────────
section "Cluster Operators"

TOTAL_CO=$(oc get co --no-headers 2>/dev/null | wc -l)
GREEN_CO=$(oc get co --no-headers 2>/dev/null | grep -c "True.*False.*False" || true)
DEGRADED=$(oc get co --no-headers 2>/dev/null | grep -v "True.*False.*False" | grep -v "^$" | wc -l)

if [ "$DEGRADED" -eq 0 ]; then
    pass "All $TOTAL_CO cluster operators green"
elif [ "$DEGRADED" -le 2 ]; then
    warn "$GREEN_CO/$TOTAL_CO operators green ($DEGRADED degraded/progressing)"
    oc get co 2>/dev/null | awk 'NR==1 || $3!="True" || $4!="False" || $5!="False"' | grep -v "^NAME"
else
    fail "$GREEN_CO/$TOTAL_CO operators green ($DEGRADED degraded)"
    oc get co 2>/dev/null | awk '$3!="True" || $4!="False" || $5!="False"' | grep -v "^NAME"
fi

# ─── 4. ETCD ─────────────────────────────────────────────────────────────────
section "etcd Health"

ETCD_STATUS=$(oc get co etcd -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)
if [ "$ETCD_STATUS" = "True" ]; then
    pass "etcd operator Available"
else
    fail "etcd operator not Available"
fi

# ─── 5. KVM-SPECIFIC: etcd read-ahead ────────────────────────────────────────
section "KVM-Specific: etcd Disk Tuning"

if [ -n "$SSH_KEY" ] && [ -f "$SSH_KEY" ]; then
    # Auto-detect control plane IPs if not provided
    if [ -z "$CONTROL_PLANE_IPS" ]; then
        CONTROL_PLANE_IPS=$(oc get nodes -l node-role.kubernetes.io/master \
          -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{" "}{end}' 2>/dev/null)
    fi

    ALL_TUNED=true
    for ip in $CONTROL_PLANE_IPS; do
        READ_AHEAD=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
          -i "$SSH_KEY" core@$ip \
          "cat /sys/block/vda/queue/read_ahead_kb 2>/dev/null" 2>/dev/null || echo "unreachable")
        if [ "$READ_AHEAD" = "0" ]; then
            pass "$ip: read_ahead_kb = 0 ✅"
        elif [ "$READ_AHEAD" = "unreachable" ]; then
            warn "$ip: unreachable via SSH (check connectivity)"
        else
            fail "$ip: read_ahead_kb = $READ_AHEAD (should be 0 — run: oc apply -f hack/etcd-disk-tuning-mc.yaml)"
            ALL_TUNED=false
        fi

        # Check udev rule
        UDEV=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
          -i "$SSH_KEY" core@$ip \
          "cat /etc/udev/rules.d/99-etcd-disk-tuning.rules 2>/dev/null || echo 'MISSING'" 2>/dev/null)
        if echo "$UDEV" | grep -q "read_ahead_kb"; then
            pass "$ip: udev rule present"
        else
            warn "$ip: udev rule missing (MachineConfig not yet applied or still rolling)"
        fi
    done
else
    warn "SSH key not found — skipping etcd disk tuning check"
    warn "  Set: SSH_KEY=~/generated_assets/<cluster>/ssh_key"
    warn "  Or:  --ssh-key ~/generated_assets/<cluster>/ssh_key"
fi

# Check MachineConfig exists
if oc get machineconfig 98-etcd-disk-tuning-master &>/dev/null 2>&1; then
    pass "MachineConfig 98-etcd-disk-tuning-master exists"
else
    fail "MachineConfig 98-etcd-disk-tuning-master missing — run: oc apply -f hack/etcd-disk-tuning-mc.yaml"
fi

# ─── 6. OLM HARDENING ────────────────────────────────────────────────────────
section "OLM Hardening"

for dep in packageserver catalog-operator; do
    TIMEOUT=$(oc get deployment $dep \
        -n openshift-operator-lifecycle-manager \
        -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.timeoutSeconds}' 2>/dev/null || echo "N/A")
    if [ "$TIMEOUT" = "5" ]; then
        pass "$dep: liveness probe = 5s"
    elif [ "$TIMEOUT" = "N/A" ]; then
        warn "$dep: not found"
    else
        fail "$dep: liveness probe = ${TIMEOUT}s (should be 5s — run: ./hack/harden-olm.sh)"
    fi
done

# ─── 7. CATALOG SOURCES ──────────────────────────────────────────────────────
section "OperatorHub Catalog"

PKG_COUNT=$(oc get packagemanifest -n openshift-marketplace --no-headers 2>/dev/null | wc -l)
if [ "$PKG_COUNT" -ge 500 ]; then
    pass "Catalog loaded: $PKG_COUNT packages"
elif [ "$PKG_COUNT" -gt 0 ]; then
    warn "Catalog partially loaded: $PKG_COUNT packages (expected ~528)"
else
    fail "Catalog empty — check catalog source pods in openshift-marketplace"
fi

for cs in redhat-operators certified-operators community-operators; do
    STATE=$(oc get catalogsource $cs -n openshift-marketplace \
        -o jsonpath='{.status.connectionState.lastObservedState}' 2>/dev/null || echo "MISSING")
    MEM=$(oc get catalogsource $cs -n openshift-marketplace \
        -o jsonpath='{.spec.grpcPodConfig.memoryTarget}' 2>/dev/null || echo "N/A")
    if [ "$STATE" = "READY" ]; then
        pass "$cs: READY (memory: $MEM)"
    else
        warn "$cs: $STATE (memory: $MEM)"
    fi
done

# ─── 8. EXTERNAL ACCESS ──────────────────────────────────────────────────────
section "External Access"

# HAProxy
if systemctl is-active haproxy &>/dev/null 2>&1; then
    pass "HAProxy: active"
else
    warn "HAProxy: not running (run: ./hack/configure-haproxy-forwarder.sh)"
fi

# Console
CONSOLE_HOST=$(oc get route console -n openshift-console \
    -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [ -n "$CONSOLE_HOST" ]; then
    HTTP_CODE=$(curl -sk --max-time 5 "https://${CONSOLE_HOST}" -o /dev/null -w "%{http_code}" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ]; then
        pass "Console accessible: https://${CONSOLE_HOST}"
    else
        warn "Console: https://${CONSOLE_HOST} returned HTTP $HTTP_CODE"
    fi
else
    warn "Console route not found"
fi

# Cert issuer
ISSUER=$(echo | openssl s_client -connect "${CONSOLE_HOST}:443" \
    -servername "${CONSOLE_HOST}" 2>/dev/null \
    | openssl x509 -noout -issuer 2>/dev/null | head -1 || echo "")
if echo "$ISSUER" | grep -q "Let's Encrypt"; then
    pass "Console TLS: Let's Encrypt ✅"
elif echo "$ISSUER" | grep -q "ingress-operator"; then
    warn "Console TLS: Self-signed (run configure-letsencrypt-certs.sh for LE cert)"
fi

# ─── 9. SUMMARY ──────────────────────────────────────────────────────────────
echo ""
echo "============================================="
echo " Validation Summary"
echo "============================================="
echo -e "  ${GREEN}PASS${NC}: $PASS"
echo -e "  ${YELLOW}WARN${NC}: $WARN"
echo -e "  ${RED}FAIL${NC}: $FAIL"
echo ""

if [ "$FAIL" -gt 0 ]; then
    echo -e "${RED}❌ Cluster has validation failures — review above.${NC}"
    echo "   Reference: hack/skills/deploy-cluster-kvm/SKILL.md (Lessons Learned)"
    exit 2
elif [ "$WARN" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Cluster has warnings — review above.${NC}"
    exit 1
else
    echo -e "${GREEN}✅ All checks passed — cluster is healthy.${NC}"
    exit 0
fi
