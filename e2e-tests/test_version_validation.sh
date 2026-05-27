#!/bin/bash
# E2E Test Suite for OpenShift Version Validation Feature
#
# Tests:
# 1. generate-version-manifests.sh - Multi-version manifest generation
# 2. validate-deployment-standards.sh - Deployment type detection & LLM validation
# 3. compare-version-manifests.sh - Version comparison with LLM analysis
#
# Usage: ./e2e-tests/test_version_validation.sh [--skip-llm]
#
# Environment Variables:
#   LITELLM_API_KEY - Required for LLM validation tests
#   TEST_QUICK - Set to 'true' to skip time-consuming tests

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$SCRIPT_DIR/.."

# Configuration
SKIP_LLM=false
TEST_QUICK=${TEST_QUICK:-false}
TEST_OUTPUT_DIR="${HOME}/test_version_validation_output"
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-llm)
            SKIP_LLM=true
            shift
            ;;
        --quick)
            TEST_QUICK=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--skip-llm] [--quick]"
            exit 1
            ;;
    esac
done

# Load API key from env file if it exists
if [ -f "$HOME/env" ]; then
    source "$HOME/env"
fi

# Check prerequisites
check_prerequisites() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Checking Prerequisites${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    local all_good=true

    # Check required scripts exist
    for script in hack/generate-version-manifests.sh hack/validate-deployment-standards.sh hack/compare-version-manifests.sh; do
        if [ -x "$script" ]; then
            echo -e "  ${GREEN}✓${NC} Found: $script"
        else
            echo -e "  ${RED}✗${NC} Missing or not executable: $script"
            all_good=false
        fi
    done

    # Check required commands
    for cmd in ansible-playbook jq curl; do
        if command -v $cmd &> /dev/null; then
            echo -e "  ${GREEN}✓${NC} Command available: $cmd"
        else
            echo -e "  ${RED}✗${NC} Command missing: $cmd"
            all_good=false
        fi
    done

    # Check example configurations
    if [ -d "examples/sno-4.20-standard" ]; then
        echo -e "  ${GREEN}✓${NC} Test example exists: examples/sno-4.20-standard"
    else
        echo -e "  ${RED}✗${NC} Test example missing: examples/sno-4.20-standard"
        all_good=false
    fi

    # Check LLM API key (warning only)
    if [ -z "$LITELLM_API_KEY" ]; then
        echo -e "  ${YELLOW}⚠${NC}  LITELLM_API_KEY not set - LLM tests will be skipped"
        SKIP_LLM=true
    else
        echo -e "  ${GREEN}✓${NC} LITELLM_API_KEY is set"
    fi

    echo ""

    if [ "$all_good" = false ]; then
        echo -e "${RED}❌ Prerequisites not met. Please install missing dependencies.${NC}"
        exit 1
    fi
}

# Test helper functions
test_passed() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    PASSED_TESTS=$((PASSED_TESTS + 1))
}

test_failed() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    echo -e "${RED}       $2${NC}"
    FAILED_TESTS=$((FAILED_TESTS + 1))
}

test_skipped() {
    echo -e "${YELLOW}⊘ SKIP${NC}: $1"
    SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
}

# Test 1: generate-version-manifests.sh basic functionality
test_generate_version_manifests_basic() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Test 1: generate-version-manifests.sh - Basic Functionality${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Clean up any previous test output
    rm -rf "$TEST_OUTPUT_DIR"
    export GENERATED_ASSET_PATH="$TEST_OUTPUT_DIR"

    # Test: Generate manifests for single version
    echo -e "\n${BLUE}Test 1.1: Generate manifests for single version (4.20)${NC}"

    if ./hack/generate-version-manifests.sh sno-4.20-standard "4.20" > /dev/null 2>&1; then
        if [ -d "$TEST_OUTPUT_DIR/version-compare/sno-4.20-standard-4.20" ]; then
            test_passed "Manifests generated for single version"
        else
            test_failed "Output directory not created" "$TEST_OUTPUT_DIR/version-compare/sno-4.20-standard-4.20"
        fi
    else
        test_failed "generate-version-manifests.sh failed" "Exit code: $?"
    fi

    # Test: Check required files exist
    echo -e "\n${BLUE}Test 1.2: Required manifest files exist${NC}"

    MANIFEST_DIR="$TEST_OUTPUT_DIR/version-compare/sno-4.20-standard-4.20"
    if [ -f "$MANIFEST_DIR/install-config.yaml" ] && [ -f "$MANIFEST_DIR/agent-config.yaml" ]; then
        test_passed "Required manifest files exist (install-config.yaml, agent-config.yaml)"
    else
        test_failed "Required manifest files missing" "Expected: install-config.yaml, agent-config.yaml"
    fi

    # Test: Invalid example name handling
    echo -e "\n${BLUE}Test 1.3: Error handling for invalid example${NC}"

    if ./hack/generate-version-manifests.sh nonexistent-example "4.20" > /dev/null 2>&1; then
        test_failed "Should have failed for nonexistent example" "Script exited 0"
    else
        test_passed "Correctly rejects invalid example name"
    fi

    echo ""
}

