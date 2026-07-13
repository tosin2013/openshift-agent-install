---
layout: default
title: "Deployment Standards: OpenShift 4.22"
parent: Reference
nav_order: 7
---

# OpenShift 4.22 Deployment Pattern Standards

Released June 9, 2026. Uses Kubernetes 1.35 with CRI-O 1.35 runtime. RHCOS based on RHEL 9.8.

## Deployment Types Supported
1. **Connected Standard** (default: internet-connected, public registries)
2. **Disconnected/Air-Gapped** (mirror registry, no internet)
3. **Proxy** (corporate proxy, restricted internet)
4. **SNO (Single Node OpenShift)** (single-node compact)
5. **3-Node Compact** (3 masters, no dedicated workers)
6. **HA (High Availability)** (3+ masters, 2+ workers)
7. **Edge** (resource-constrained, intermittent connectivity)

---

## CONNECTED STANDARD Deployment Standards

### Image Registry Configuration
- **NO** `imageDigestSources` or `imageContentSources` (uses public registries)
- **NO** `image-mirror-config.yaml` needed
- **MUST** have valid pull secret for registry.redhat.io

### Network Configuration
- **MANDATORY**: `networkType: OVNKubernetes` (OpenShiftSDN removed since 4.21)
- **MUST NOT** specify `OpenShiftSDN` (will fail installation)
- Gateway API CRD no longer restricted (available without TechPreview feature gate)

### Platform Configuration
- **SUPPORTED**: baremetal, vsphere, none, nutanix, external
- **MUST** set `platform_type` in cluster.yml
- Boot image management for control plane nodes is now GA on most platforms

---

## DISCONNECTED/AIR-GAPPED Deployment Standards

### Image Registry Configuration
- **MUST** use `ImageDigestMirrorSet` (IDMS) for mirror configuration
- **MUST NOT** use deprecated `ImageContentSourcePolicy` (ICSP)
- **MUST** configure mirror registry in install-config.yaml

### Mirror Registry Requirements
- **MUST** mirror all release images to local registry
- **MUST** include operator catalog images if using OLM operators
- **RECOMMENDED**: Use `oc-mirror` v2 for registry mirroring

### Network Configuration
- **MANDATORY**: `networkType: OVNKubernetes`
- **MUST** configure proxy settings if partial connectivity exists
- **MUST** include mirror registry CA in `additionalTrustBundle`

---

## Key Changes from 4.21

| Area | Change | Impact |
|------|--------|--------|
| RHCOS | Based on RHEL 9.8 | Updated kernel, drivers, hardware support |
| RHCOS 10.2 | Technology Preview | Optional: set `osImageStream: rhcos-10.2` with TechPreview feature set |
| Boot Images | Management GA | Control plane boot images auto-managed on supported platforms |
| Gateway API | CRD unrestricted | No longer requires TechPreview feature gate |
| Azure DNS | User-provisioned GA | Azure clusters can use existing DNS infrastructure |
| Observability | Unified stack | Logging integrated into Cluster Observability operator |
| OLM | v1 extensions | Next-gen Operator Lifecycle Manager maturing |

---

## Agent-Based Installer Specifics (4.22)

### Validated Configuration
- `ocp_version: "4.22"` in cluster.yml
- `openshift-install` binary version 4.22.x required
- Agent ISO uses RHCOS 9.8 base image
- Rendezvous IP must be a control plane node

### Install-Config Requirements
```yaml
networking:
  networkType: OVNKubernetes
platform:
  baremetal: {}          # or vsphere/none/nutanix
```

### Known Working Versions
- openshift-install 4.22.0 - 4.22.3
- oc CLI 4.22.x
- Kubernetes 1.35.x

---

## Validation Checklist

Before deploying OCP 4.22:

- [ ] `ocp_version: "4.22"` set in cluster.yml
- [ ] `network_type: OVNKubernetes` (mandatory)
- [ ] openshift-install binary matches 4.22.x
- [ ] Pull secret valid for registry.redhat.io
- [ ] Platform type set correctly (baremetal/vsphere/none/nutanix)
- [ ] For disconnected: IDMS configured (not ICSP)
- [ ] DNS entries configured for api.* and *.apps.*
- [ ] NTP servers configured (recommended)

---

## Forward Look: OpenShift 4.23 (In Development)

OpenShift 4.23 is currently in nightly builds (not yet GA). Based on CI streams, anticipated changes relevant to agent-based installation include:

| Feature | Status | Expected Impact |
|---------|--------|-----------------|
| MutableTopology | New feature gate | Day-2 topology changes for control plane |
| NetworkObservabilityInstall | Enabled by default | Built-in network flow monitoring |
| MachineAPIMigration (BareMetal) | New | Machine API v2 migration path for bare metal |
| Boot image auto-updates | Mandatory (IPI) | IPI clusters must allow boot image management |
| TLSGroupPreferences | New feature gate | Fine-grained TLS cipher configuration |
| OLMLifecycleAndCompatibility | New | OLM v1 lifecycle enforcement |
| UserNamespacesSupport | Unconditionally enabled | Pod-level user namespace isolation |

This repository will add `v4.23.0` support once GA is released (estimated Q4 2026 based on release cadence).

---

## References

- [OCP 4.22 Release Notes](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/release_notes/ocp-4-22-release-notes)
- [OCP 4.22 New Features Highlights](https://electromech.cloud/openshift-4-22-new-features-release-highlights/)
- [OpenShift Release Status](https://openshift-release.apps.ci.l2s4.p1.openshiftapps.com/)
- [Boot Images Update Roadmap](https://developers.redhat.com/articles/2025/08/18/roadmap-openshift-boot-images-update)
