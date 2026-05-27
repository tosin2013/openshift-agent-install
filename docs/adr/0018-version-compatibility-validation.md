---
layout: default
title: "ADR-0018-version-compatibility-validation: ---"
description: "Architecture Decision Record for OpenShift Version Compatibility Validation and Testing"
---

# ADR-018: OpenShift Version Compatibility Validation and Testing

## Date
2026-05-27

## Status
Accepted

## Decision Makers
- OpenShift Platform Team
- DevOps Automation Team
- Quality Engineering Team

## Context
The repository supports OpenShift versions 4.15-4.22+ with critical API changes at version boundaries:
- **4.19→4.20**: ImageContentSourcePolicy/imageDigestSources removed, ImageDigestMirrorSet mandatory
- **4.20→4.21**: OpenShiftSDN removed completely, OVNKubernetes enforced
- **4.22+**: ContainerRuntimeConfig for AI/ML workloads

Without automated validation:
- Template bugs surface only during production deployments
- Version-specific API deprecations go undetected
- Manual testing across versions is error-prone and time-consuming
- No systematic tracking of version compatibility

**Real-World Impact**:
- Issue #11 (ImageDigestMirrorSet migration) highlighted the need for version testing
- Examples specify versions inconsistently (25% have `ocp_version`, 75% rely on defaults)
- No automated way to validate templates generate correct manifests per version

## Considered Options

### 1. Manual Version Testing
- Pros:
  - No additional tooling required
  - Full control over test scenarios
- Cons:
  - Time-consuming (5-10 min per version)
  - Error-prone (human oversight)
  - Not scalable across 20+ examples × 3-4 versions
  - No CI/CD integration

### 2. Lightweight Bash Scripting
- Pros:
  - Fast execution (<2 min per version)
  - Reuses existing patterns
  - No new dependencies
- Cons:
  - Limited diff analysis (only shows what changed)
  - Cannot explain WHY changes occurred
  - Manual maintenance of expected changes
  - No intelligent validation

### 3. LLM-Powered Intelligent Validation (Selected)
- Pros:
  - **Smart diff interpretation**: Explains what changed and why
  - **Version-aware validation**: Knows OpenShift API changes per version
  - **Deployment standards**: Validates patterns against version-specific requirements
  - **Natural language reports**: Human-readable explanations
  - **Auto-documentation**: Generates compatibility matrix from results
  - **GitHub integration**: Automated issue creation for failures
- Cons:
  - Requires API key and network access
  - Slightly slower than pure bash (~1-2s API latency)
  - Dependency on external LLM service

## Decision
We chose **LLM-Powered Intelligent Validation** using Granite-3-2-8b-instruct because it:
1. Explains complex API migrations (ImageContentSourcePolicy → ImageDigestMirrorSet)
2. Validates against version-specific deployment standards (SNO, 3-Node, HA × Connected/Disconnected/Proxy)
3. Auto-generates human-readable compatibility documentation
4. Integrates with GitHub Actions for CI/CD automation
5. Creates actionable GitHub issues with LLM-generated remediation steps

**Fallback**: If LLM API unavailable, falls back to basic bash diff

## Implementation

### Core Components

#### 1. Version Manifest Generator (`hack/generate-version-manifests.sh`)
```bash
# Downloads specific OC CLI versions
# Generates manifests for multiple OpenShift versions
# Stores output in versioned directories
./hack/generate-version-manifests.sh sno-disconnected "4.19 4.20 4.21"
```

**Features**:
- CLI version caching (`~/.cache/ocp-cli/<version>/`)
- Cross-platform OS detection (RHEL 8/9, Ubuntu, Debian)
- Explicit version argument support (stable-4.20, 4.21, etc.)
- Parallel manifest generation for efficiency

#### 2. LLM-Powered Comparison Tool (`hack/compare-version-manifests.sh`)
```bash
# Compares manifests between versions
# Sends diff to LLM for analysis
# Reports PASS/FAIL with explanations
./hack/compare-version-manifests.sh 4.19 4.20 sno-disconnected
```

**LLM Prompt Structure**:
- System context: OpenShift deployment expert
- Version standards: Embedded 4.19/4.20/4.21 requirements
- Manifest diff: Unified diff between versions
- Analysis request: What changed, why, compliance check

**Validation Categories**:
- Image Registry Configuration
- Network Configuration
- Platform Configuration
- Deployment Topology
- Connectivity Requirements

#### 3. Deployment Standards Validator (`hack/validate-deployment-standards.sh`)
```bash
# Auto-detects deployment type from install-config.yaml
# Validates against version-specific standards
# Creates GitHub issues for failures
./hack/validate-deployment-standards.sh \
  ~/generated_assets/version-compare/sno-disconnected-4.20 4.20 \
  --create-issue
```

