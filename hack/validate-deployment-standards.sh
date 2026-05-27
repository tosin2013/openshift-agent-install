#!/bin/bash
set -e

# OpenShift Deployment Standards Validator (LLM-Powered)
# Validates manifests against version-specific deployment patterns
#
# Usage: ./hack/validate-deployment-standards.sh <manifest-dir> <ocp-version> [--create-issue]
# Example: ./hack/validate-deployment-standards.sh ~/generated_assets/sno-disconnected-4.20 4.20
# Example: ./hack/validate-deployment-standards.sh ~/generated_assets/ha-4.21 4.21 --create-issue

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$SCRIPT_DIR/.."

# Load API key from env file if it exists
if [ -f "$HOME/env" ]; then
    source "$HOME/env"
fi

# Configuration
LITELLM_ENDPOINT="https://litellm-prod.apps.maas.redhatworkshops.io/v1/chat/completions"
LITELLM_MODEL="granite-3-2-8b-instruct"

# Argument validation
if [ $# -lt 2 ]; then
    echo -e "${RED}Usage: $0 <manifest-dir> <ocp-version> [--create-issue]${NC}"
    echo ""
    echo "Example: $0 ~/generated_assets/sno-disconnected-4.20 4.20"
    echo "Example: $0 ~/generated_assets/ha-4.21-disconnected 4.21 --create-issue"
    exit 1
fi

MANIFEST_DIR=$1
OCP_VERSION=$2
CREATE_ISSUE=${3:-""}

# Validate manifest directory exists
if [ ! -d "$MANIFEST_DIR" ]; then
    echo -e "${RED}❌ Manifest directory not found: $MANIFEST_DIR${NC}"
    exit 1
fi

INSTALL_CONFIG="$MANIFEST_DIR/install-config.yaml"
if [ ! -f "$INSTALL_CONFIG" ]; then
    echo -e "${RED}❌ install-config.yaml not found in $MANIFEST_DIR${NC}"
    exit 1
fi

echo "=================================================================="
echo "LLM-Powered Deployment Standards Validation"
echo "=================================================================="
echo "Manifest Directory: $MANIFEST_DIR"
echo "OpenShift Version:  $OCP_VERSION"
echo "=================================================================="
echo ""

# Function to call LLM API
call_llm() {
    local prompt="$1"
    local temp="${2:-0.2}"

    if [ -z "$LITELLM_API_KEY" ]; then
        echo -e "${YELLOW}⚠️  LITELLM_API_KEY not set - cannot perform LLM validation${NC}"
        return 1
    fi

    # Escape prompt for JSON
    local escaped_prompt=$(echo "$prompt" | jq -Rs .)

    # Call LiteLLM API
    local response=$(curl -s -X POST "$LITELLM_ENDPOINT" \
        -H "Authorization: Bearer $LITELLM_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"$LITELLM_MODEL\",
            \"messages\": [
                {
                    \"role\": \"system\",
                    \"content\": \"You are an OpenShift deployment expert. Validate configurations against version-specific deployment standards.\"
                },
                {
                    \"role\": \"user\",
                    \"content\": $escaped_prompt
                }
            ],
            \"temperature\": $temp
        }" 2>&1)

    # Check for errors
    if echo "$response" | jq -e '.error' > /dev/null 2>&1; then
        echo -e "${RED}❌ LLM API Error:${NC}"
        echo "$response" | jq -r '.error.message // .error'
        return 1
    fi

    # Extract response
    echo "$response" | jq -r '.choices[0].message.content // empty'
}

echo -e "${BLUE}Analyzing manifest configuration...${NC}"

# Auto-detect deployment type from manifest
HAS_IMAGE_DIGEST_SOURCES=$(grep -q "imageDigestSources" "$INSTALL_CONFIG" 2>/dev/null && echo "true" || echo "false")
HAS_IMAGE_CONTENT_SOURCES=$(grep -q "imageContentSources" "$INSTALL_CONFIG" 2>/dev/null && echo "true" || echo "false")
HAS_IMAGE_MIRROR_CONFIG=$([ -f "$MANIFEST_DIR/image-mirror-config.yaml" ] && echo "true" || echo "false")
HAS_PROXY=$(grep -q "httpProxy:" "$INSTALL_CONFIG" 2>/dev/null && echo "true" || echo "false")
HAS_DISCONNECTED=$(grep -q "additionalTrustBundle:" "$INSTALL_CONFIG" 2>/dev/null && echo "true" || echo "false")
NETWORK_TYPE=$(grep "networkType:" "$INSTALL_CONFIG" 2>/dev/null | awk '{print $2}' | tr -d '"' || echo "unknown")
CONTROL_PLANE_REPLICAS=$(grep -A 10 "^controlPlane:" "$INSTALL_CONFIG" | grep "replicas:" | head -1 | awk '{print $2}' || echo "unknown")
WORKER_REPLICAS=$(grep -A 10 "^compute:" "$INSTALL_CONFIG" | grep "replicas:" | head -1 | awk '{print $2}' || echo "0")
PLATFORM_TYPE=$(grep -A 1 "^platform:" "$INSTALL_CONFIG" | tail -1 | awk '{print $1}' | tr -d ':' || echo "unknown")

