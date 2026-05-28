---
layout: default
title: OpenShift Version Compatibility Matrix
parent: Advanced Topics
nav_order: 4
---

# OpenShift Version Compatibility Matrix

## Overview

This matrix documents supported OpenShift versions, critical API changes, and migration paths for the Agent-Based Installer deployment patterns.

## Supported Versions

| Version | Release Date | End of Life | Support Status | Recommended For |
|---------|--------------|-------------|----------------|-----------------|
| **4.19** | Q2 2025 | Jan 2026 | ✅ Fully Supported | Legacy deployments, transitional workloads |
| **4.20** | Q3 2025 | May 2026 | ✅ Current Stable | Production deployments, new installations |
| **4.21** | Q4 2025 | Oct 2026 | ✅ Latest Release | Modern deployments, new features |
| **4.22** | Q1 2026 (preview) | TBD | ⚠️ Preview/RC | Testing, early adoption |

## Critical API Changes by Version

### 4.19 → 4.20 (CRITICAL BOUNDARY)

**Breaking Changes**:
- ❌ **imageContentSources removed** from install-config.yaml
- ❌ **imageDigestSources removed** from install-config.yaml
- ✅ **ImageDigestMirrorSet** becomes mandatory (standalone manifest)

**Migration Impact**:
```yaml
# 4.19 - DEPRECATED (but functional)
imageContentSources:
  - source: registry.redhat.io
    mirrors:
      - mirror.example.com

# 4.19 - TRANSITIONAL (recommended)
imageDigestSources:
  - source: registry.redhat.io
    mirrors:
      - mirror.example.com

# 4.20+ - REQUIRED
# Move to standalone image-mirror-config.yaml
apiVersion: config.openshift.io/v1
kind: ImageDigestMirrorSet
metadata:
  name: image-mirror-set
spec:
  imageDigestMirrors:
  - source: registry.redhat.io
    mirrors:
    - mirror.example.com
```

**Deployment Pattern Changes**:

| Deployment Type | 4.19 Approach | 4.20+ Approach |
|-----------------|---------------|----------------|
| **Disconnected** | `imageDigestSources` in install-config | Standalone `image-mirror-config.yaml` |
| **Connected** | No changes | No changes |
| **Proxy** | Optional mirror config | Same as 4.19 |

**Validation**:
```bash
# Generate manifests for both versions
./hack/generate-version-manifests.sh sno-disconnected "4.19 4.20"

# Compare critical boundary
./hack/compare-version-manifests.sh 4.19 4.20 sno-disconnected

# Validate 4.20 compliance
./hack/validate-deployment-standards.sh \
  ~/generated_assets/version-compare/sno-disconnected-4.20 4.20
```

### 4.20 → 4.21 (CRITICAL BOUNDARY)

**Breaking Changes**:
- ❌ **OpenShiftSDN removed completely**
- ✅ **OVNKubernetes mandatory** (networkType enforcement)

**Migration Impact**:
```yaml
# 4.19-4.20 - DEPRECATED (but functional)
networking:
  networkType: OpenShiftSDN

# 4.21+ - REQUIRED
networking:
  networkType: OVNKubernetes
```

**Network Configuration Changes**:

| Feature | 4.19-4.20 (OpenShiftSDN) | 4.21+ (OVNKubernetes) |
|---------|--------------------------|------------------------|
| **Network Policy** | NetworkPolicy API | Same, enhanced performance |
| **Egress IP** | EgressNetworkPolicy | EgressIP (CRD-based) |
| **Multicast** | Supported | Supported (different implementation) |
| **Hybrid Networking** | Limited | Full support (OVN-Kubernetes native) |
| **IPsec** | Not supported | Supported |

**Pre-Migration Testing**:
```bash
# Test 4.20 with OVNKubernetes before upgrading to 4.21
# In cluster.yml:
network_type: OVNKubernetes

# Generate and validate
./hack/create-iso.sh sno-4.20-standard
```

### 4.21 → 4.22 (Preview Features)

**Upcoming Features**:
- ✅ **ContainerRuntimeConfig** for AI/ML workloads (GPU, specialized runtimes)
- ✅ **Enhanced ImageTagMirrorSet** support (tag-based mirroring)
- ✅ **Improved Metal³ integration** (bare metal provisioning)

**Preview Testing** (when 4.22-rc available):
```bash
# Test pre-release versions
./hack/generate-version-manifests.sh sno-disconnected "4.21 4.22-rc.1"
./hack/compare-version-manifests.sh 4.21 4.22-rc.1 sno-disconnected
```