**Auto-Detection Logic**:
- **Deployment Type**: SNO (1,0), 3-Node (3,0), HA (3,2+)
- **Connectivity**: Disconnected (additionalTrustBundle), Proxy (httpProxy), Connected
- **Platform**: baremetal, vsphere, none, nutanix
- **Network**: OpenShiftSDN vs OVNKubernetes

**GitHub Issue Format**:
```markdown
## Automated Validation Report

**Deployment Type:** SNO (DISCONNECTED)
**OpenShift Version:** 4.20
**Example:** sno-disconnected

---

## LLM Validation Results

[FAIL] Image Registry Configuration
- Issue: imageDigestSources in install-config.yaml (removed 4.20+)
- Remediation: Use standalone ImageDigestMirrorSet manifest
- Severity: CRITICAL

[PASS] Network Configuration
[PASS] Platform Configuration
```

#### 4. GitHub Actions Workflow (`.github/workflows/version-validation.yml`)
```yaml
# Matrix testing: 3 versions × 3 examples = 9 jobs
# Runs on PR to templates/ or examples/
# Creates issues for failures
# Uploads artifacts (manifests, reports)
```

**Trigger Conditions**:
- Pull requests modifying:
  - `playbooks/templates/**`
  - `examples/**`
  - `docs/deployment-standards-*.md`
  - `hack/*version*.sh`
- Manual workflow dispatch with options:
  - `create_issues`: true/false
  - `examples`: space-separated list

**Deployment Type Coverage**:
- SNO Connected
- SNO Disconnected
- HA Disconnected
- 3-Node Compact
- HA Connected
- HA Proxy

#### 5. Deployment Standards Documentation
- `docs/deployment-standards-4.19.md` - Transitional API (imageDigestSources)
- `docs/deployment-standards-4.20.md` - ImageDigestMirrorSet mandatory
- `docs/deployment-standards-4.21.md` - OVNKubernetes enforcement

**Coverage Per Version**:
- Connected Standard (public registries)
- Disconnected/Air-Gapped (mirror registry)
- Proxy (corporate proxy)
- SNO (single node)
- 3-Node Compact
- HA (high availability)
- Edge (resource-constrained)

### Enhanced CLI Download (`download-openshift-cli.sh`)
```bash
# Auto-detects OS (RHEL 8/9, Ubuntu, Debian)
# Accepts explicit version argument
./download-openshift-cli.sh 4.20  # Download specific version
./download-openshift-cli.sh       # Auto-detect based on OS
```

**Cross-Platform Support**:
- RHEL 8 → stable-4.15
- RHEL 9 → stable-4.17
- Ubuntu/Debian → stable-4.21
- Unknown → stable-4.21 (default)

### Documentation
- `docs/version-compatibility-matrix.md` - API changes, migration paths
- `docs/version-validation-feature.md` - Complete feature documentation
- `docs/version-validation-quick-start.md` - Step-by-step guide
- `VERSION_VALIDATION_CHEATSHEET.md` - Quick reference commands
- `README.md` - Version validation section
- `llm.txt` - Script reference documentation

## Consequences

### Positive
1. **Early API Change Detection**
   - Catches deprecated APIs before deployment
   - Validates version boundaries (4.19→4.20, 4.20→4.21)
   - Prevents production failures from API incompatibilities

2. **Intelligent Validation**
   - LLM explains WHY manifests changed
   - Validates against deployment pattern standards
   - Provides actionable remediation steps

3. **CI/CD Integration**
   - Automated PR validation
   - GitHub issue creation for failures
   - Matrix testing across versions and deployment types

4. **Self-Documenting**
   - Auto-generates compatibility matrix
   - LLM-powered natural language reports
   - Version-specific deployment standards

5. **Developer Productivity**
   - Reduces manual version testing time (30 min → 5 min)
   - Catches issues before manual review
   - Provides clear migration guidance

6. **Quality Assurance**
   - Systematic coverage of 7 deployment types × 3 versions
   - Regression detection for template changes
   - Consistent validation across team

### Negative
1. **External Dependency**
   - Requires LiteLLM API access
   - Network connectivity needed
   - API key management required

2. **Execution Time**
   - Slightly slower than pure bash (API call latency)
   - First-time CLI download per version (cached thereafter)

3. **Complexity**
   - Additional scripts to maintain
   - LLM prompt engineering required
   - Deployment standards docs need updates

### Mitigations
- **Fallback**: Basic bash diff if LLM unavailable
- **Caching**: CLI binaries cached per version
- **Documentation**: Comprehensive script reference in llm.txt
- **Testing**: E2E workflow verification

