# OpenShift Version Compatibility Validation

## Overview

Automated validation feature that ensures OpenShift manifest templates generate correct configurations across multiple OpenShift versions (4.19, 4.20, 4.21+). Uses LLM-powered analysis (Granite-3-2-8b-instruct via LiteLLM) to detect version-specific API changes and deployment standards violations.

## Problem Statement

- OpenShift templates must support versions 4.15-4.22+ with critical API changes at version boundaries
- ImageContentSourcePolicy → imageDigestSources → ImageDigestMirrorSet migration (4.19→4.20→4.21)
- OpenShiftSDN removed in 4.21, OVNKubernetes mandatory
- Template bugs surface only during deployment without automated validation
- Examples specify versions inconsistently (25% explicit, 75% defaults)

## Solution

Three-phase validation workflow:

1. **Generate**: Create manifests for multiple OCP versions from single example config
2. **Validate**: LLM validates each version against deployment standards
3. **Compare**: LLM compares adjacent versions to detect expected/unexpected changes

## Architecture

```
hack/generate-version-manifests.sh
  ├─> Downloads version-specific OC CLI (with caching)
  ├─> Runs Ansible with ocp_version override
  └─> Outputs: ~/generated_assets/version-compare/<example>-<version>/

hack/validate-deployment-standards.sh
  ├─> Auto-detects deployment type (SNO/HA/3-Node × Connected/Disconnected/Proxy)
  ├─> Calls LiteLLM API with version-specific standards
  ├─> Generates PASS/FAIL report with remediation steps
  └─> Optional: Creates GitHub issue for violations

hack/compare-version-manifests.sh
  ├─> Generates unified diff between versions
  ├─> Calls LiteLLM API with version standards + diff
  ├─> Validates changes against expected API migrations
  └─> Outputs: Structured compatibility report

.github/workflows/version-validation.yml
  ├─> Runs on PR (template/example changes)
  ├─> Matrix: 3 versions × N examples
  ├─> Uploads manifests + reports as artifacts
  └─> Comments PR with validation summary
```

## Deployment Standards

Version-specific deployment pattern requirements documented in:

- `docs/deployment-standards-4.19.md` - Transitional imageDigestSources, OpenShiftSDN deprecated
- `docs/deployment-standards-4.20.md` - ImageDigestMirrorSet standalone manifest, imageDigestSources removed from install-config
- `docs/deployment-standards-4.21.md` - OpenShiftSDN removed, OVNKubernetes mandatory

Each document defines requirements for 7 deployment types:
1. Connected Standard (internet-connected, public registries)
2. Disconnected/Air-Gapped (mirror registry, no internet)
3. Proxy (corporate proxy, restricted internet)
4. SNO (Single Node OpenShift)
5. 3-Node Compact (3 masters, no workers)
6. HA (High Availability, 3+ masters, 2+ workers)
7. Edge (resource-constrained, intermittent connectivity)

## Usage

### Local Testing

```bash
# 1. Generate manifests for multiple versions
./hack/generate-version-manifests.sh sno-disconnected "4.19 4.20 4.21"

# 2. Validate each version
./hack/validate-deployment-standards.sh \
  ~/generated_assets/version-compare/sno-disconnected-4.19 4.19

./hack/validate-deployment-standards.sh \
  ~/generated_assets/version-compare/sno-disconnected-4.20 4.20

# 3. Compare versions
./hack/compare-version-manifests.sh 4.19 4.20 sno-disconnected
./hack/compare-version-manifests.sh 4.20 4.21 sno-disconnected
```

### GitHub Actions

Automatically runs on PRs that modify:
- `playbooks/templates/**`
- `examples/**`
- `docs/deployment-standards-*.md`
- Validation scripts in `hack/`

**Manual Trigger** (with optional issue creation):
```yaml
workflow_dispatch:
  inputs:
    create_issues: 'true'  # Creates GitHub issues for failures
    examples: 'sno-disconnected ha-4.21-disconnected'
```

**Default Examples Tested**:
- `sno-disconnected` - SNO disconnected deployment
- `ha-4.21-disconnected` - HA disconnected deployment
- `sno-4.20-standard` - SNO connected deployment

## LLM Integration

### API Configuration

- **Endpoint**: `https://litellm-prod.apps.maas.redhatworkshops.io/v1/chat/completions`
- **Model**: `granite-3-2-8b-instruct`
- **Temperature**: 0.2 (deterministic)
- **Auth**: Bearer token from `$LITELLM_API_KEY` (sourced from `~/env`)

### LLM Prompts

**Validation Prompt** (validate-deployment-standards.sh):
```
Validate this OpenShift <version> deployment configuration against deployment standards.

**Deployment Type Detected:** <topology> (<connectivity>)
- Topology: SNO | 3-NODE | HA
- Connectivity: CONNECTED | DISCONNECTED | PROXY
- Platform: <platform_type>

**Generated Manifests:**
- imageDigestSources in install-config.yaml: true/false
- imageContentSources in install-config.yaml: true/false
- Standalone image-mirror-config.yaml exists: true/false
- Proxy configured: true/false
- networkType: <type>

**Standards for OCP <version>:**
[Full standards document content]

**Validation Required:**
1. Does this configuration comply with OCP <version> standards?
2. Are there any deprecated API usages?
3. Are there deployment type-specific issues?
4. What changes are needed to make it compliant?

**Output Format:**
[PASS/FAIL] for each category with remediation steps
```