## Deployment Pattern Compatibility Matrix

### Disconnected/Air-Gapped Deployments

| Feature | 4.19 | 4.20 | 4.21 | Notes |
|---------|------|------|------|-------|
| Mirror Registry | ✅ | ✅ | ✅ | Required for all versions |
| imageContentSources | ⚠️ Deprecated | ❌ Removed | ❌ Removed | Use ImageDigestMirrorSet |
| imageDigestSources | ✅ Transitional | ❌ Removed | ❌ Removed | Use standalone manifest |
| ImageDigestMirrorSet | ✅ Recommended | ✅ Required | ✅ Required | Standalone manifest only |
| ImageTagMirrorSet | ❌ | ⚠️ Tech Preview | ✅ GA | Tag-based mirroring |
| Additional Trust Bundle | ✅ | ✅ | ✅ | CA cert for mirror registry |

### Network Configuration

| Feature | 4.19 | 4.20 | 4.21 | Notes |
|---------|------|------|------|-------|
| OpenShiftSDN | ✅ Default | ⚠️ Deprecated | ❌ Removed | Migrate before 4.21 |
| OVNKubernetes | ✅ Supported | ✅ Recommended | ✅ Required | Default in 4.21+ |
| Dual-stack IPv4/IPv6 | ✅ | ✅ | ✅ | OVN-Kubernetes only |
| IPsec encryption | ❌ | ⚠️ Tech Preview | ✅ GA | OVN-Kubernetes feature |

### Platform Support

| Platform | 4.19 | 4.20 | 4.21 | Notes |
|----------|------|------|------|-------|
| Bare Metal (platform: baremetal) | ✅ | ✅ | ✅ | VIP management included |
| Platform None (platform: none) | ✅ | ✅ | ✅ | Manual VIP setup required |
| vSphere | ✅ | ✅ | ✅ | Full integration |
| Nutanix | ✅ | ✅ | ✅ | Agent-Based Installer supported |
| External (platform: external) | ⚠️ Tech Preview | ✅ GA | ✅ | Third-party platform integration |

### Deployment Topology

| Topology | 4.19 | 4.20 | 4.21 | Resource Requirements |
|----------|------|------|------|----------------------|
| **SNO** (Single Node) | ✅ | ✅ | ✅ | 8 vCPU, 32GB RAM minimum |
| **3-Node Compact** | ✅ | ✅ | ✅ | 8 vCPU, 32GB RAM per node |
| **HA** (3 masters + workers) | ✅ | ✅ | ✅ | Standard HA requirements |
| **Edge** (resource-constrained) | ✅ | ✅ | ✅ | SNO or 3-node recommended |

## Migration Paths

### Migrating from 4.19 to 4.20

**For Disconnected Deployments**:

1. **Before Upgrade**:
   ```bash
   # Generate 4.19 manifests with imageDigestSources (transitional API)
   # Already in install-config.yaml
   ```

2. **After Upgrade to 4.20**:
   ```bash
   # Extract imageDigestSources to standalone manifest
   cat > image-mirror-config.yaml <<EOF
   apiVersion: config.openshift.io/v1
   kind: ImageDigestMirrorSet
   metadata:
     name: image-mirror-set
   spec:
     imageDigestMirrors:
     - source: registry.redhat.io
       mirrors:
       - mirror.example.com:5000
   EOF
   
   # Remove imageDigestSources from install-config.yaml
   # (Automatically handled by templates when ocp_version >= 4.20)
   ```

3. **Validate**:
   ```bash
   ./hack/validate-deployment-standards.sh \
     ~/generated_assets/my-cluster 4.20
   ```

### Migrating from 4.20 to 4.21

**For All Deployments** (Network Type Change):

1. **Pre-Upgrade** (on 4.20):
   ```bash
   # Switch to OVNKubernetes before upgrading
   # In cluster.yml:
   network_type: OVNKubernetes
   
   # Redeploy cluster with OVN-Kubernetes
   ./hack/create-iso.sh my-cluster
   ```

2. **After Upgrade to 4.21**:
   - No manual network changes required
   - OpenShiftSDN is no longer available

3. **Validate**:
   ```bash
   # Verify network plugin
   oc get network.config.openshift.io cluster -o yaml | grep networkType
   # Should show: networkType: OVNKubernetes
   ```