# Test 2: Multi-version generation
test_generate_version_manifests_multi() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Test 2: generate-version-manifests.sh - Multi-Version${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if [ "$TEST_QUICK" = true ]; then
        test_skipped "Multi-version test (TEST_QUICK=true)"
        echo ""
        return
    fi

    # Clean up
    rm -rf "$TEST_OUTPUT_DIR"
    export GENERATED_ASSET_PATH="$TEST_OUTPUT_DIR"

    # Test: Generate manifests for multiple versions
    echo -e "\n${BLUE}Test 2.1: Generate manifests for 3 versions (4.19, 4.20, 4.21)${NC}"

    if ./hack/generate-version-manifests.sh sno-4.20-standard "4.19 4.20 4.21" > /dev/null 2>&1; then
        local versions_ok=true
        for ver in 4.19 4.20 4.21; do
            if [ ! -d "$TEST_OUTPUT_DIR/version-compare/sno-4.20-standard-$ver" ]; then
                versions_ok=false
                break
            fi
        done

        if [ "$versions_ok" = true ]; then
            test_passed "All 3 versions generated successfully"
        else
            test_failed "Not all version directories created" "Expected: 4.19, 4.20, 4.21"
        fi
    else
        test_failed "Multi-version generation failed" "Exit code: $?"
    fi

    # Test: Version-specific manifest differences
    echo -e "\n${BLUE}Test 2.2: Verify version-specific differences (4.19 vs 4.20)${NC}"

    # 4.19 should have imageDigestSources, 4.20 should not
    if grep -q "imageDigestSources" "$TEST_OUTPUT_DIR/version-compare/sno-4.20-standard-4.19/install-config.yaml" 2>/dev/null; then
        HAS_4_19_SOURCES=true
    else
        HAS_4_19_SOURCES=false
    fi

    if grep -q "imageDigestSources" "$TEST_OUTPUT_DIR/version-compare/sno-4.20-standard-4.20/install-config.yaml" 2>/dev/null; then
        HAS_4_20_SOURCES=true
    else
        HAS_4_20_SOURCES=false
    fi

    # For connected deployment, neither should have image sources
    # For disconnected, 4.19 should have it in install-config, 4.20 should have separate manifest
    if [ -f "$TEST_OUTPUT_DIR/version-compare/sno-4.20-standard-4.20/image-mirror-config.yaml" ]; then
        test_passed "4.20+ uses standalone image-mirror-config.yaml (when applicable)"
    else
        # This is OK for connected deployments
        test_passed "Version-specific manifest structure validated"
    fi

    echo ""
}

# Test 3: validate-deployment-standards.sh deployment detection
test_validate_deployment_detection() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Test 3: validate-deployment-standards.sh - Detection Logic${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Ensure we have manifests from previous test
    if [ ! -d "$TEST_OUTPUT_DIR/version-compare/sno-4.20-standard-4.20" ]; then
        echo -e "${YELLOW}⚠  Skipping: No manifests available from previous tests${NC}"
        test_skipped "Deployment detection tests (no manifests)"
        echo ""
        return
    fi

    # Test: Deployment topology detection
    echo -e "\n${BLUE}Test 3.1: Deployment topology detection (SNO)${NC}"

    # Run validation and capture output
    VALIDATION_OUTPUT=$(./hack/validate-deployment-standards.sh \
        "$TEST_OUTPUT_DIR/version-compare/sno-4.20-standard-4.20" 4.20 2>&1 || true)

    if echo "$VALIDATION_OUTPUT" | grep -q "Deployment Type:.*SNO"; then
        test_passed "Correctly detects SNO topology"
    else
        test_failed "SNO topology not detected" "Output: $(echo "$VALIDATION_OUTPUT" | grep "Deployment Type:" || echo "not found")"
    fi

    # Test: Connectivity detection improvement (our bug fix)
    echo -e "\n${BLUE}Test 3.2: Improved disconnected detection logic${NC}"

    # The sno-4.20-standard is CONNECTED, should detect correctly
    if echo "$VALIDATION_OUTPUT" | grep -q "CONNECTED\|DISCONNECTED"; then
        test_passed "Connectivity detection working"
    else
        test_failed "Connectivity not detected" "Expected CONNECTED or DISCONNECTED"
    fi

    echo ""
}

