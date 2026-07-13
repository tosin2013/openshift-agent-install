#!/bin/bash
# verify-dns-resolution.sh - Verify DNS resolution for OpenShift cluster
#
# This script verifies that DNS is properly configured for an OpenShift cluster
# by testing resolution of API and apps wildcard domains.
#
# Usage: ./verify-dns-resolution.sh <cluster-config-yml>
# Example: ./verify-dns-resolution.sh examples/sno-4.20-standard/cluster.yml

set -e

CLUSTER_CONFIG="${1:-}"

if [ -z "$CLUSTER_CONFIG" ]; then
    echo "❌ Usage: $0 <cluster-config-yml>"
    echo "   Example: $0 examples/sno-4.20-standard/cluster.yml"
    exit 1
fi

if [ ! -f "$CLUSTER_CONFIG" ]; then
    echo "❌ Error: Cluster config not found: $CLUSTER_CONFIG"
    exit 1
fi

# Extract cluster details
CLUSTER_NAME=$(grep "^cluster_name:" "$CLUSTER_CONFIG" | awk '{print $2}' | tr -d '"')
BASE_DOMAIN=$(grep "^base_domain:" "$CLUSTER_CONFIG" | awk '{print $2}' | tr -d '"')
API_VIP=$(grep -A 1 "^api_vips:" "$CLUSTER_CONFIG" | tail -1 | awk '{print $2}' | tr -d '"-')

if [ -z "$CLUSTER_NAME" ] || [ -z "$BASE_DOMAIN" ]; then
    echo "❌ Error: Could not extract cluster_name or base_domain from $CLUSTER_CONFIG"
    exit 1
fi

CLUSTER_DOMAIN="${CLUSTER_NAME}.${BASE_DOMAIN}"

echo "╔═══════════════════════════════════════════════════════╗"
echo "║  DNS Resolution Verification                          ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""
echo "Cluster: $CLUSTER_DOMAIN"
echo "API VIP: $API_VIP"
echo ""

# Test DNS resolution
FAILED=0

echo "Testing DNS resolution..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Test 1: API endpoint
echo -n "1. API endpoint (api.$CLUSTER_DOMAIN): "
API_RESOLVED=$(dig +short @127.0.0.1 api.$CLUSTER_DOMAIN 2>/dev/null | tail -1)
if [ -n "$API_RESOLVED" ]; then
    if [ "$API_RESOLVED" = "$API_VIP" ]; then
        echo "✅ $API_RESOLVED"
    else
        echo "⚠️  $API_RESOLVED (expected: $API_VIP)"
        FAILED=$((FAILED + 1))
    fi
else
    echo "❌ NOT RESOLVED"
    FAILED=$((FAILED + 1))
fi

# Test 2: API-int endpoint
echo -n "2. Internal API (api-int.$CLUSTER_DOMAIN): "
API_INT_RESOLVED=$(dig +short @127.0.0.1 api-int.$CLUSTER_DOMAIN 2>/dev/null | tail -1)
if [ -n "$API_INT_RESOLVED" ]; then
    if [ "$API_INT_RESOLVED" = "$API_VIP" ]; then
        echo "✅ $API_INT_RESOLVED"
    else
        echo "⚠️  $API_INT_RESOLVED (expected: $API_VIP)"
        FAILED=$((FAILED + 1))
    fi
else
    echo "❌ NOT RESOLVED"
    FAILED=$((FAILED + 1))
fi

# Test 3: Apps wildcard (console)
echo -n "3. Console (console-openshift-console.apps.$CLUSTER_DOMAIN): "
CONSOLE_RESOLVED=$(dig +short @127.0.0.1 console-openshift-console.apps.$CLUSTER_DOMAIN 2>/dev/null | tail -1)
if [ -n "$CONSOLE_RESOLVED" ]; then
    echo "✅ $CONSOLE_RESOLVED"
else
    echo "❌ NOT RESOLVED"
    FAILED=$((FAILED + 1))
fi

# Test 4: Apps wildcard (oauth)
echo -n "4. OAuth (oauth-openshift.apps.$CLUSTER_DOMAIN): "
OAUTH_RESOLVED=$(dig +short @127.0.0.1 oauth-openshift.apps.$CLUSTER_DOMAIN 2>/dev/null | tail -1)
if [ -n "$OAUTH_RESOLVED" ]; then
    echo "✅ $OAUTH_RESOLVED"
else
    echo "❌ NOT RESOLVED"
    FAILED=$((FAILED + 1))
fi

# Test 5: Generic apps wildcard
echo -n "5. Generic apps (test.apps.$CLUSTER_DOMAIN): "
TEST_RESOLVED=$(dig +short @127.0.0.1 test.apps.$CLUSTER_DOMAIN 2>/dev/null | tail -1)
if [ -n "$TEST_RESOLVED" ]; then
    echo "✅ $TEST_RESOLVED"
else
    echo "❌ NOT RESOLVED"
    FAILED=$((FAILED + 1))
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $FAILED -eq 0 ]; then
    echo "✅ All DNS tests passed!"
    echo ""
    echo "DNS Configuration:"
    sudo cat /etc/dnsmasq.d/openshift.conf 2>/dev/null | grep "$CLUSTER_NAME" || echo "(No entries found in dnsmasq)"
    exit 0
else
    echo "❌ $FAILED DNS test(s) failed"
    echo ""
    echo "Troubleshooting:"
    echo "1. Check if DNS entries exist:"
    echo "   sudo cat /etc/dnsmasq.d/openshift.conf | grep \"$CLUSTER_NAME\""
    echo ""
    echo "2. Add DNS entries if missing:"
    echo "   sudo ./hack/configure-dnsmasq-entries.sh add $CLUSTER_CONFIG"
    echo ""
    echo "3. Restart dnsmasq:"
    echo "   sudo systemctl restart dnsmasq"
    echo ""
    echo "4. Re-run this test:"
    echo "   $0 $CLUSTER_CONFIG"
    exit 1
fi