# Detect deployment topology
if [ "$CONTROL_PLANE_REPLICAS" = "1" ] && [ "$WORKER_REPLICAS" = "0" ]; then
    DEPLOYMENT_TOPOLOGY="SNO"
elif [ "$CONTROL_PLANE_REPLICAS" = "3" ] && [ "$WORKER_REPLICAS" = "0" ]; then
    DEPLOYMENT_TOPOLOGY="3-NODE COMPACT"
elif [ "$CONTROL_PLANE_REPLICAS" = "3" ] && [ "$WORKER_REPLICAS" -gt 0 ]; then
    DEPLOYMENT_TOPOLOGY="HA"
else
    DEPLOYMENT_TOPOLOGY="CUSTOM"
fi

# Detect connectivity type
# Disconnected if ANY of these conditions are true:
# - additionalTrustBundle present (mirror registry CA)
# - imageDigestSources present (4.19 transitional API)
# - imageContentSources present (deprecated but still indicates mirror)
# - image-mirror-config.yaml exists (4.20+ standalone manifest)
if [ "$HAS_DISCONNECTED" = "true" ] || \
   [ "$HAS_IMAGE_DIGEST_SOURCES" = "true" ] || \
   [ "$HAS_IMAGE_CONTENT_SOURCES" = "true" ] || \
   [ "$HAS_IMAGE_MIRROR_CONFIG" = "true" ]; then
    CONNECTIVITY="DISCONNECTED"
elif [ "$HAS_PROXY" = "true" ]; then
    CONNECTIVITY="PROXY"
else
    CONNECTIVITY="CONNECTED"
fi

FULL_DEPLOYMENT_TYPE="$DEPLOYMENT_TOPOLOGY ($CONNECTIVITY)"

echo "  Deployment Type: $FULL_DEPLOYMENT_TYPE"
echo "  Platform:        $PLATFORM_TYPE"
echo "  Network Type:    $NETWORK_TYPE"
echo "  Control Planes:  $CONTROL_PLANE_REPLICAS"
echo "  Workers:         $WORKER_REPLICAS"
echo ""

# Load deployment standards for this version
STANDARDS_FILE="docs/deployment-standards-${OCP_VERSION}.md"
if [ ! -f "$STANDARDS_FILE" ]; then
    echo -e "${YELLOW}⚠️  Standards file not found: $STANDARDS_FILE${NC}"
    STANDARDS_CONTENT="No version-specific standards available for OpenShift ${OCP_VERSION}."
else
    STANDARDS_CONTENT=$(cat "$STANDARDS_FILE")
fi

# Build LLM validation prompt
read -r -d '' PROMPT << EOM || true
Validate this OpenShift $OCP_VERSION deployment configuration against deployment standards.

**Deployment Type Detected:** $FULL_DEPLOYMENT_TYPE
- Topology: $DEPLOYMENT_TOPOLOGY
- Connectivity: $CONNECTIVITY
- Platform: $PLATFORM_TYPE

**Generated Manifests:**
- imageDigestSources in install-config.yaml: $HAS_IMAGE_DIGEST_SOURCES
- imageContentSources in install-config.yaml: $HAS_IMAGE_CONTENT_SOURCES
- Standalone image-mirror-config.yaml exists: $HAS_IMAGE_MIRROR_CONFIG
- Proxy configured: $HAS_PROXY
- additionalTrustBundle present: $HAS_DISCONNECTED
- networkType: $NETWORK_TYPE
- Control plane replicas: $CONTROL_PLANE_REPLICAS
- Worker replicas: $WORKER_REPLICAS

**Standards for OCP $OCP_VERSION:**
$STANDARDS_CONTENT

**Validation Required:**
1. Does this $FULL_DEPLOYMENT_TYPE configuration comply with OCP $OCP_VERSION standards?
2. Are there any deprecated API usages for this deployment type?
3. Are there deployment type-specific issues? (e.g., SNO using separate VIPs, HA using platform: none)
4. What changes are needed to make it compliant?

**Output Format - Provide structured report:**
[PASS/FAIL] Image Registry Configuration
- (explanation if FAIL)

[PASS/FAIL] Network Configuration
- (explanation if FAIL)

[PASS/FAIL] Platform Configuration
- (explanation if FAIL)

[PASS/FAIL] Deployment Topology
- (explanation if FAIL)

[PASS/FAIL] Connectivity Requirements
- (explanation if FAIL)

For each FAIL, provide:
- Issue: (what's wrong)
- Remediation: (how to fix)
- Severity: (CRITICAL/WARNING/INFO)

**Summary:**
Overall Status: PASS or FAIL
EOM

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}LLM Validation (powered by $LITELLM_MODEL)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Call LLM for validation
LLM_RESPONSE=$(call_llm "$PROMPT")