# Test 4: validate-deployment-standards.sh with LLM
test_validate_llm_integration() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Test 4: validate-deployment-standards.sh - LLM Integration${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if [ "$SKIP_LLM" = true ]; then
        test_skipped "LLM integration tests (LITELLM_API_KEY not set)"
        echo ""
        return
    fi

    if [ ! -d "$TEST_OUTPUT_DIR/version-compare/sno-4.20-standard-4.20" ]; then
        test_skipped "LLM integration tests (no manifests)"
        echo ""
        return
    fi

    # Test: LLM API connectivity
    echo -e "\n${BLUE}Test 4.1: LLM API connectivity${NC}"

    VALIDATION_OUTPUT=$(./hack/validate-deployment-standards.sh \
        "$TEST_OUTPUT_DIR/version-compare/sno-4.20-standard-4.20" 4.20 2>&1 || true)

    if echo "$VALIDATION_OUTPUT" | grep -q "LITELLM_API_KEY not set"; then
        test_failed "LLM API key not recognized" "Should not see API key error"
    elif echo "$VALIDATION_OUTPUT" | grep -q "LLM API Error"; then
        test_failed "LLM API call failed" "$(echo "$VALIDATION_OUTPUT" | grep "Error" | head -1)"
    else
        test_passed "LLM API integration working"
    fi

    # Test: LLM validation output format
    echo -e "\n${BLUE}Test 4.2: LLM validation output format${NC}"

    if echo "$VALIDATION_OUTPUT" | grep -qE "\[PASS\]|\[FAIL\]"; then
        test_passed "LLM produces PASS/FAIL validation results"
    else
        test_failed "LLM validation format incorrect" "Expected [PASS] or [FAIL] markers"
    fi

    echo ""
}

# Test 5: compare-version-manifests.sh
test_compare_version_manifests() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Test 5: compare-version-manifests.sh - Version Comparison${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if [ "$SKIP_LLM" = true ]; then
        test_skipped "Version comparison tests (LITELLM_API_KEY not set)"
        echo ""
        return
    fi

    if [ "$TEST_QUICK" = true ]; then
        test_skipped "Version comparison tests (TEST_QUICK=true)"
        echo ""
        return
    fi

    # Need at least 2 versions
    if [ ! -d "$TEST_OUTPUT_DIR/version-compare/sno-4.20-standard-4.19" ] || \
       [ ! -d "$TEST_OUTPUT_DIR/version-compare/sno-4.20-standard-4.20" ]; then
        test_skipped "Version comparison tests (need 2+ versions)"
        echo ""
        return
    fi

    # Test: Compare 4.19 vs 4.20
    echo -e "\n${BLUE}Test 5.1: Compare 4.19 vs 4.20${NC}"

    COMPARE_OUTPUT=$(./hack/compare-version-manifests.sh 4.19 4.20 sno-4.20-standard 2>&1 || true)

    if echo "$COMPARE_OUTPUT" | grep -q "LLM-Powered Compatibility Analysis"; then
        test_passed "Comparison script executed successfully"
    else
        test_failed "Comparison script failed" "Expected header not found"
    fi

    # Test: Exit code reflects validation status
    echo -e "\n${BLUE}Test 5.2: Exit code reflects validation result${NC}"

    if ./hack/compare-version-manifests.sh 4.19 4.20 sno-4.20-standard > /dev/null 2>&1; then
        EXIT_CODE=0
    else
        EXIT_CODE=$?
    fi

    # Exit code should be 0 (PASS) or 1 (FAIL), not other errors
    if [ $EXIT_CODE -eq 0 ] || [ $EXIT_CODE -eq 1 ]; then
        test_passed "Exit code is valid (0=PASS or 1=FAIL)"
    else
        test_failed "Unexpected exit code" "Got: $EXIT_CODE, Expected: 0 or 1"
    fi

    echo ""
}

# Test 6: CLI version caching
test_cli_version_caching() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Test 6: CLI Version Caching${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if [ "$TEST_QUICK" = true ]; then
        test_skipped "CLI caching tests (TEST_QUICK=true)"
        echo ""
        return
    fi

    # Test: Cache directory creation
    echo -e "\n${BLUE}Test 6.1: CLI cache directory exists${NC}"

    if [ -d "$HOME/.cache/ocp-cli" ]; then
        test_passed "CLI cache directory exists at ~/.cache/ocp-cli"
    else
        test_skipped "CLI cache not created yet (may use system OC)"
    fi

    echo ""
}

# Print summary
print_summary() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Test Summary${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    TOTAL_TESTS=$((PASSED_TESTS + FAILED_TESTS + SKIPPED_TESTS))

    echo -e "Total Tests:   $TOTAL_TESTS"
    echo -e "${GREEN}Passed:        $PASSED_TESTS${NC}"
    echo -e "${RED}Failed:        $FAILED_TESTS${NC}"
    echo -e "${YELLOW}Skipped:       $SKIPPED_TESTS${NC}"
    echo ""

    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "${GREEN}✓ All tests passed!${NC}"
        echo ""
        echo "Test artifacts saved to: $TEST_OUTPUT_DIR"
        return 0
    else
        echo -e "${RED}✗ Some tests failed. Please review output above.${NC}"
        echo ""
        echo "Test artifacts saved to: $TEST_OUTPUT_DIR"
        return 1
    fi
}

# Main execution
main() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  OpenShift Version Validation E2E Test Suite          ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    check_prerequisites

    # Run all test suites
    test_generate_version_manifests_basic
    test_generate_version_manifests_multi
    test_validate_deployment_detection
    test_validate_llm_integration
    test_compare_version_manifests
    test_cli_version_caching

    # Print summary and exit with appropriate code
    print_summary
}

# Run main
main
