# Version Validation Quick Start

## Prerequisites

1. **LiteLLM API Key**: Add to `~/env`
   ```bash
   echo "LITELLM_API_KEY=sk-xxxxx" >> ~/env
   ```

2. **Required Tools**: Ansible, jq, curl
   ```bash
   pip install ansible-core
   sudo dnf install -y jq curl
   ```

## Quick Test

### 1. Generate Manifests

```bash
./hack/generate-version-manifests.sh sno-disconnected "4.19 4.20 4.21"
```

**Output**: `~/generated_assets/version-compare/sno-disconnected-{4.19,4.20,4.21}/`

### 2. Validate Each Version

```bash
# Validate 4.19
./hack/validate-deployment-standards.sh \
  ~/generated_assets/version-compare/sno-disconnected-4.19 4.19

# Validate 4.20
./hack/validate-deployment-standards.sh \
  ~/generated_assets/version-compare/sno-disconnected-4.20 4.20

# Validate 4.21
./hack/validate-deployment-standards.sh \
  ~/generated_assets/version-compare/sno-disconnected-4.21 4.21
```

**Report Location**: `generated_assets/validation-report-<example>-<version>.txt`

### 3. Compare Versions

```bash
# Critical boundary: 4.19 → 4.20 (imageDigestSources migration)
./hack/compare-version-manifests.sh 4.19 4.20 sno-disconnected

# Critical boundary: 4.20 → 4.21 (OpenShiftSDN removal)
./hack/compare-version-manifests.sh 4.20 4.21 sno-disconnected
```

**Report Location**: `~/generated_assets/comparison-<example>-<base>-to-<target>.txt`

## Understanding Results

### Validation Report

**PASS Example**:
```
[PASS] Image Registry Configuration
[PASS] Network Configuration
[PASS] Platform Configuration
[PASS] Deployment Topology
[PASS] Connectivity Requirements

Summary: Overall Status: PASS ✅
```

**FAIL Example**:
```
[FAIL] Image Registry Configuration
- Issue: imageContentSources found in install-config.yaml (deprecated in 4.20+)
- Remediation: Use standalone image-mirror-config.yaml with ImageDigestMirrorSet
- Severity: CRITICAL

Summary: Overall Status: FAIL ❌
```

### Comparison Report

**Expected Changes** (4.19→4.20):
```
1. What changed?
   - imageDigestSources removed from install-config.yaml ✓
   - Standalone image-mirror-config.yaml added ✓

2. Are changes expected?
   - [PASS] imageDigestSources migration is expected per 4.20 standards

3. Violations?
   - [PASS] No violations detected
```

**Unexpected Changes**:
```
3. Violations?
   - [FAIL] OpenShiftSDN still in use (deprecated in 4.21)
   - Remediation: Change networkType to OVNKubernetes
```

## Common Issues

### Issue: "LITELLM_API_KEY not set"

**Solution**:
```bash
# Create ~/env file
echo "LITELLM_API_KEY=sk-xxxxx" > ~/env
chmod 600 ~/env
```

### Issue: "Failed to download OC CLI"

**Behavior**: Script continues with system CLI (graceful degradation)

**Optional Fix**: Pre-cache CLI versions
```bash
mkdir -p ~/.cache/ocp-cli/{4.19,4.20,4.21}
# Download and place oc binaries in each directory
```

### Issue: Deployment Type Detection Wrong

**Symptom**: Detected "CONNECTED" but should be "DISCONNECTED"

**Cause**: Missing `additionalTrustBundle` in generated manifest

**Solution**: Ensure CA cert file exists:
```bash
# For disconnected examples, create dummy CA cert
mkdir -p ~/
cat > ~/mirror-registry-ca.pem << 'EOF'
-----BEGIN CERTIFICATE-----
(your mirror registry CA certificate)
-----END CERTIFICATE-----
EOF
```

### Issue: Validation Takes Too Long

**Timeout**: Default 60s for LLM API calls

**If API is slow**:
- Check LiteLLM endpoint status
- Use fallback mode (works without LLM)
- Increase timeout in script if needed

## GitHub Actions

### Automatic Validation

Runs automatically on PRs that modify:
- Template files (`playbooks/templates/**`)
- Example configs (`examples/**`)
- Deployment standards (`docs/deployment-standards-*.md`)

### Manual Trigger

**Via GitHub UI**:
1. Go to Actions → "Validate Manifests Across OpenShift Versions"
2. Click "Run workflow"
3. Select options:
   - `create_issues`: true (creates GitHub issues for failures)
   - `examples`: Space-separated list (e.g., "sno-disconnected ha-4.21-disconnected")

**Via GitHub CLI**:
```bash
gh workflow run version-validation.yml \
  -f create_issues=true \
  -f examples="sno-disconnected ha-4.21-disconnected sno-4.20-standard"
```

### View Results

**PR Comments**: Automated summary posted to PR
**Artifacts**: Download validation/comparison reports (retention: 30 days)

## Testing Multiple Examples

```bash
# Test all representative deployment types
for example in sno-disconnected ha-4.21-disconnected sno-4.20-standard; do
  echo "Testing: $example"
  ./hack/generate-version-manifests.sh "$example" "4.19 4.20 4.21"

  for version in 4.19 4.20 4.21; do
    ./hack/validate-deployment-standards.sh \
      ~/generated_assets/version-compare/${example}-${version} ${version}
  done

  ./hack/compare-version-manifests.sh 4.19 4.20 "$example"
  ./hack/compare-version-manifests.sh 4.20 4.21 "$example"
done
```

## Deployment Types Covered

1. **SNO Connected**: `sno-4.20-standard`
2. **SNO Disconnected**: `sno-disconnected`
3. **HA Disconnected**: `ha-4.21-disconnected`
4. **3-Node Compact**: `3-node-example` (if exists)
5. **Proxy**: `proxy-example` (if exists)
6. **Bond + VLAN**: `cnv-bond0-tagged`

## Best Practices

1. **Run validation before committing template changes**
2. **Test against all 3 stable versions** (4.19, 4.20, 4.21)
3. **Review LLM remediation suggestions** (don't blindly apply)
4. **Compare critical boundaries** (4.19→4.20, 4.20→4.21)
5. **Create issues for persistent violations** (use `--create-issue`)

## Next Steps

- Read full documentation: `docs/version-validation-feature.md`
- Review deployment standards: `docs/deployment-standards-4.{19,20,21}.md`
- Explore example configs: `examples/*/`
- Check GitHub Actions results: `.github/workflows/version-validation.yml`

## Support

- **LLM Issues**: Check `~/env` for API key, verify LiteLLM endpoint
- **Manifest Generation**: Ensure Ansible collections installed
- **Template Bugs**: Review validation reports for remediation steps
- **GitHub Actions**: Check workflow logs for detailed error messages
