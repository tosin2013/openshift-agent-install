# 🚀 Version Validation Cheatsheet

## Quick Commands

### Generate & Validate (Local)
```bash
# Generate manifests for all 3 versions
./hack/generate-version-manifests.sh sno-disconnected "4.19 4.20 4.21"

# Validate each
./hack/validate-deployment-standards.sh ~/generated_assets/version-compare/sno-disconnected-4.19 4.19
./hack/validate-deployment-standards.sh ~/generated_assets/version-compare/sno-disconnected-4.20 4.20
./hack/validate-deployment-standards.sh ~/generated_assets/version-compare/sno-disconnected-4.21 4.21

# Compare critical boundaries
./hack/compare-version-manifests.sh 4.19 4.20 sno-disconnected  # ImageDigestMirrorSet migration
./hack/compare-version-manifests.sh 4.20 4.21 sno-disconnected  # OpenShiftSDN removal
```

### GitHub Actions
```bash
# Trigger manually with issue creation
gh workflow run version-validation.yml \
  -f create_issues=true \
  -f examples="sno-disconnected ha-4.21-disconnected sno-4.20-standard"

# View latest run
gh run list --workflow=version-validation.yml --limit 1

# Download artifacts
gh run download <run-id>
```

## Critical Version Boundaries

| Boundary | Key Change | Impact |
|----------|-----------|---------|
| **4.19 → 4.20** | `imageDigestSources` removed from install-config.yaml | CRITICAL - Disconnected deployments must use standalone ImageDigestMirrorSet manifest |
| **4.20 → 4.21** | OpenShiftSDN removed completely | CRITICAL - networkType must be OVNKubernetes |

## LLM Integration

**Endpoint**: `https://litellm-prod.apps.maas.redhatworkshops.io/v1/chat/completions`  
**Model**: `granite-3-2-8b-instruct`  
**Auth**: Set `LITELLM_API_KEY` in `~/env`

```bash
# Setup
echo "LITELLM_API_KEY=sk-xxxxx" >> ~/env
chmod 600 ~/env
```

## Report Locations

```
~/generated_assets/version-compare/          # Generated manifests
~/generated_assets/validation-report-*.txt   # Validation reports
~/generated_assets/comparison-*.txt          # Comparison reports
```

## GitHub Workflow Triggers

**Automatic**: PR changes to:
- `playbooks/templates/**`
- `examples/**`
- `docs/deployment-standards-*.md`
- `hack/*version*.sh`

**Manual**: Actions → "Validate Manifests..." → Run workflow

## Deployment Standards

| Version | Image Sources | Network | Key Changes |
|---------|--------------|---------|-------------|
| **4.19** | `imageDigestSources` in install-config | OpenShiftSDN deprecated | Transitional API |
| **4.20** | Standalone `image-mirror-config.yaml` | OpenShiftSDN warning | ImageDigestMirrorSet mandatory |
| **4.21** | Standalone `image-mirror-config.yaml` | OVNKubernetes only | OpenShiftSDN removed |

## Deployment Types Covered

1. **Connected** - Public registries, internet access
2. **Disconnected** - Mirror registry, air-gapped
3. **Proxy** - Corporate proxy, restricted internet
4. **SNO** - Single node (replicas: 1,0)
5. **3-Node** - Compact cluster (replicas: 3,0)
6. **HA** - High availability (replicas: 3,2+)
7. **Edge** - Resource-constrained

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `LITELLM_API_KEY not set` | Create `~/env` with API key |
| Download OC CLI fails | Graceful fallback - continues with system CLI |
| Deployment type detection wrong | Ensure `additionalTrustBundle` exists (for disconnected) |
| Validation timeout | LLM API may be slow - wait or use fallback |

## Quick Reference Links

- **Quick Start**: `docs/version-validation-quick-start.md`
- **Full Docs**: `docs/version-validation-feature.md`
- **Standards**: `docs/deployment-standards-4.{19,20,21}.md`
- **Workflow**: `.github/workflows/version-validation.yml`

## Example Output

### ✅ PASS
```
[PASS] Image Registry Configuration
[PASS] Network Configuration
[PASS] Platform Configuration
[PASS] Deployment Topology
[PASS] Connectivity Requirements

Summary: Overall Status: PASS ✅
```

### ❌ FAIL
```
[FAIL] Image Registry Configuration
- Issue: imageContentSources in install-config.yaml (deprecated 4.20+)
- Remediation: Use standalone ImageDigestMirrorSet manifest
- Severity: CRITICAL

Summary: Overall Status: FAIL ❌
```

---
**Version**: 1.0.0 | **Deployed**: 2026-05-27 | **Model**: granite-3-2-8b-instruct
