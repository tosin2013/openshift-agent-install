---
layout: default
title: OpenShift 4.20 Deployment Pattern Standards
---

# OpenShift 4.20 Deployment Pattern Standards

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
- **RECOMMENDED**: `networkType: OVNKubernetes`
- **DEPRECATED**: `networkType: OpenShiftSDN` (works but warns)

### Platform Configuration
- **SUPPORTED**: baremetal, vsphere, none, nutanix, external
- **MUST** set `platform_type` in cluster.yml

---

## DISCONNECTED/AIR-GAPPED Deployment Standards

### Image Registry Configuration
- **MUST NOT** use `imageContentSources` in install-config.yaml (deprecated, removed in 4.20)
- **MUST NOT** use `imageDigestSources` in install-config.yaml (transitional, removed in 4.20)
- **MUST** use standalone `image-mirror-config.yaml` with `ImageDigestMirrorSet` API
- **MUST** have `disconnected_registries` list in cluster.yml with source→target mappings
- **MUST** have `additional_trust_bundle` for mirror registry CA certificate

### Network Configuration
- Same as connected (OVNKubernetes recommended)
- **MUST NOT** have external DNS dependencies in manifests

### Platform Configuration
- Same as connected
- **MUST** consider: how will nodes reach installation media without internet?

---

## PROXY Deployment Standards

### Proxy Configuration
- **MUST** set `proxy.httpProxy` and `proxy.httpsProxy` in install-config.yaml
- **MUST** set `proxy.noProxy` to exclude cluster networks, VIPs, and internal services
- **OPTIONAL**: May use `imageDigestSources` if using internal mirror alongside proxy

### Network Configuration
- Same as connected
- **MUST** ensure proxy allows OpenShift telemetry endpoints (or disable telemetry)

---

## SNO (Single Node OpenShift) Standards

### Node Configuration
- **MUST** set `control_plane_replicas: 1` and `app_node_replicas: 0`
- **MUST** set `platform_type: none` (no VIP support in SNO)
- **MUST** set `api_vips` and `app_vips` to same IP as node IP
- **MUST** set `rendezvous_ip` to node IP

### Resource Requirements
- **MINIMUM**: 8 vCPUs, 32 GB RAM, 120 GB disk
- **RECOMMENDED**: 16 vCPUs, 64 GB RAM for production workloads

---

## 3-NODE COMPACT Standards

### Node Configuration
- **MUST** set `control_plane_replicas: 3` and `app_node_replicas: 0`
- **CAN** use `platform_type: baremetal` or `none`
- **MUST** have 3 nodes in nodes.yml with `role: master`
- **MUST** set `rendezvous_ip` to one master's IP

### High Availability
- **MUST** have separate `api_vips` and `app_vips` (different from node IPs)
- **MUST** use `platform_type: baremetal` for automatic VIP management

---

## HA (High Availability) Standards

### Node Configuration
- **MUST** set `control_plane_replicas: 3` and `app_node_replicas: 2+`
- **MUST** use `platform_type: baremetal` or `vsphere` for VIP management
- **MUST** have separate `api_vips` and `app_vips`
- **MUST** have workers defined in nodes.yml with `role: worker`

### Load Balancing
- **REQUIRED**: VIPs for API and Ingress (managed by platform or external LB)
- **NOT RECOMMENDED**: `platform_type: none` for production HA clusters

---

## EDGE Deployment Standards

### Resource Optimization
- **RECOMMENDED**: SNO or 3-node compact topology
- **OPTIONAL**: Use `ImageTagMirrorSet` to reduce mirror registry size
- **RECOMMENDED**: Limit operator catalogs to required operators only

### Connectivity
- **MUST** plan for intermittent connectivity scenarios
- **RECOMMENDED**: Local mirror registry for disconnected periods
- **OPTIONAL**: Proxy configuration for connected periods

---

## Version-Specific Notes

### OpenShift 4.20 Highlights
- **ImageDigestMirrorSet** is now the standard for disconnected deployments
- **OpenShiftSDN** deprecated but still functional (removed in 4.21)
- **Nutanix** and **External** platform support added
- **ContainerRuntimeConfig** available as tech preview for AI/ML workloads