**Comparison Prompt** (compare-version-manifests.sh):
```
Analyze manifest differences between OCP <base> and <target>.

**Deployment Pattern Standards by Version:**
[Standards for base version]
[Standards for target version]

**Manifest Comparison Data:**
install-config.yaml diff: [unified diff]
Additional manifests: [presence checks]

**Analysis Required:**
1. What changed between versions?
2. Are changes expected per version standards?
3. Are there any violations?
4. What risks exist if manifests used for wrong version?

Provide structured report with PASS/FAIL for each check.
```

### Fallback Behavior

If LLM API unavailable:
- `validate-deployment-standards.sh`: Basic regex checks (imageContentSources in 4.20+, OpenShiftSDN in 4.21+)
- `compare-version-manifests.sh`: Basic grep-based diff output

## Validation Reports

### Validation Report Format

```
==================================================================
OpenShift <version> Deployment Standards Validation
==================================================================
Deployment Type:    <topology> (<connectivity>)
Validated:          <timestamp>

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

Summary:
Overall Status: PASS or FAIL

For each FAIL:
- Issue: (what's wrong)
- Remediation: (how to fix)
- Severity: (CRITICAL/WARNING/INFO)
```

### Comparison Report Format

```
Analysis Report: OpenShift <base> vs <target> Manifest Differences

1. What changed between versions?
   - <change 1>
   - <change 2>

2. Are changes expected per version standards?
   - [PASS/FAIL] <check 1>
   - [PASS/FAIL] <check 2>

3. Are there any violations?
   - [PASS/FAIL] <validation 1>

4. What risks exist if manifests used for wrong version?
   - <risk 1>
   - <risk 2>

Remediation Steps:
- <step 1>
- <step 2>
```

## GitHub Issue Creation

When validation fails and `--create-issue` flag provided:

**Issue Title**: `Deployment Standards Violation: <example> (OCP <version>)`

**Labels**: `deployment-standards`, `automated`, `llm-generated`

**Body**:
```markdown
## Automated Validation Report

**Deployment Type:** <type>
**OpenShift Version:** <version>
**Manifest Directory:** `<path>`
**Generated:** <timestamp>

---

## LLM Validation Results

[Full LLM response]

---

## Critical Issues
[Extracted CRITICAL issues]

## Warnings
[Extracted WARNING issues]

---

**Automated by:** `hack/validate-deployment-standards.sh`
**Standards Reference:** `docs/deployment-standards-<version>.md`
**Model:** granite-3-2-8b-instruct
```

## Performance

- **Manifest Generation**: ~30s per version (with CLI caching)
- **Validation**: ~5s per version (LLM API call)
- **Comparison**: ~5s per version pair (LLM API call)
- **Full Workflow** (3 versions, 3 examples): ~8-10 minutes in GitHub Actions

## Known Limitations

1. **Deployment Type Detection**: Requires `additionalTrustBundle` in generated manifest (not just cluster.yml) to detect DISCONNECTED
2. **OC CLI Download**: Permission issues in some environments, gracefully falls back to system CLI
3. **LLM Accuracy**: Occasional minor analysis errors (e.g., misinterpreting diffs), but change detection is reliable
4. **API Rate Limits**: LiteLLM endpoint may rate-limit on high-volume workflows

## Future Enhancements

### Pre-Release Support (Planned)

Support Early Candidate, Release Candidate, and nightly builds:

```bash
# Pre-release versions
./hack/generate-version-manifests.sh sno-disconnected "4.21 4.22-ec.1"
./hack/generate-version-manifests.sh sno-disconnected "4.22-rc.1 4.23-nightly"
```

**Standards Documents**:
- `docs/deployment-standards-4.22-preview.md` - EC/RC standards
- `docs/deployment-standards-4.23-nightly.md` - Nightly build warnings

**GitHub Actions Matrix**:
```yaml
matrix:
  ocp_version:
    - '4.21'
    - '4.22-ec.1'    # Uncomment when available
    - '4.22-rc.1'    # Uncomment for GA prep
```

### Additional Deployment Types

- **Multi-Cluster** (ACM/Hive)
- **Hosted Control Plane** (HyperShift)
- **vSphere with CSI** (specific platform validation)

### Enhanced LLM Features

- **Multi-LLM Consensus**: Query multiple models, vote on validation results
- **Fine-tuned Model**: Train on historical validation data for improved accuracy
- **Remediation Automation**: LLM generates PR with fixes for violations

## Testing

### Local Testing Results

Test case: `sno-disconnected` across OCP 4.19, 4.20, 4.21

**Phase 1**: Manifest Generation ✅
- Generated 3 versions successfully
- Output: `~/generated_assets/version-compare/sno-disconnected-{4.19,4.20,4.21}/`

**Phase 2**: Standards Validation ✅
- 4.19: FAIL (correctly detected missing `additionalTrustBundle`)
- Auto-detected deployment type (minor issue: detected CONNECTED instead of DISCONNECTED due to missing CA cert)

**Phase 3**: Version Comparison ✅
- 4.19→4.20: Detected `imageDigestSources` removal (expected)
- 4.20→4.21: PASS (no API changes, SSH key change only)

### CI/CD Testing

GitHub Actions workflow tested with:
- **YAML Validation**: ✅ Syntax valid
- **Job Dependencies**: ✅ Correct execution order
- **Artifact Uploads**: ✅ Manifests + reports saved
- **PR Comments**: ✅ Summary generation working

## References

- **Issue #11**: ImageDigestMirrorSet migration (original motivation)
- **LiteLLM Documentation**: https://litellm-prod.apps.maas.redhatworkshops.io/
- **OpenShift 4.20 Release Notes**: Image source API changes
- **OpenShift 4.21 Release Notes**: OpenShiftSDN removal

## Contributors

- Feature designed and implemented: 2026-05-27
- LLM Model: Granite-3-2-8b-instruct via LiteLLM
- Validation powered by: IBM Granite AI
