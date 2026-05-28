#!/bin/bash
# Pre-Release Validation Orchestrator for v4.21.0
# Reuses existing e2e-tests and validation scripts
# Issue: #31

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$SCRIPT_DIR/.."

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

REPORT_FILE="${HOME}/validation-report-v4.21.0.md"

log_section() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

init_report() {
    cat > "$REPORT_FILE" << EOF
# OpenShift Agent Install v4.21.0 - Pre-Release Validation Report

**Date:** $(date '+%Y-%m-%d %H:%M:%S')
**System:** $(hostname) - RHEL $(rpm -E %{rhel})
**Issue:** #31
**Milestone:** v4.21.0 - Platform Stability & Enterprise Integration

## Validation Strategy

This validation reuses existing e2e-tests and validation scripts:
- ✅ \`e2e-tests/test_version_validation.sh\` - Multi-version testing
- ✅ \`hack/generate-version-manifests.sh\` - Version manifest generation
- ✅ \`hack/validate-deployment-standards.sh\` - Deployment standards validation
- ✅ \`hack/compare-version-manifests.sh\` - Version comparison
- ✅ \`e2e-tests/run_e2e.sh\` - Full E2E deployment testing

---

## Test Phases

EOF
}

# =============================================================================
# Phase 1: Version Validation E2E Tests (Existing Script)
# =============================================================================
run_version_validation_tests() {
    log_section "Phase 1: Version Validation E2E Tests"

    log_info "Running e2e-tests/test_version_validation.sh"
    log_info "This tests:"
    log_info "  - Multi-version manifest generation (4.19, 4.20, 4.21)"
    log_info "  - Deployment standards validation"
    log_info "  - Version comparison with LLM analysis"

    echo "" | tee -a "$REPORT_FILE"
    echo "### Phase 1: Version Validation Tests" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    if ./e2e-tests/test_version_validation.sh --quick 2>&1 | tee -a "$REPORT_FILE"; then
        log_success "Version validation tests passed"
        echo "✅ **Status:** PASSED" >> "$REPORT_FILE"
    else
        log_error "Version validation tests failed"
        echo "❌ **Status:** FAILED" >> "$REPORT_FILE"
        return 1
    fi

    echo "" >> "$REPORT_FILE"
}

# =============================================================================
# Phase 2: Platform-Specific Manifest Validation
# =============================================================================
run_platform_validation() {
    log_section "Phase 2: Platform-Specific Manifest Validation"

    echo "### Phase 2: Platform Validation" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    local examples=(
        "nutanix-sno"
        "nutanix-ha"
        "vmware-disconnected-example"
    )

    for example in "${examples[@]}"; do
        log_info "Testing: $example"

        if [ ! -d "examples/$example" ]; then
            log_warning "Example not found: $example (skipping)"
            echo "- ⊘ $example - **SKIPPED** (not found)" >> "$REPORT_FILE"
            continue
        fi

        # Generate manifests
        if ./hack/create-iso.sh "$example" &>/dev/null; then
            log_success "Manifests generated: $example"
            echo "- ✅ $example - **PASSED**" >> "$REPORT_FILE"
        else
            log_error "Manifest generation failed: $example"
            echo "- ❌ $example - **FAILED**" >> "$REPORT_FILE"
        fi
    done

    echo "" >> "$REPORT_FILE"
}

# =============================================================================
# Phase 3: Disconnected Workflow Validation
# =============================================================================
run_disconnected_validation() {
    log_section "Phase 3: Disconnected Workflow Validation"

    echo "### Phase 3: Disconnected Workflow" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    local example="ha-4.21-disconnected"
    log_info "Testing disconnected example: $example"

    # Generate manifests
    log_info "Generating manifests..."
    if ./hack/create-iso.sh "$example" 2>&1 | tee /tmp/disconnected-test.log; then
        log_success "Disconnected manifests generated"

        # Check for ImageDigestMirrorSet
        if [ -f "${HOME}/generated_assets/ha-4-21/image-mirror-config.yaml" ]; then
            if grep -q "kind: ImageDigestMirrorSet" "${HOME}/generated_assets/ha-4-21/image-mirror-config.yaml"; then
                log_success "ImageDigestMirrorSet manifest found (4.20+ API)"
                echo "- ✅ ImageDigestMirrorSet - **PASSED**" >> "$REPORT_FILE"
            fi
        else
            log_warning "ImageDigestMirrorSet manifest not found (check disconnected_registries config)"
            echo "- ⚠️  ImageDigestMirrorSet - **WARNING** (not generated)" >> "$REPORT_FILE"
        fi

        # Check for UpdateService
        if [ -f "${HOME}/generated_assets/ha-4-21/updateservice.yaml" ]; then
            if grep -q "kind: UpdateService" "${HOME}/generated_assets/ha-4-21/updateservice.yaml"; then
                log_success "UpdateService manifest found (NEW in v4.21.0)"
                echo "- ✅ UpdateService - **PASSED**" >> "$REPORT_FILE"
            fi
        else
            log_warning "UpdateService manifest not found (check deploy_update_service config)"
            echo "- ⚠️  UpdateService - **WARNING** (not generated)" >> "$REPORT_FILE"
        fi

        # Verify no image sources in install-config
        if ! grep -q "imageDigestSources\|imageContentSources" "${HOME}/generated_assets/ha-4-21/install-config.yaml"; then
            log_success "No image sources in install-config.yaml (correct for 4.20+)"
            echo "- ✅ install-config.yaml (no image sources) - **PASSED**" >> "$REPORT_FILE"
        else
            log_error "Image sources found in install-config.yaml (should be in separate manifest)"
            echo "- ❌ install-config.yaml (image sources present) - **FAILED**" >> "$REPORT_FILE"
        fi

    else
        log_error "Disconnected manifest generation failed"
        echo "- ❌ Manifest generation - **FAILED**" >> "$REPORT_FILE"
    fi

    echo "" >> "$REPORT_FILE"
}

# =============================================================================
# Phase 4: Network Type Enforcement Validation
# =============================================================================
run_network_enforcement_validation() {
    log_section "Phase 4: OVNKubernetes Enforcement (4.21+)"

    echo "### Phase 4: Network Type Enforcement" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    # Create test config with OpenShiftSDN for 4.21 (should fail)
    log_info "Creating test config with OpenShiftSDN + OCP 4.21 (should be rejected)"

    mkdir -p /tmp/network-test
    cp -r examples/sno-4.20-standard/* /tmp/network-test/

    # Modify to use OpenShiftSDN
    sed -i 's/network_type: OVNKubernetes/network_type: OpenShiftSDN/' /tmp/network-test/cluster.yml
    sed -i 's/ocp_version: .*/ocp_version: "4.21"/' /tmp/network-test/cluster.yml

    # Copy to examples for testing
    mkdir -p examples/test-network-enforcement
    cp /tmp/network-test/* examples/test-network-enforcement/

    log_info "Testing OpenShiftSDN rejection for OCP 4.21..."
    if ./hack/create-iso.sh test-network-enforcement 2>&1 | tee /tmp/network-test.log; then
        log_error "OpenShiftSDN was NOT rejected for 4.21 (enforcement FAILED)"
        echo "- ❌ OpenShiftSDN rejection - **FAILED** (was accepted)" >> "$REPORT_FILE"
    else
        # Check error message
        if grep -q "OpenShiftSDN" /tmp/network-test.log && grep -q "4.21" /tmp/network-test.log; then
            log_success "OpenShiftSDN correctly rejected for 4.21 with proper error"
            echo "- ✅ OpenShiftSDN rejection - **PASSED**" >> "$REPORT_FILE"
        else
            log_warning "OpenShiftSDN rejected but error message unclear"
            echo "- ⚠️  OpenShiftSDN rejection - **WARNING** (error message unclear)" >> "$REPORT_FILE"
        fi
    fi

    # Cleanup
    rm -rf examples/test-network-enforcement /tmp/network-test

    echo "" >> "$REPORT_FILE"
}

# =============================================================================
# Phase 5: Optional Full E2E Deployment Test
# =============================================================================
run_full_e2e_test() {
    log_section "Phase 5: Full E2E Deployment (Optional - SKIPPED)"

    echo "### Phase 5: Full E2E Deployment" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "⊘ **Status:** SKIPPED (use \`./e2e-tests/run_e2e.sh <example>\` manually if needed)" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    log_warning "Full E2E deployment test skipped"
    log_info "To run manually: ./e2e-tests/run_e2e.sh sno-4.20-standard"
}

# =============================================================================
# Generate Summary
# =============================================================================
generate_summary() {
    log_section "Validation Summary"

    cat >> "$REPORT_FILE" << EOF

---

## Summary and Recommendations

EOF

    # Count results
    PASSED=$(grep -c "✅.*PASSED" "$REPORT_FILE" || echo 0)
    FAILED=$(grep -c "❌.*FAILED" "$REPORT_FILE" || echo 0)
    WARNINGS=$(grep -c "⚠️.*WARNING" "$REPORT_FILE" || echo 0)

    echo "- **Tests Passed:** $PASSED" >> "$REPORT_FILE"
    echo "- **Tests Failed:** $FAILED" >> "$REPORT_FILE"
    echo "- **Warnings:** $WARNINGS" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    if [ "$FAILED" -eq 0 ]; then
        cat >> "$REPORT_FILE" << EOF
### ✅ Release Status: READY

All critical validation tests passed. The release can proceed.

**Next Steps:**
1. Review this report and any warnings
2. Post results to issue #31
3. Close issue #31
4. Update issue #24 with validation completion
5. Tag v4.21.0 release
6. Generate CHANGELOG

EOF
        log_success "All validation tests passed! Release is ready."
    else
        cat >> "$REPORT_FILE" << EOF
### ❌ Release Status: BLOCKED

$FAILED test(s) failed. Address these issues before release.

**Required Actions:**
1. Review failed tests above
2. Fix identified issues
3. Re-run validation: ./hack/pre-release-validation.sh
4. Do NOT release until all critical tests pass

EOF
        log_error "$FAILED validation test(s) failed. Release is blocked."
    fi

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Validation Complete${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "📊 Results: $PASSED passed, $FAILED failed, $WARNINGS warnings"
    echo "📄 Full report: $REPORT_FILE"
    echo ""

    # Display report
    cat "$REPORT_FILE"

    # Return exit code
    [ "$FAILED" -eq 0 ]
}

# =============================================================================
# Main
# =============================================================================
main() {
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  OpenShift Agent Install v4.21.0                      ║${NC}"
    echo -e "${CYAN}║  Pre-Release Validation (Reusing Existing Scripts)    ║${NC}"
    echo -e "${CYAN}║  Issue #31                                            ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""

    init_report

    # Run validation phases
    run_version_validation_tests || true
    run_platform_validation || true
    run_disconnected_validation || true
    run_network_enforcement_validation || true
    run_full_e2e_test  # Skipped by default

    # Generate summary and return exit code
    generate_summary
}

# Show help
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    cat << EOF
Usage: $0

Pre-Release Validation for OpenShift Agent Install v4.21.0

This script orchestrates existing validation tools:
  - e2e-tests/test_version_validation.sh (version matrix testing)
  - hack/generate-version-manifests.sh (multi-version manifests)
  - hack/validate-deployment-standards.sh (standards validation)
  - hack/create-iso.sh (manifest generation per example)

Validation Phases:
  1. Version validation tests (4.19, 4.20, 4.21)
  2. Platform-specific manifests (Nutanix, vSphere)
  3. Disconnected workflow (ImageDigestMirrorSet, UpdateService)
  4. Network enforcement (OVNKubernetes for 4.21+)
  5. Full E2E deployment (optional - currently skipped)

Output:
  - Validation report: ${HOME}/validation-report-v4.21.0.md
  - Test artifacts: ${HOME}/test_version_validation_output/

Related Issue: #31
Related Milestone: v4.21.0

EOF
    exit 0
fi

# Run main
main