if [ $? -eq 0 ] && [ -n "$LLM_RESPONSE" ]; then
    echo "$LLM_RESPONSE"
    echo ""

    # Save validation report
    EXAMPLE_NAME=$(basename "$MANIFEST_DIR")
    REPORT_FILE="generated_assets/validation-report-${EXAMPLE_NAME}-${OCP_VERSION}.txt"
    mkdir -p "generated_assets"

    {
        echo "=================================================================="
        echo "OpenShift $OCP_VERSION Deployment Standards Validation"
        echo "=================================================================="
        echo "Manifest Directory: $MANIFEST_DIR"
        echo "Deployment Type:    $FULL_DEPLOYMENT_TYPE"
        echo "Validated:          $(date)"
        echo "=================================================================="
        echo ""
        echo "$LLM_RESPONSE"
    } > "$REPORT_FILE"

    echo -e "${GREEN}✓ Validation report saved to: $REPORT_FILE${NC}"

    # Create GitHub issue if requested and FAILs found
    if [ "$CREATE_ISSUE" = "--create-issue" ] && echo "$LLM_RESPONSE" | grep -q "FAIL"; then
        echo ""
        echo -e "${BLUE}Creating GitHub issue for deployment standards violations...${NC}"

        # Extract CRITICAL and WARNING issues
        CRITICAL_ISSUES=$(echo "$LLM_RESPONSE" | grep -A 3 "CRITICAL" || echo "None detected")
        WARNING_ISSUES=$(echo "$LLM_RESPONSE" | grep -A 3 "WARNING" || echo "None detected")

        # Create issue with LLM-generated content
        if command -v gh &> /dev/null; then
            gh issue create \
                --title "Deployment Standards Violation: $EXAMPLE_NAME (OCP $OCP_VERSION)" \
                --label "deployment-standards,automated,llm-generated" \
                --body "## Automated Validation Report

**Deployment Type:** $FULL_DEPLOYMENT_TYPE
**OpenShift Version:** $OCP_VERSION
**Manifest Directory:** \`$MANIFEST_DIR\`
**Generated:** $(date)

---

## LLM Validation Results

\`\`\`
$LLM_RESPONSE
\`\`\`

---

## Critical Issues

\`\`\`
$CRITICAL_ISSUES
\`\`\`

## Warnings

\`\`\`
$WARNING_ISSUES
\`\`\`

---

**Automated by:** \`hack/validate-deployment-standards.sh\`
**Standards Reference:** \`docs/deployment-standards-$OCP_VERSION.md\`
**Model:** $LITELLM_MODEL

**Remediation Steps:**
Review the LLM validation output above for specific remediation guidance.
" && echo -e "${GREEN}✅ GitHub issue created successfully${NC}" || echo -e "${RED}❌ Failed to create GitHub issue${NC}"
        else
            echo -e "${YELLOW}⚠️  gh CLI not installed, skipping issue creation${NC}"
        fi
    fi

    # Exit with failure if any FAIL found
    if echo "$LLM_RESPONSE" | grep -q "FAIL"; then
        echo ""
        echo -e "${RED}❌ Deployment standards validation FAILED${NC}"
        exit 1
    else
        echo ""
        echo -e "${GREEN}✓ All deployment standards checks PASSED${NC}"
        exit 0
    fi
else
    # Fallback validation (basic checks without LLM)
    echo -e "${YELLOW}⚠️  LLM validation unavailable, performing basic checks:${NC}"
    echo ""

    FAIL_COUNT=0

    # Basic check: imageContentSources deprecated in 4.20+
    if [ "$HAS_IMAGE_CONTENT_SOURCES" = "true" ] && [[ "$OCP_VERSION" > "4.19" ]]; then
        echo -e "${RED}❌ imageContentSources found in install-config.yaml (deprecated in 4.20+)${NC}"
        ((FAIL_COUNT++))
    fi

    # Basic check: OpenShiftSDN removed in 4.21+
    if [ "$NETWORK_TYPE" = "OpenShiftSDN" ] && [[ "$OCP_VERSION" > "4.20" ]]; then
        echo -e "${RED}❌ OpenShiftSDN not supported in 4.21+ (use OVNKubernetes)${NC}"
        ((FAIL_COUNT++))
    fi

    # Basic check: Disconnected should have image mirror config in 4.20+
    if [ "$HAS_DISCONNECTED" = "true" ] && [[ "$OCP_VERSION" > "4.19" ]] && [ "$HAS_IMAGE_MIRROR_CONFIG" = "false" ]; then
        echo -e "${YELLOW}⚠️  Disconnected deployment missing image-mirror-config.yaml (recommended for 4.20+)${NC}"
    fi

    if [ $FAIL_COUNT -eq 0 ]; then
        echo -e "${GREEN}✓ Basic validation checks passed${NC}"
        exit 0
    else
        echo -e "${RED}❌ $FAIL_COUNT validation checks failed${NC}"
        exit 1
    fi
fi