## Version-Specific Validation

### Automated Validation Workflow

**Local Testing**:
```bash
# Generate manifests for all supported versions
./hack/generate-version-manifests.sh sno-disconnected "4.19 4.20 4.21"

# Validate each version against deployment standards
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

**CI/CD Integration**:
```bash
# Trigger GitHub Actions workflow
gh workflow run version-validation.yml \
  -f create_issues=true \
  -f examples="sno-disconnected ha-4.21-disconnected"
```

## Deployment Standards Documentation

Version-specific deployment standards are documented separately:

- **4.19**: [docs/deployment-standards-4.19.md](deployment-standards-4.19.md)
- **4.20**: [docs/deployment-standards-4.20.md](deployment-standards-4.20.md)
- **4.21**: [docs/deployment-standards-4.21.md](deployment-standards-4.21.md)

Each document covers:
- Image registry configuration (connected, disconnected, proxy)
- Network configuration (SDN vs OVN-Kubernetes)
- Platform requirements (baremetal, vsphere, none)
- Deployment topology (SNO, 3-node, HA)
- Connectivity patterns (connected, disconnected, proxy, edge)

## LLM-Powered Validation

The version validation feature uses **Granite-3-2-8b-instruct** LLM for intelligent manifest analysis:

### What the LLM Validates

1. **API Compliance**: Detects deprecated/removed APIs per version
2. **Deployment Pattern Standards**: Validates SNO/HA/3-Node specific requirements
3. **Connectivity Requirements**: Checks disconnected, proxy, connected configurations
4. **Platform Configuration**: Validates platform-specific settings (VIPs, networking)
5. **Version Boundaries**: Identifies critical migration paths

### Example LLM Output

```
[PASS] Image Registry Configuration
- OCP 4.20 correctly uses standalone ImageDigestMirrorSet
- No deprecated imageContentSources or imageDigestSources in install-config.yaml

[FAIL] Network Configuration
- Issue: networkType: OpenShiftSDN detected
- Remediation: Update cluster.yml with network_type: OVNKubernetes before 4.21 upgrade
- Severity: WARNING (critical for 4.21 migration)

[PASS] Platform Configuration
- platform: none is valid for SNO deployment
- VIPs correctly configured for single-node topology

[PASS] Deployment Topology
- SNO topology detected (replicas: 1,0)
- Resource requirements met
```

## Quick Reference

### Version Selection Guide

**Choose 4.19 if**:
- Existing infrastructure requires OpenShiftSDN
- Migration to OVN-Kubernetes not yet tested
- Need transitional period before 4.20 API changes

**Choose 4.20 if**:
- New production deployments
- Ready to adopt ImageDigestMirrorSet API
- Want stable release with latest features
- Planning 4.21 upgrade path

**Choose 4.21 if**:
- New deployments (recommended)
- Already using OVN-Kubernetes
- Need latest features and security updates
- Modern network stack requirements (IPsec, hybrid networking)

### Common Issues and Solutions

| Issue | Version | Solution |
|-------|---------|----------|
| "imageContentSources field not found" | 4.20+ | Use standalone ImageDigestMirrorSet manifest |
| "OpenShiftSDN not supported" | 4.21+ | Change networkType to OVNKubernetes |
| "imageDigestSources deprecated" | 4.19 | Working as intended (transitional API) |
| Disconnected deployment fails | 4.20+ | Ensure image-mirror-config.yaml exists |
| Network plugin mismatch | 4.21+ | Verify networkType: OVNKubernetes in all configs |

## Additional Resources

- **Feature Documentation**: [docs/version-validation-feature.md](version-validation-feature.md)
- **Quick Start Guide**: [docs/version-validation-quick-start.md](version-validation-quick-start.md)
- **Cheat Sheet**: [VERSION_VALIDATION_CHEATSHEET.md](../VERSION_VALIDATION_CHEATSHEET.md)
- **GitHub Workflow**: [.github/workflows/version-validation.yml](../.github/workflows/version-validation.yml)

## Release Notes

- **v1.0.0** (2026-05-27): Initial release with LLM-powered validation
  - Support for OpenShift 4.19, 4.20, 4.21
  - Automated GitHub Actions integration
  - Deployment standards validation
  - Version comparison and migration guidance

---

**Last Updated**: 2026-05-27  
**Validation Model**: granite-3-2-8b-instruct via LiteLLM API  
**Maintainer**: OpenShift Agent-Based Installer Team
