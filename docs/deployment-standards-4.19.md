---
layout: default
title: OpenShift 4.19 Deployment Pattern Standards
---

# OpenShift 4.19 Deployment Pattern Standards

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
- **SUPPORTED**: `networkType: OVNKubernetes` or `OpenShiftSDN`
- **RECOMMENDED**: `OVNKubernetes` (OpenShiftSDN deprecated)

### Platform Configuration
- **SUPPORTED**: baremetal, vsphere, none
- **MUST** set `platform_type` in cluster.yml

---

## DISCONNECTED/AIR-GAPPED Deployment Standards

### Image Registry Configuration
- **RECOMMENDED**: Use `imageDigestSources` in install-config.yaml (transitional API)
- **DEPRECATED**: `imageContentSources` (still works but deprecated since 4.14)
- **MUST** have `disconnected_registries` list in cluster.yml
- **MUST** have `additional_trust_bundle` for mirror registry CA certificate

### Alternative Approach (Forward-Compatible)
- **OPTIONAL**: Generate standalone `ImageDigestMirrorSet` manifest for 4.20+ compatibility
- See imagedigestmirrorset.yml.j2 template

### Network Configuration
- Same as connected
- **MUST NOT** have external DNS dependencies

---

## PROXY Deployment Standards

### Proxy Configuration
- **MUST** set `proxy.httpProxy` and `proxy.httpsProxy`
- **MUST** set `proxy.noProxy` to exclude cluster networks and VIPs
- **OPTIONAL**: Use `imageDigestSources` with internal mirror

### Network Configuration
- Same as connected
- **MUST** ensure proxy allows OpenShift endpoints

---

## SNO (Single Node OpenShift) Standards

### Node Configuration
- **MUST** set `control_plane_replicas: 1` and `app_node_replicas: 0`
- **MUST** set `platform_type: none`
- **MUST** set `api_vips` and `app_vips` to same IP as node IP
- **MUST** set `rendezvous_ip` to node IP

### Resource Requirements
- **MINIMUM**: 8 vCPUs, 32 GB RAM, 120 GB disk
- **RECOMMENDED**: 16 vCPUs, 64 GB RAM for production

---

## 3-NODE COMPACT Standards

### Node Configuration
- **MUST** set `control_plane_replicas: 3` and `app_node_replicas: 0`
- **CAN** use `platform_type: baremetal` or `none`
- **MUST** have 3 nodes with `role: master`

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

### Load Balancing
- **REQUIRED**: VIPs managed by platform or external LB

---

## EDGE Deployment Standards

### Resource Optimization
- **RECOMMENDED**: SNO or 3-node compact
- **OPTIONAL**: Reduce operator catalogs

### Connectivity
- **MUST** plan for intermittent connectivity
- **RECOMMENDED**: Local mirror registry

---

## Version-Specific Notes

### OpenShift 4.19 Highlights
- **imageDigestSources** transitional API (recommended for disconnected)
- **OpenShiftSDN** still supported but deprecated
- **OVNKubernetes** recommended for new deployments
- Last version supporting `imageContentSources` (use `imageDigestSources` instead)
