#!/bin/bash
# validate-baremetal-env.sh - Pre-flight validation for bare metal OpenShift deployments
#
# Checks that a cluster configuration is ready to deploy to physical bare metal:
#   1. Required tools are installed
#   2. Cluster config files exist and are parseable
#   3. Corporate DNS records resolve for api.*, api-int.*, *.apps.*
#   4. VIPs are within the machine_network_cidr
#   5. BMC addresses are network-reachable (ping)
#   6. NMState networkConfig syntax is valid
#   7. SSH public key is readable
#   8. Pull secret exists
#
# Usage:
#   ./hack/validate-baremetal-env.sh <cluster-config-name>
#   SITE_CONFIG_DIR=site-config ./hack/validate-baremetal-env.sh my-cluster
#
# Environment Variables:
#   SITE_CONFIG_DIR   - Where cluster configs live (default: examples)
#   GENERATED_ASSET_PATH - Where ISOs go (default: ~/generated_assets)
#   DNS_SERVER        - DNS server to test against (auto-detected from cluster.yml)

set -e

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$SCRIPT_DIR/.."

# Configuration
SITE_CONFIG_DIR="${SITE_CONFIG_DIR:-examples}"
GENERATED_ASSET_PATH="${GENERATED_ASSET_PATH:-${HOME}/generated_assets}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0

# --- Helper Functions ---