## Related
- Issue #11: ImageDigestMirrorSet migration for 4.20
- `playbooks/templates/install-config.yml.j2` - Version-aware templating
- `examples/` - Version-specific example configurations
- `.github/workflows/version-validation.yml` - CI/CD automation

## Test Cases

### Local Validation Workflow
```bash
# Generate manifests for 3 versions
./hack/generate-version-manifests.sh sno-disconnected "4.19 4.20 4.21"

# Validate each version
./hack/validate-deployment-standards.sh \
  ~/generated_assets/version-compare/sno-disconnected-4.19 4.19

./hack/validate-deployment-standards.sh \
  ~/generated_assets/version-compare/sno-disconnected-4.20 4.20

./hack/validate-deployment-standards.sh \
  ~/generated_assets/version-compare/sno-disconnected-4.21 4.21

# Compare critical boundaries
./hack/compare-version-manifests.sh 4.19 4.20 sno-disconnected
./hack/compare-version-manifests.sh 4.20 4.21 sno-disconnected
```

### CI/CD Validation
```bash
# Trigger GitHub Actions workflow
gh workflow run version-validation.yml \
  -f create_issues=true \
  -f examples="sno-disconnected ha-4.21-disconnected sno-4.20-standard"

# View results
gh run list --workflow=version-validation.yml --limit 1
```

### Expected Outputs

**4.19→4.20 Comparison** (ImageDigestMirrorSet migration):
```
✅ PASS: Image Registry Configuration
- OCP 4.19 correctly uses imageDigestSources (transitional API)
- OCP 4.20 correctly uses standalone ImageDigestMirrorSet
- Migration path is valid
```

**4.20→4.21 Comparison** (OpenShiftSDN removal):
```
⚠️ WARNING: Network Configuration
- networkType: OpenShiftSDN detected
- RECOMMENDED: Switch to OVNKubernetes before 4.21 upgrade
- OpenShiftSDN will be removed in 4.21
```

**Validation Failure Example**:
```
[FAIL] Deployment Topology
- Issue: Control plane replicas: 3, Worker replicas: 2 (HA)
- platform_type: none not recommended for HA production
- Remediation: Use platform_type: baremetal for VIP management
- Severity: WARNING
```

## LLM Integration Details

### Model
- **Name**: granite-3-2-8b-instruct
- **Endpoint**: https://litellm-prod.apps.maas.redhatworkshops.io/v1/chat/completions
- **Temperature**: 0.2 (deterministic validation)

### Prompt Engineering
- **System Role**: "OpenShift deployment expert. Analyze manifest differences and validate against version-specific standards."
- **User Prompt**: Includes version standards, manifest diff, analysis requirements
- **Output Format**: Structured PASS/FAIL with Issue/Remediation/Severity

### Validation Logic
1. Extract manifest characteristics (imageDigestSources, networkType, platform, replicas)
2. Build deployment type profile (SNO/3-Node/HA × Connected/Disconnected/Proxy)
3. Load version standards from `docs/deployment-standards-<version>.md`
4. Send to LLM with structured prompt
5. Parse PASS/FAIL results
6. Exit 0 (all pass) or 1 (any fail)

## Future Enhancements

### Phase 1 Completed (2026-05-27)
- ✅ Core scripts with LLM intelligence
- ✅ GitHub Actions integration
- ✅ Documentation (matrix, quick start, cheat sheet)
- ✅ Deployment standards documents (4.19, 4.20, 4.21)

### Phase 2 Candidates
- Pre-release version support (4.22-ec, 4.22-rc, nightly)
- Additional deployment standards (4.22, 4.23)
- MCP server tool integration
- Cross-repository validation
- Performance metrics tracking

### Phase 3 Enhancements
- Automated PR comments with validation summary
- Version upgrade path recommendations
- Migration guide generation from comparison results
- Integration with release planning (RELEASE_PLAN.md)

## Notes
This feature is particularly valuable for:
- Multi-version support (4.15-4.22+)
- Template development and testing
- Version boundary migrations (4.19→4.20, 4.20→4.21)
- Quality assurance across deployment patterns
- Continuous integration and delivery

The LLM-powered approach provides significant value over simple diff tools by:
- Explaining complex API migrations
- Validating deployment pattern compliance
- Generating actionable remediation guidance
- Auto-documenting version compatibility

## References
- [Version Compatibility Matrix](../version-compatibility-matrix.md)
- [Version Validation Feature Documentation](../version-validation-feature.md)
- [Version Validation Quick Start](../version-validation-quick-start.md)
- [Version Validation Cheatsheet](../../VERSION_VALIDATION_CHEATSHEET.md)
- [OpenShift 4.20 Release Notes](https://docs.openshift.com/container-platform/4.20/release_notes/)
- [OpenShift 4.21 Release Notes](https://docs.openshift.com/container-platform/4.21/release_notes/)
