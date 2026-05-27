#!/bin/bash
set -e

# OpenShift Version Manifest Comparison Tool (LLM-Powered)
# Compares manifests across OpenShift versions and provides intelligent analysis
#
# Usage: ./hack/compare-version-manifests.sh <base-version> <target-version> <example-name>
# Example: ./hack/compare-version-manifests.sh 4.19 4.20 sno-disconnected

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
GENERATED_ASSET_PATH="${GENERATED_ASSET_PATH:-${HOME}/generated_assets}"
VERSION_COMPARE_DIR="${GENERATED_ASSET_PATH}/version-compare"
LITELLM_ENDPOINT="https://litellm-prod.apps.maas.redhatworkshops.io/v1/chat/completions"
LITELLM_MODEL="granite-3-2-8b-instruct"

# Argument validation
if [ $# -ne 3 ]; then
    echo -e "${RED}Usage: $0 <base-version> <target-version> <example-name>${NC}"
    echo ""
    echo "Example: $0 4.19 4.20 sno-disconnected"
    exit 1
fi

BASE_VERSION=$1
TARGET_VERSION=$2
EXAMPLE_NAME=$3

BASE_DIR="${VERSION_COMPARE_DIR}/${EXAMPLE_NAME}-${BASE_VERSION}"
TARGET_DIR="${VERSION_COMPARE_DIR}/${EXAMPLE_NAME}-${TARGET_VERSION}"

# Validate directories exist
if [ ! -d "$BASE_DIR" ]; then
    echo -e "${RED}❌ Base version directory not found: $BASE_DIR${NC}"
    echo "Run: ./hack/generate-version-manifests.sh $EXAMPLE_NAME \"$BASE_VERSION\""
    exit 1
fi

if [ ! -d "$TARGET_DIR" ]; then
    echo -e "${RED}❌ Target version directory not found: $TARGET_DIR${NC}"
    echo "Run: ./hack/generate-version-manifests.sh $EXAMPLE_NAME \"$TARGET_VERSION\""
    exit 1
fi

echo "=================================================================="
echo "LLM-Powered Version Comparison: OCP $BASE_VERSION → $TARGET_VERSION"
echo "=================================================================="
echo "Example: $EXAMPLE_NAME"
echo "Base:    $BASE_DIR"
echo "Target:  $TARGET_DIR"
echo "=================================================================="
echo ""

# Function to call LLM API
call_llm() {
    local prompt="$1"
    local temp="${2:-0.2}"

    if [ -z "$LITELLM_API_KEY" ]; then
        echo -e "${YELLOW}⚠️  LITELLM_API_KEY not set - falling back to basic diff${NC}"
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
                    \"content\": \"You are an OpenShift deployment expert. Analyze manifest differences and validate against version-specific standards.\"
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

# Generate unified diff for install-config.yaml
echo -e "${BLUE}Comparing install-config.yaml...${NC}"
if [ -f "$BASE_DIR/install-config.yaml" ] && [ -f "$TARGET_DIR/install-config.yaml" ]; then
    INSTALL_CONFIG_DIFF=$(diff -u "$BASE_DIR/install-config.yaml" "$TARGET_DIR/install-config.yaml" || true)

    if [ -z "$INSTALL_CONFIG_DIFF" ]; then
        echo -e "${GREEN}✓ No changes in install-config.yaml${NC}"
    else
        echo -e "${YELLOW}Changes detected in install-config.yaml${NC}"
    fi
else
    INSTALL_CONFIG_DIFF="One or both install-config.yaml files not found"
    echo -e "${YELLOW}⚠️  $INSTALL_CONFIG_DIFF${NC}"
fi

# Check for additional manifests
echo ""
echo -e "${BLUE}Checking for version-specific manifests...${NC}"

BASE_HAS_IMAGE_MIRROR=$([ -f "$BASE_DIR/image-mirror-config.yaml" ] && echo "true" || echo "false")
TARGET_HAS_IMAGE_MIRROR=$([ -f "$TARGET_DIR/image-mirror-config.yaml" ] && echo "true" || echo "false")

echo "  Base ($BASE_VERSION) has image-mirror-config.yaml: $BASE_HAS_IMAGE_MIRROR"
echo "  Target ($TARGET_VERSION) has image-mirror-config.yaml: $TARGET_HAS_IMAGE_MIRROR"

# Load deployment standards for context
STANDARDS_4_19=""
STANDARDS_4_20=""
STANDARDS_4_21=""

if [ -f "docs/deployment-standards-4.19.md" ]; then
    STANDARDS_4_19=$(cat docs/deployment-standards-4.19.md)
fi

if [ -f "docs/deployment-standards-4.20.md" ]; then
    STANDARDS_4_20=$(cat docs/deployment-standards-4.20.md)
fi

if [ -f "docs/deployment-standards-4.21.md" ]; then
    STANDARDS_4_21=$(cat docs/deployment-standards-4.21.md)
fi

# Build LLM prompt
read -r -d '' PROMPT << EOM || true
You are an OpenShift deployment expert. Analyze the manifest differences between OCP $BASE_VERSION and $TARGET_VERSION.

**Deployment Pattern Standards by Version:**

**OpenShift 4.19:**
- imageDigestSources in install-config.yaml (transitional API)
- OpenShiftSDN supported (deprecated)
- ImageContentSourcePolicy deprecated

**OpenShift 4.20+:**
- NO image sources in install-config.yaml
- Standalone ImageDigestMirrorSet manifest (image-mirror-config.yaml)
- OpenShiftSDN deprecated (warning only)
- OVNKubernetes strongly recommended

**OpenShift 4.21+:**
- ImageDigestMirrorSet mandatory for disconnected
- OpenShiftSDN removed completely
- OVNKubernetes mandatory (networkType must be OVNKubernetes)

**Manifest Comparison Data:**

install-config.yaml diff:
\`\`\`diff
$INSTALL_CONFIG_DIFF
\`\`\`

Additional manifests:
- Base ($BASE_VERSION) has image-mirror-config.yaml: $BASE_HAS_IMAGE_MIRROR
- Target ($TARGET_VERSION) has image-mirror-config.yaml: $TARGET_HAS_IMAGE_MIRROR

**Analysis Required:**
1. What changed between $BASE_VERSION and $TARGET_VERSION?
2. Are these changes expected per the version standards above?
3. Are there any violations of deployment pattern standards?
4. What risks exist if these manifests are used for the wrong version?

Provide a structured report with:
- [PASS/FAIL] for each validation check
- Explanation of changes
- Remediation steps if any FAIL
EOM

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}LLM Analysis (powered by $LITELLM_MODEL)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Call LLM for analysis
LLM_RESPONSE=$(call_llm "$PROMPT")

if [ $? -eq 0 ] && [ -n "$LLM_RESPONSE" ]; then
    echo "$LLM_RESPONSE"

    # Save report to file
    REPORT_FILE="${GENERATED_ASSET_PATH}/comparison-${EXAMPLE_NAME}-${BASE_VERSION}-to-${TARGET_VERSION}.txt"
    echo "$LLM_RESPONSE" > "$REPORT_FILE"
    echo ""
    echo -e "${GREEN}✓ Report saved to: $REPORT_FILE${NC}"

    # Check for failures
    if echo "$LLM_RESPONSE" | grep -q "FAIL"; then
        echo ""
        echo -e "${RED}❌ Compatibility issues detected${NC}"
        exit 1
    else
        echo ""
        echo -e "${GREEN}✓ All version compatibility checks passed${NC}"
        exit 0
    fi
else
    # Fallback to basic diff
    echo -e "${YELLOW}⚠️  LLM analysis unavailable, showing basic diff:${NC}"
    echo ""
    echo "$INSTALL_CONFIG_DIFF" | grep -E "imageContent|imageDigest|networkType|^\+|^-" || echo "(No significant changes detected)"
    echo ""
    echo "Key differences:"
    echo "  - Base has image-mirror-config.yaml: $BASE_HAS_IMAGE_MIRROR"
    echo "  - Target has image-mirror-config.yaml: $TARGET_HAS_IMAGE_MIRROR"
    exit 0
fi