print_section() {
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}$1${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

pass() {
    echo -e "${GREEN}  ✓ $1${NC}"
    PASS=$((PASS + 1))
}

fail() {
    echo -e "${RED}  ✗ $1${NC}"
    FAIL=$((FAIL + 1))
}

warn() {
    echo -e "${YELLOW}  ⚠ $1${NC}"
}

info() {
    echo -e "${BLUE}  → $1${NC}"
}

# Check if a command exists
cmd_exists() {
    type "$1" >/dev/null 2>&1
}

# --- Argument Validation ---

if [ -z "$1" ]; then
    echo "Usage: $0 <cluster-config-name>"
    echo "       SITE_CONFIG_DIR=site-config $0 my-production-cluster"
    exit 1
fi

CLUSTER_CONFIG_NAME="$1"
CLUSTER_DIR="${SITE_CONFIG_DIR}/${CLUSTER_CONFIG_NAME}"
CLUSTER_YML="${CLUSTER_DIR}/cluster.yml"
NODES_YML="${CLUSTER_DIR}/nodes.yml"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Bare Metal Pre-flight Validation                        ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
info "Cluster config: ${CLUSTER_DIR}"
info "SITE_CONFIG_DIR: ${SITE_CONFIG_DIR}"
info "GENERATED_ASSET_PATH: ${GENERATED_ASSET_PATH}"

# --- Section 1: Required Tools ---

print_section "1. Required Tools"

for tool in dig ipmitool yq nmstatectl openssl; do
    if cmd_exists "$tool"; then
        pass "$tool is installed"
    else
        fail "$tool is not installed — install it before deploying"
    fi
done

if [ -f "./bin/openshift-install" ]; then
    pass "bin/openshift-install found"
else
    warn "bin/openshift-install not found — run ./download-openshift-cli.sh"
fi

# --- Section 2: Config Files ---

print_section "2. Cluster Configuration Files"

if [ -f "$CLUSTER_YML" ]; then
    pass "cluster.yml exists: $CLUSTER_YML"
else
    fail "cluster.yml not found: $CLUSTER_YML"
    echo ""
    echo -e "${RED}Cannot continue without cluster.yml. Exiting.${NC}"
    exit 1
fi

if [ -f "$NODES_YML" ]; then
    pass "nodes.yml exists: $NODES_YML"
else
    fail "nodes.yml not found: $NODES_YML"
    echo ""
    echo -e "${RED}Cannot continue without nodes.yml. Exiting.${NC}"
    exit 1
fi

# Extract values
CLUSTER_NAME=$(grep "^cluster_name:" "$CLUSTER_YML" | awk '{print $2}' | tr -d '"')
BASE_DOMAIN=$(grep "^base_domain:" "$CLUSTER_YML" | awk '{print $2}' | tr -d '"')
PLATFORM_TYPE=$(grep "^platform_type:" "$CLUSTER_YML" | awk '{print $2}' | tr -d '"')
API_VIP=$(grep -A1 "^api_vips:" "$CLUSTER_YML" | tail -1 | awk '{print $2}' | tr -d '- "')
APP_VIP=$(grep -A1 "^app_vips:" "$CLUSTER_YML" | tail -1 | awk '{print $2}' | tr -d '- "')
MACHINE_CIDR=$(grep -A1 "^machine_network_cidrs:" "$CLUSTER_YML" | tail -1 | awk '{print $2}' | tr -d '- "')
PULL_SECRET_PATH=$(grep "^pull_secret_path:" "$CLUSTER_YML" | awk '{print $2}' | tr -d '"' | sed 's|~|'"$HOME"'|')
DNS_SERVER_YML=$(grep -A1 "^dns_servers:" "$CLUSTER_YML" | tail -1 | awk '{print $2}' | tr -d '- "')
OCP_VERSION=$(grep "^ocp_version:" "$CLUSTER_YML" | awk '{print $2}' | tr -d '"')
RENDEZVOUS_IP=$(grep "^rendezvous_ip:" "$CLUSTER_YML" | awk '{print $2}' | tr -d '"')

if [ -n "$CLUSTER_NAME" ]; then
    pass "cluster_name: $CLUSTER_NAME"
else
    fail "cluster_name not found in cluster.yml"
fi

if [ -n "$BASE_DOMAIN" ]; then
    pass "base_domain: $BASE_DOMAIN"
else
    fail "base_domain not found in cluster.yml"
fi

if [ "$PLATFORM_TYPE" = "baremetal" ]; then
    pass "platform_type: baremetal (correct for HA bare metal)"
elif [ "$PLATFORM_TYPE" = "none" ]; then
    warn "platform_type: none — only valid for SNO deployments"
else
    warn "platform_type: ${PLATFORM_TYPE:-not set}"
fi

if [ -n "$API_VIP" ]; then
    pass "api_vip: $API_VIP"
else
    fail "api_vips not found in cluster.yml"
fi

if [ -n "$APP_VIP" ]; then
    pass "app_vip: $APP_VIP"
else
    fail "app_vips not found in cluster.yml"
fi

if [ -n "$OCP_VERSION" ]; then
    pass "ocp_version: $OCP_VERSION"
else
    warn "ocp_version not set in cluster.yml"
fi

if [ -n "$RENDEZVOUS_IP" ]; then
    pass "rendezvous_ip: $RENDEZVOUS_IP"
else
    warn "rendezvous_ip not set — installer will auto-select"
fi

# Pull secret
PULL_SECRET_PATH_EXPANDED="${PULL_SECRET_PATH:-$HOME/pull-secret.json}"
if [ -f "$PULL_SECRET_PATH_EXPANDED" ]; then
    pass "Pull secret found: $PULL_SECRET_PATH_EXPANDED"
else
    fail "Pull secret not found at: $PULL_SECRET_PATH_EXPANDED"
    info "Download from https://console.redhat.com/openshift/downloads#tool-pull-secret"
fi

# SSH key
SSH_KEY_PATH=$(grep "ssh_public_key_path:" "$CLUSTER_YML" 2>/dev/null | awk '{print $2}' | tr -d '"' | sed 's|~|'"$HOME"'|' || true)
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_rsa.pub}"
if [ -f "$SSH_KEY_PATH" ]; then
    pass "SSH public key found: $SSH_KEY_PATH"
else
    warn "SSH public key not found at: $SSH_KEY_PATH"
    info "Generate with: ssh-keygen -t ed25519 -f ~/.ssh/id_rsa"
fi

# --- Section 3: DNS Verification ---

print_section "3. DNS Verification"

# Use DNS_SERVER env var, then cluster.yml, then system default
DNS_SERVER="${DNS_SERVER:-${DNS_SERVER_YML}}"
CLUSTER_FQDN="${CLUSTER_NAME}.${BASE_DOMAIN}"

if [ -n "$DNS_SERVER" ]; then
    info "Testing against DNS server: $DNS_SERVER"
    DNS_OPTS="@${DNS_SERVER}"
else
    info "No DNS_SERVER set — testing against system resolver"
    DNS_OPTS=""
fi

