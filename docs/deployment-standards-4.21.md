---
layout: default
title: "Deployment Standards: OpenShift 4.21"
parent: Reference
nav_order: 7
---

# OpenShift 4.21 Deployment Pattern Standards

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
- **MANDATORY**: `networkType: OVNKubernetes` (OpenShiftSDN removed in 4.21)
- **MUST NOT** specify `OpenShiftSDN` (will fail installation)

### Platform Configuration
- **SUPPORTED**: baremetal, vsphere, none, nutanix, external
- **MUST** set `platform_type` in cluster.yml

---

## DISCONNECTED/AIR-GAPPED Deployment Standards

### Image Registry Configuration
- **MUST NOT** use `imageContentSources` (removed)
- **MUST NOT** use `imageDigestSources` in install-config.yaml (removed)
- **MUST** use standalone `image-mirror-config.yaml` with `ImageDigestMirrorSet` API
- **MUST** have `disconnected_registries` list in cluster.yml
- **MUST** have `additional_trust_bundle` for mirror registry CA certificate

### Network Configuration
- **MANDATORY**: `networkType: OVNKubernetes`
- **MUST NOT** have external DNS dependencies

### Platform Configuration
- Same as connected

---

## PROXY Deployment Standards

### Proxy Configuration
- **MUST** set `proxy.httpProxy` and `proxy.httpsProxy`
- **MUST** set `proxy.noProxy` to exclude cluster networks, VIPs, internal services
- **OPTIONAL**: Use ImageDigestMirrorSet with internal mirror

### Network Configuration
- **MANDATORY**: `networkType: OVNKubernetes`
- **MUST** ensure proxy allows OpenShift endpoints

---

## SNO (Single Node OpenShift) Standards

### Node Configuration
- **MUST** set `control_plane_replicas: 1` and `app_node_replicas: 0`
- **MUST** set `platform_type: none`
- **MUST** set `api_vips` and `app_vips` to same IP as node IP
- **MUST** set `rendezvous_ip` to node IP

### Network Configuration
- **MANDATORY**: `networkType: OVNKubernetes`

### Resource Requirements
- **MINIMUM**: 8 vCPUs, 32 GB RAM, 120 GB disk
- **RECOMMENDED**: 16 vCPUs, 64 GB RAM for production

---

## 3-NODE COMPACT Standards

### Node Configuration
- **MUST** set `control_plane_replicas: 3` and `app_node_replicas: 0`
- **CAN** use `platform_type: baremetal` or `none`
- **MUST** have 3 nodes with `role: master`

### Network Configuration
- **MANDATORY**: `networkType: OVNKubernetes`

### High Availability
- **MUST** have separate `api_vips` and `app_vips`
- **RECOMMENDED**: Use `platform_type: baremetal` for VIP management

---

## HA (High Availability) Standards

### Node Configuration
- **MUST** set `control_plane_replicas: 3` and `app_node_replicas: 2+`
- **MUST** use `platform_type: baremetal` or `vsphere`
- **MUST** have separate VIPs
- **MUST** define workers with `role: worker`

### Network Configuration
- **MANDATORY**: `networkType: OVNKubernetes`

### Load Balancing
- **REQUIRED**: VIPs managed by platform or external LB

---

## EDGE Deployment Standards

### Resource Optimization
- **RECOMMENDED**: SNO or 3-node compact
- **OPTIONAL**: Use `ImageTagMirrorSet` for reduced mirror size

### Network Configuration
- **MANDATORY**: `networkType: OVNKubernetes`

### Connectivity
- **MUST** plan for intermittent connectivity
- **RECOMMENDED**: Local mirror registry

---

## Version-Specific Notes

### OpenShift 4.21 Breaking Changes
- **OpenShiftSDN REMOVED** - All clusters must use OVNKubernetes
- **imageDigestSources REMOVED** from install-config.yaml
- **imageContentSources REMOVED** from install-config.yaml
- **ONLY** ImageDigestMirrorSet supported for disconnected (standalone manifest)

### Migration from 4.20
- Change `networkType: OpenShiftSDN` → `networkType: OVNKubernetes`
- Ensure ImageDigestMirrorSet manifests are generated (not in install-config)
- Test network policies (OVN has different behavior from OpenShiftSDN)
