#!/bin/bash
set -e

# OpenShift Version Manifest Generator
# Generates manifests for multiple OpenShift versions to enable version comparison
#
# Usage: ./hack/generate-version-manifests.sh <example-name> <version-list>
# Example: ./hack/generate-version-manifests.sh sno-disconnected "4.19 4.20 4.21"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$SCRIPT_DIR/.."

# Configuration
SITE_CONFIG_DIR="${SITE_CONFIG_DIR:-examples}"
GENERATED_ASSET_PATH="${GENERATED_ASSET_PATH:-${HOME}/generated_assets}"
VERSION_COMPARE_DIR="${GENERATED_ASSET_PATH}/version-compare"

# Argument validation
if [ $# -lt 2 ]; then
    echo -e "${RED}Usage: $0 <example-name> <version-list>${NC}"
    echo ""
    echo "Example: $0 sno-disconnected \"4.19 4.20 4.21\""
    echo ""
    echo "Available examples:"
    ls -1 "$SITE_CONFIG_DIR" | grep -v "^_" | sed 's/^/  - /'
    exit 1
fi

EXAMPLE_NAME=$1
shift
VERSION_LIST="$@"

# Validate example exists
if [ ! -d "${SITE_CONFIG_DIR}/${EXAMPLE_NAME}" ]; then
    echo -e "${RED}❌ Example '${EXAMPLE_NAME}' not found in ${SITE_CONFIG_DIR}/${NC}"
    echo ""
    echo "Available examples:"
    ls -1 "$SITE_CONFIG_DIR" | grep -v "^_" | sed 's/^/  - /'
    exit 1
fi

# Check required files
if [ ! -f "${SITE_CONFIG_DIR}/${EXAMPLE_NAME}/cluster.yml" ]; then
    echo -e "${RED}❌ cluster.yml not found in ${SITE_CONFIG_DIR}/${EXAMPLE_NAME}/${NC}"
    exit 1
fi

if [ ! -f "${SITE_CONFIG_DIR}/${EXAMPLE_NAME}/nodes.yml" ]; then
    echo -e "${RED}❌ nodes.yml not found in ${SITE_CONFIG_DIR}/${EXAMPLE_NAME}/${NC}"
    exit 1
fi

# Function to download OC CLI for specific version (with caching)
download_oc_cli() {
    local version=$1
    local cache_dir="$HOME/.cache/ocp-cli/$version"

    if [ -f "$cache_dir/oc" ]; then
        echo -e "${GREEN}✓ Using cached OC CLI $version${NC}"
        export PATH="$cache_dir:$PATH"
        return 0
    fi

    echo -e "${BLUE}Downloading OC CLI for version $version...${NC}"

    # Call download script with version argument
    if [ -x "./download-openshift-cli.sh" ]; then
        ./download-openshift-cli.sh "$version" || {
            echo -e "${YELLOW}⚠️  Failed to download OC CLI for $version, will use default${NC}"
            return 1
        }

        # Cache the downloaded CLI
        mkdir -p "$cache_dir"
        if [ -f "bin/oc" ]; then
            cp bin/oc "$cache_dir/"
            echo -e "${GREEN}✓ OC CLI $version cached${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  download-openshift-cli.sh not found, using system OC CLI${NC}"
        return 1
    fi
}

# Create version-compare directory
mkdir -p "$VERSION_COMPARE_DIR"

echo "=================================================================="
echo "OpenShift Version Manifest Generator"
echo "=================================================================="
echo "Example: $EXAMPLE_NAME"
echo "Versions: $VERSION_LIST"
echo "Output: $VERSION_COMPARE_DIR"
echo "=================================================================="
echo ""

# Generate manifests for each version
GENERATED_COUNT=0
FAILED_COUNT=0

for version in $VERSION_LIST; do
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Generating manifests for OpenShift ${version}${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Download/verify OC CLI for this version (optional, won't fail if unavailable)
    download_oc_cli "$version" || true

    # Set output directory
    OUTPUT_DIR="${VERSION_COMPARE_DIR}/${EXAMPLE_NAME}-${version}"
    mkdir -p "$OUTPUT_DIR"

    # Generate manifests with ocp_version override
    echo -e "${BLUE}Running Ansible playbook...${NC}"
    if ansible-playbook \
        -e "@${SITE_CONFIG_DIR}/${EXAMPLE_NAME}/cluster.yml" \
        -e "@${SITE_CONFIG_DIR}/${EXAMPLE_NAME}/nodes.yml" \
        -e "ocp_version=${version}" \
        -e "generated_asset_path=${VERSION_COMPARE_DIR}" \
        -e "cluster_name=${EXAMPLE_NAME}-${version}" \
        playbooks/create-manifests.yml 2>&1 | tee "${OUTPUT_DIR}/generation.log"; then

        # Move generated manifests to versioned directory
        if [ -d "${VERSION_COMPARE_DIR}/${EXAMPLE_NAME}-${version}" ]; then
            MANIFEST_COUNT=$(find "${OUTPUT_DIR}" -name "*.yaml" -o -name "*.yml" | wc -l)
            echo -e "${GREEN}✓ Generated ${MANIFEST_COUNT} manifests for OCP ${version}${NC}"
            echo -e "${GREEN}  Location: ${OUTPUT_DIR}${NC}"
            ((GENERATED_COUNT++))
        else
            echo -e "${RED}❌ Failed to generate manifests for OCP ${version}${NC}"
            ((FAILED_COUNT++))
        fi
    else
        echo -e "${RED}❌ Ansible playbook failed for OCP ${version}${NC}"
        ((FAILED_COUNT++))
    fi

    echo ""
done

# Summary
echo "=================================================================="
echo "Generation Summary"
echo "=================================================================="
echo -e "Total versions: $(echo $VERSION_LIST | wc -w)"
echo -e "${GREEN}✓ Successfully generated: $GENERATED_COUNT${NC}"
if [ $FAILED_COUNT -gt 0 ]; then
    echo -e "${RED}❌ Failed: $FAILED_COUNT${NC}"
fi
echo ""
echo "Next steps:"
echo "  1. Compare versions:"
echo "     ./hack/compare-version-manifests.sh <base-ver> <target-ver> $EXAMPLE_NAME"
echo ""
echo "  2. Validate deployment standards:"
echo "     ./hack/validate-deployment-standards.sh \\"
echo "       ${VERSION_COMPARE_DIR}/${EXAMPLE_NAME}-<version> <version>"
echo "=================================================================="

# Exit with error if any failures
if [ $FAILED_COUNT -gt 0 ]; then
    exit 1
fi