check_dns() {
    local record="$1"
    local expected="$2"
    local resolved
    resolved=$(dig +short ${DNS_OPTS} "$record" 2>/dev/null | head -1)
    if [ -n "$resolved" ]; then
        if [ -n "$expected" ] && [ "$resolved" != "$expected" ]; then
            warn "$record → $resolved (expected $expected)"
        else
            pass "$record → $resolved"
        fi
    else
        fail "$record → NOT RESOLVED"
        if [ -n "$DNS_SERVER" ]; then
            info "Register this record in your DNS server ($DNS_SERVER)"
        fi
    fi
}

check_dns "api.${CLUSTER_FQDN}" "$API_VIP"
check_dns "api-int.${CLUSTER_FQDN}" "$API_VIP"
check_dns "console-openshift-console.apps.${CLUSTER_FQDN}" "$APP_VIP"
check_dns "test.apps.${CLUSTER_FQDN}" "$APP_VIP"

# --- Section 4: VIP in Machine CIDR ---

print_section "4. VIP / CIDR Validation"

if [ -n "$MACHINE_CIDR" ] && [ -n "$API_VIP" ] && cmd_exists python3; then
    CIDR_CHECK=$(python3 -c "
import ipaddress, sys
try:
    net = ipaddress.ip_network('${MACHINE_CIDR}', strict=False)
    api = ipaddress.ip_address('${API_VIP}')
    app = ipaddress.ip_address('${APP_VIP}')
    ok = True
    if api not in net:
        print('API VIP ${API_VIP} is NOT in ${MACHINE_CIDR}')
        ok = False
    if app not in net:
        print('App VIP ${APP_VIP} is NOT in ${MACHINE_CIDR}')
        ok = False
    if ok:
        print('OK')
except Exception as e:
    print(f'ERROR: {e}')
" 2>/dev/null)
    if [ "$CIDR_CHECK" = "OK" ]; then
        pass "API VIP $API_VIP is within machine CIDR $MACHINE_CIDR"
        pass "App VIP $APP_VIP is within machine CIDR $MACHINE_CIDR"
    else
        fail "VIP CIDR check: $CIDR_CHECK"
        info "VIPs must be free IPs on the same subnet as cluster nodes"
    fi
else
    warn "Could not validate VIPs in CIDR (missing machine_network_cidrs or python3)"
fi

# --- Section 5: BMC Reachability ---

print_section "5. BMC Reachability"

if ! cmd_exists yq; then
    warn "yq not installed — skipping BMC reachability checks"
else
    BMC_COUNT=0
    BMC_FAIL=0

    while IFS= read -r bmc_address; do
        [ -z "$bmc_address" ] && continue
        [ "$bmc_address" = "null" ] && continue
        BMC_COUNT=$((BMC_COUNT + 1))

        # Strip scheme (redfish-virtualmedia://, ipmi://, redfish://)
        bmc_ip=$(echo "$bmc_address" | sed -E 's|^[a-z+:-]+//([^/]+).*|\1|')

        if ping -c 1 -W 3 "$bmc_ip" >/dev/null 2>&1; then
            pass "BMC reachable: $bmc_ip (from $bmc_address)"
        else
            fail "BMC NOT reachable: $bmc_ip (from $bmc_address)"
            BMC_FAIL=$((BMC_FAIL + 1))
        fi
    done < <(yq e '.nodes[].bmc.address // ""' "$NODES_YML" 2>/dev/null)

    if [ "$BMC_COUNT" -eq 0 ]; then
        warn "No bmc.address entries found in nodes.yml"
        info "Add bmc: blocks to nodes.yml for automated ISO delivery"
        info "See examples/baremetal-example/nodes.yml for commented examples"
    else
        info "$BMC_COUNT BMC address(es) checked, $BMC_FAIL unreachable"
    fi
fi

# --- Section 6: NMState Syntax ---

print_section "6. NMState networkConfig Syntax"

if cmd_exists nmstatectl; then
    # Extract networkConfig blocks from nodes.yml and validate
    TMPFILE=$(mktemp /tmp/nmstate-validate-XXXXXX.yml)
    trap "rm -f $TMPFILE" EXIT

    if cmd_exists yq; then
        yq e '.nodes[].networkConfig' "$NODES_YML" 2>/dev/null > "$TMPFILE" || true
        if [ -s "$TMPFILE" ] && grep -q "interfaces" "$TMPFILE" 2>/dev/null; then
            if nmstatectl gc "$TMPFILE" >/dev/null 2>&1; then
                pass "NMState networkConfig syntax is valid"
            else
                fail "NMState networkConfig has syntax errors:"
                nmstatectl gc "$TMPFILE" 2>&1 | head -10 | sed 's/^/    /'
                info "Fix networkConfig in nodes.yml and re-validate"
            fi
        else
            warn "No networkConfig blocks found in nodes.yml"
        fi
    else
        warn "yq not available — cannot extract networkConfig for validation"
    fi
else
    warn "nmstatectl not installed — skipping NMState validation"
    info "Install with: dnf install nmstate"
fi

# --- Section 7: Node Count ---

print_section "7. Node Count"

if cmd_exists yq; then
    MASTER_COUNT=$(yq e '[.nodes[] | select(.role == "master")] | length' "$NODES_YML" 2>/dev/null || echo 0)
    WORKER_COUNT=$(yq e '[.nodes[] | select(.role == "worker")] | length' "$NODES_YML" 2>/dev/null || echo 0)
    TOTAL_COUNT=$((MASTER_COUNT + WORKER_COUNT))

    info "Masters: $MASTER_COUNT  Workers: $WORKER_COUNT  Total: $TOTAL_COUNT"

    EXPECTED_MASTERS=$(grep "^control_plane_replicas:" "$NODES_YML" 2>/dev/null | awk '{print $2}' || echo "")
    EXPECTED_WORKERS=$(grep "^app_node_replicas:" "$NODES_YML" 2>/dev/null | awk '{print $2}' || echo "")

    if [ -n "$EXPECTED_MASTERS" ] && [ "$MASTER_COUNT" -ne "$EXPECTED_MASTERS" ]; then
        fail "Master count mismatch: nodes.yml has $MASTER_COUNT but control_plane_replicas=$EXPECTED_MASTERS"
    elif [ -n "$EXPECTED_MASTERS" ]; then
        pass "Master count matches control_plane_replicas: $MASTER_COUNT"
    fi

    if [ "$MASTER_COUNT" -eq 1 ]; then
        if [ "$PLATFORM_TYPE" != "none" ]; then
            warn "SNO (1 master) should use platform_type: none"
        else
            pass "SNO topology: 1 master with platform_type: none"
        fi
    elif [ "$MASTER_COUNT" -eq 3 ]; then
        if [ "$PLATFORM_TYPE" = "baremetal" ]; then
            pass "HA topology: 3 masters with platform_type: baremetal"
        else
            warn "HA with 3 masters should use platform_type: baremetal for VIP management"
        fi
    fi
fi

# --- Summary ---

print_section "Validation Summary"

TOTAL=$((PASS + FAIL))
echo ""
echo -e "  ${GREEN}Passed:${NC} $PASS / $TOTAL"
echo -e "  ${RED}Failed:${NC} $FAIL / $TOTAL"
echo ""

if [ "$FAIL" -eq 0 ]; then
    echo -e "${GREEN}✅ All checks passed — ready to generate ISO and deploy${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Generate ISO: export SITE_CONFIG_DIR=${SITE_CONFIG_DIR} && ./hack/create-iso.sh ${CLUSTER_CONFIG_NAME}"
    echo "  2. Deliver ISO: see docs/bare-metal-production-guide.md Phase 4"
    echo "  3. Monitor:     ./bin/openshift-install agent wait-for install-complete --dir ${GENERATED_ASSET_PATH}/${CLUSTER_NAME}/"
    exit 0
else
    echo -e "${RED}❌ $FAIL check(s) failed — resolve issues before deploying${NC}"
    echo ""
    echo "Reference documentation:"
    echo "  - Fork & Adapt Checklist:     docs/fork-and-adapt-checklist.md"
    echo "  - Corporate DNS Integration:  docs/corporate-dns-integration.md"
    echo "  - Bare Metal Production Guide: docs/bare-metal-production-guide.md"
    echo "  - BMC Management Guide:       docs/bmc-management.md"
    exit 1
fi
