---
layout: default
title: Configuration Reference
description: Comprehensive configuration guide for OpenShift Agent-based installations
parent: Reference
nav_order: 1
---

# Configuration Guide

This guide provides detailed information about configuring OpenShift Agent-based installations.

## Configuration Files Overview

The Agent-Based Installer uses two primary configuration files:
- **cluster.yml** - Cluster-wide settings (networking, platform, versions)
- **nodes.yml** - Node-specific settings (hardware, network interfaces, storage)

---

## cluster.yml Complete Parameter Reference

**Location**: `examples/<cluster-name>/cluster.yml`

### Required Parameters

| Parameter | Type | Description | Example | Notes |
|-----------|------|-------------|---------|-------|
| `cluster_name` | string | Cluster identifier used in FQDN | `sno-4-20` | Alphanumeric + hyphens |
| `base_domain` | string | DNS base domain for cluster | `example.com` | Must have DNS records |
| `platform_type` | string | Platform type | `none`, `baremetal`, `vsphere`, `nutanix` | SNO must use `none` |
| `control_plane_replicas` | integer | Number of control plane nodes | `1` (SNO), `3` (HA) | 1 or 3 only |
| `app_node_replicas` | integer | Number of worker nodes | `0` (SNO/compact), `2+` (HA) | 0 for compact clusters |
| `api_vips` | list | API endpoint VIP addresses | `- 192.168.50.21` | Dual-stack: 2 IPs |
| `app_vips` | list | Ingress VIP addresses | `- 192.168.50.21` | SNO: same as node IP |
| `machine_network_cidrs` | list | Node network CIDRs | `- 192.168.50.0/24` | Must match node IPs |
| `cluster_network_cidr` | string | Pod network CIDR | `10.128.0.0/14` | Default works for most |
| `cluster_network_host_prefix` | integer | Subnet prefix per node | `23` | Affects pod count/node |
| `service_network_cidrs` | list | Service network CIDRs | `- 172.30.0.0/16` | Default works for most |
| `network_type` | string | Network provider | `OVNKubernetes` | **4.21+**: OVN only (SDN removed) |
| `rendezvous_ip` | string | Bootstrap node IP | `192.168.50.21` | SNO: matches node IP |
| `pull_secret_path` | string | Path to pull secret | `~/pull-secret.json` | Download from console.redhat.com |

### Optional Parameters

| Parameter | Type | Description | Default | Valid For |
|-----------|------|-------------|---------|-----------|
| `ocp_version` | string | OpenShift version | auto-detect | `"4.19"`, `"4.20"`, `"4.21"` |
| `ssh_public_key_path` | string | Path to SSH public key | auto-generate | Any file path |
| `dns_servers` | list | DNS server IPs | None | e.g., `- 192.168.122.1` |
| `dns_search_domains` | list | DNS search domains | None | e.g., `- example.com` |
| `ntp_servers` | list | NTP server addresses | RHEL defaults | e.g., `- 0.rhel.pool.ntp.org` |
| `use_site_configs` | boolean | Use site-specific configs | `false` | Advanced users |
| `cluster_architecture` | string | CPU architecture | `x86_64` | `x86_64`, `aarch64`, `ppc64le`, `s390x` |
| `create_ztp_manifests` | boolean | Generate ZTP manifests | `false` | RHACM/ZTP workflows |

### Disconnected/Air-Gap Parameters

**Required for disconnected installations:**

| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `disconnected_registries` | list | Mirror registry mappings | See below |
| `additional_trust_bundle_path` | string | Mirror CA cert path | `~/mirror-ca.crt` |
| `additional_trust_bundle_policy` | string | CA policy | `"Always"` or `"Proxyonly"` |
| `image_content_sources` | list | Image source mirrors | See disconnected guide |

**disconnected_registries format:**
```yaml
disconnected_registries:
  - source: quay.io
    target: mirror-registry.example.com:8443/quay-io
  - source: registry.redhat.io
    target: mirror-registry.example.com:8443/redhat-io
```

### UpdateService Parameters (Disconnected Updates)

**Required when `deploy_update_service: true`:**

| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `deploy_update_service` | boolean | Enable UpdateService | `true` |
| `update_service_graph_image` | string | Graph data image with digest | `mirror.io/graph@sha256:abc123...` |
| `update_service_releases` | string | Releases path in mirror | `mirror.io/ocp-release-dev/ocp-release` |
| `update_service_replicas` | integer | Number of replicas | `2` (HA), `1` (SNO) |

### Proxy Parameters

```yaml
proxy:
  http_proxy: http://192.168.42.31:3128
  https_proxy: http://192.168.42.31:3128
  no_proxy:
    - .svc.cluster.local
    - 192.168.0.0/16
    - .example.com
```

### Version-Specific Notes

#### OpenShift 4.19
- `network_type`: `OVNKubernetes` or `OpenShiftSDN` (deprecated)
- Uses `ImageContentSourcePolicy` for disconnected

#### OpenShift 4.20
- `network_type`: `OVNKubernetes` (recommended) or `OpenShiftSDN` (deprecated)
- Migrates to `ImageDigestMirrorSet` (critical boundary)
- `ocp_version: "4.20"` triggers version validation

#### OpenShift 4.21+
- `network_type`: **MUST be `OVNKubernetes`** (OpenShiftSDN removed)
- `nutanix` platform support added
- UpdateService support for disconnected upgrades

### Example: SNO with Standard Networking

```yaml
use_site_configs: false
pull_secret_path: ~/pull-secret.json
ocp_version: "4.20"

cluster_name: sno-4-20
base_domain: example.com
platform_type: none

control_plane_replicas: 1
app_node_replicas: 0

api_vips:
  - 192.168.50.21
app_vips:
  - 192.168.50.21

ntp_servers:
  - 0.rhel.pool.ntp.org
  - 1.rhel.pool.ntp.org

dns_servers:
  - 192.168.122.1  # Libvirt dnsmasq for KVM deployments

cluster_network_cidr: 10.128.0.0/14
cluster_network_host_prefix: 23
service_network_cidrs:
  - 172.30.0.0/16
machine_network_cidrs:
  - 192.168.50.0/24  # VLAN 1924 standard

network_type: OVNKubernetes
rendezvous_ip: 192.168.50.21
```

### Example: HA Cluster

```yaml
use_site_configs: false
pull_secret_path: ~/pull-secret.json
ocp_version: "4.21"

cluster_name: ha-prod
base_domain: example.com
platform_type: baremetal

control_plane_replicas: 3
app_node_replicas: 3

api_vips:
  - 192.168.50.252
app_vips:
  - 192.168.50.253

dns_servers:
  - 192.168.122.1

machine_network_cidrs:
  - 192.168.50.0/24

network_type: OVNKubernetes
rendezvous_ip: 192.168.50.21  # First control plane node
```

---

## nodes.yml Complete Parameter Reference

**Location**: `examples/<cluster-name>/nodes.yml`

### Top-Level Parameters

| Parameter | Type | Required | Description | Example |
|-----------|------|----------|-------------|---------|
| `control_plane_replicas` | integer | Yes | Number of control plane nodes | `1` (SNO), `3` (HA) |
| `app_node_replicas` | integer | Yes | Number of worker nodes | `0` (compact), `2+` (HA) |
| `nodes` | list | Yes | List of node definitions | See below |

### Node Definition Parameters

Each entry in the `nodes` list:

| Parameter | Type | Required | Description | Example |
|-----------|------|----------|-------------|---------|
| `hostname` | string | Yes | Node hostname | `master-0`, `worker-1` |
| `role` | string | No | Node role (omit for SNO) | `master`, `worker` |
| `interfaces` | list | Yes | Network interface definitions | See below |
| `rootDeviceHints` | object | Yes | Root disk selection | See below |
| `networkConfig` | object | Yes | NMState network configuration | See below |

### Interface Parameters

| Parameter | Type | Required | Description | Example |
|-----------|------|----------|-------------|---------|
| `name` | string | Yes | Interface name | `enp1s0`, `ens192`, `bond0` |
| `mac_address` | string | Yes | MAC address | `"52:54:00:00:00:01"` |

### Root Device Hints

| Parameter | Type | Description | Example | Notes |
|-----------|------|-------------|---------|-------|
| `deviceName` | string | Device path | `/dev/sda`, `/dev/nvme0n1` | Most common |
| `hctl` | string | SCSI address | `"0:0:0:0"` | For multipath |
| `model` | string | Device model | `"SSD"` | Fuzzy match |
| `vendor` | string | Device vendor | `"Samsung"` | Fuzzy match |
| `serialNumber` | string | Serial number | `"abc123"` | Exact match |
| `minSizeGigabytes` | integer | Minimum size (GB) | `120` | For size filtering |
| `wwn` | string | World Wide Name | `"0x50014ee..."` | SAN storage |
| `wwnWithExtension` | string | WWN with extension | `"0x50014ee...01"` | LUN identification |
| `wwnVendorExtension` | string | WWN vendor extension | `"0x50014ee..."` | Vendor-specific |
| `rotational` | boolean | Rotational disk | `false` (SSD) | Filter by type |

**Example** (multipath SAN storage):
```yaml
rootDeviceHints:
  wwn: "0x50014ee2b5d8e5c8"
  wwnWithExtension: "0x50014ee2b5d8e5c801"
```

### Network Configuration (NMState Format)

#### Interface Types

**Ethernet Interface:**
```yaml
- name: enp1s0
  type: ethernet
  state: up
  mac-address: "52:54:00:00:00:01"
  ipv4:
    enabled: true
    address:
      - ip: 192.168.50.21
        prefix-length: 24
    dhcp: false
```

**VLAN Interface:**
```yaml
- name: enp1s0.1924
  type: vlan
  state: up
  vlan:
    base-iface: enp1s0
    id: 1924
  ipv4:
    enabled: true
    address:
      - ip: 192.168.50.21
        prefix-length: 24
    dhcp: false
```

**Bond Interface:**
```yaml
- name: bond0
  type: bond
  state: up
  ipv4:
    enabled: true
    dhcp: false
  link-aggregation:
    mode: 802.3ad  # LACP
    options:
      miimon: '140'
    port:
      - enp1s0
      - enp2s0
```

**Bond + VLAN (Production Pattern):**
```yaml
- name: bond0
  type: bond
  state: up
  ipv4:
    dhcp: false
    enabled: true
  link-aggregation:
    mode: 802.3ad
    options:
      miimon: '140'
    port:
      - enp1s0
      - enp2s0

- name: bond0.1924
  type: vlan
  state: up
  vlan:
    base-iface: bond0
    id: 1924
  ipv4:
    address:
      - ip: 192.168.50.21
        prefix-length: 24
    dhcp: false
    enabled: true
```

#### Bond Modes

| Mode | Description | Use Case | Switch Support |
|------|-------------|----------|----------------|
| `802.3ad` | LACP (Link Aggregation) | Production, load balancing | LACP required |
| `active-backup` | Active/passive failover | Simple redundancy | Any switch |
| `balance-rr` | Round-robin load balancing | Testing only | Avoid in production |
| `balance-xor` | XOR hash load balancing | Alternative to LACP | Static LAG |

#### Routing Configuration

```yaml
routes:
  config:
    - destination: 0.0.0.0/0
      next-hop-address: 192.168.50.1
      next-hop-interface: bond0.1924
      table-id: 254  # Main routing table
```

#### DNS Resolver Configuration

```yaml
dns-resolver:
  config:
    server:
      - 192.168.122.1
      - 8.8.8.8
```

### Complete Example: SNO with Bond + VLAN

```yaml
control_plane_replicas: 1
app_node_replicas: 0

nodes:
  - hostname: sno-node
    rootDeviceHints:
      deviceName: /dev/sda
    interfaces:
      - name: enp1s0
        mac_address: "52:54:00:19:04:73"
      - name: enp2s0
        mac_address: "52:54:00:27:dd:40"
    networkConfig:
      interfaces:
        # Bond interface
        - name: bond0
          type: bond
          state: up
          ipv4:
            dhcp: false
            enabled: true
          link-aggregation:
            mode: 802.3ad
            options:
              miimon: '140'
            port:
              - enp1s0
              - enp2s0

        # VLAN on bond
        - name: bond0.1924
          type: vlan
          state: up
          vlan:
            base-iface: bond0
            id: 1924
          ipv4:
            address:
              - ip: 192.168.50.21
                prefix-length: 24
            dhcp: false
            enabled: true

      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: 192.168.50.1  # VyOS gateway
            next-hop-interface: bond0.1924
            table-id: 254

      dns-resolver:
        config:
          server:
            - 192.168.122.1  # Libvirt dnsmasq
```

### Complete Example: HA Cluster (3 Control Planes + 3 Workers)

```yaml
control_plane_replicas: 3
app_node_replicas: 3

nodes:
  # Control Plane Nodes
  - hostname: master-0
    role: master
    rootDeviceHints:
      deviceName: /dev/sda
    interfaces:
      - name: enp1s0
        mac_address: "52:54:00:00:00:01"
      - name: enp2s0
        mac_address: "52:54:00:00:00:02"
    networkConfig:
      interfaces:
        - name: bond0
          type: bond
          state: up
          link-aggregation:
            mode: 802.3ad
            port:
              - enp1s0
              - enp2s0
        - name: bond0.1924
          type: vlan
          state: up
          vlan:
            base-iface: bond0
            id: 1924
          ipv4:
            address:
              - ip: 192.168.50.21
                prefix-length: 24
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: 192.168.50.1
            next-hop-interface: bond0.1924
      dns-resolver:
        config:
          server:
            - 192.168.122.1

  - hostname: master-1
    role: master
    rootDeviceHints:
      deviceName: /dev/sda
    interfaces:
      - name: enp1s0
        mac_address: "52:54:00:00:01:01"
      - name: enp2s0
        mac_address: "52:54:00:00:01:02"
    networkConfig:
      interfaces:
        - name: bond0
          type: bond
          state: up
          link-aggregation:
            mode: 802.3ad
            port:
              - enp1s0
              - enp2s0
        - name: bond0.1924
          type: vlan
          state: up
          vlan:
            base-iface: bond0
            id: 1924
          ipv4:
            address:
              - ip: 192.168.50.22
                prefix-length: 24
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: 192.168.50.1
            next-hop-interface: bond0.1924

  - hostname: master-2
    role: master
    rootDeviceHints:
      deviceName: /dev/sda
    interfaces:
      - name: enp1s0
        mac_address: "52:54:00:00:02:01"
      - name: enp2s0
        mac_address: "52:54:00:00:02:02"
    networkConfig:
      interfaces:
        - name: bond0
          type: bond
          state: up
          link-aggregation:
            mode: 802.3ad
            port:
              - enp1s0
              - enp2s0
        - name: bond0.1924
          type: vlan
          state: up
          vlan:
            base-iface: bond0
            id: 1924
          ipv4:
            address:
              - ip: 192.168.50.23
                prefix-length: 24
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: 192.168.50.1
            next-hop-interface: bond0.1924

  # Worker Nodes
  - hostname: worker-0
    role: worker
    rootDeviceHints:
      deviceName: /dev/sda
    interfaces:
      - name: enp1s0
        mac_address: "52:54:00:01:00:01"
      - name: enp2s0
        mac_address: "52:54:00:01:00:02"
    networkConfig:
      interfaces:
        - name: bond0
          type: bond
          state: up
          link-aggregation:
            mode: 802.3ad
            port:
              - enp1s0
              - enp2s0
        - name: bond0.1924
          type: vlan
          state: up
          vlan:
            base-iface: bond0
            id: 1924
          ipv4:
            address:
              - ip: 192.168.50.31
                prefix-length: 24
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: 192.168.50.1
            next-hop-interface: bond0.1924

  # worker-1 and worker-2 follow same pattern with different IPs/MACs...
```

---

## Example Configurations

We provide several example configurations in the `examples/` directory:

### Standard Configurations
- `baremetal-example/`: Standard bare metal deployment
- `vmware-example/`: VMware vSphere deployment
- `vmware-disconnected-example/`: Disconnected VMware installation

### Network Configurations
- `bond0-single-bond0-vlan/`: Basic bonded interface with VLAN
- `cnv-bond0-tagged/`: OpenShift Virtualization with tagged bonds
- `converged-bond0-signal-vlan/`: Converged networking setup

### Special Deployments
- `sno-bond0-signal-vlan/`: Single Node OpenShift with bonding
- `stretched-metro-cluster/`: Multi-site stretched cluster
- `serenity-sno.v60.lab.kemo.network/`: Lab environment example

## Advanced Network Configuration

### Bond Configuration
```yaml
networkConfig:
  interfaces:
    - name: bond0
      type: bond
      state: up
      ipv4:
        enabled: true
        address:
          - ip: 192.168.180.21
            prefix-length: 23
      link-aggregation:
        mode: active-backup
        ports:
          - enp1s0
          - enp2s0
```

### VLAN Configuration
```yaml
networkConfig:
  interfaces:
    - name: bond0.100
      type: vlan
      state: up
      vlan:
        base-iface: bond0
        id: 100
      ipv4:
        enabled: true
        address:
          - ip: 192.168.100.10
            prefix-length: 24
```

## Optional Features

### Proxy Configuration
```yaml
proxy:
  http_proxy: http://192.168.42.31:3128
  https_proxy: http://192.168.42.31:3128
  no_proxy:
    - .svc.cluster.local
    - 192.168.0.0/16
    - .example.network
    - .example.labs
```

### Architecture Selection
```yaml
cluster_architecture: x86_64  # Options: x86_64 | s390x | ppc64le | aarch64 | multi
```

### ZTP Manifests
```yaml
create_ztp_manifests: false
```

## Example Deployment Types

### Single Node OpenShift (SNO)
See `examples/sno-bond0-signal-vlan/` for a complete example.

### Three-node Compact Cluster
See `examples/baremetal-example/` and modify the node counts.

### Standard HA Cluster
See `examples/baremetal-example/` for a complete HA deployment.

## Platform-Specific Parameters

### VSphere Platform

```yaml
platform_type: vsphere
vsphere:
  vcenter: vcenter.example.com
  username: administrator@vsphere.local
  password: secretpassword
  datacenter: DC1
  default_datastore: datastore1
  cluster: Cluster1
  network: VM Network
  api_vips:
    - 192.168.100.50
  app_vips:
    - 192.168.100.51
```

### Nutanix Platform (OpenShift 4.21+)

```yaml
platform_type: nutanix
nutanix:
  prism_central_address: prism-central.example.com
  prism_central_username: admin
  prism_central_password: secretpassword
  prism_element_uuid: "<element-uuid>"
  subnet_uuids:
    - "<subnet-uuid>"
  api_vips:
    - 192.168.100.50
  app_vips:
    - 192.168.100.51
```

### Bare Metal Platform

```yaml
platform_type: baremetal
control_plane_replicas: 3
app_node_replicas: 2

api_vips:
  - 192.168.50.252  # Separate VIP (not a node IP)
app_vips:
  - 192.168.50.253  # Separate VIP (not a node IP)
```

### Platform None (SNO/Edge)

```yaml
platform_type: none
control_plane_replicas: 1
app_node_replicas: 0

api_vips:
  - 192.168.50.21  # MUST match SNO node IP
app_vips:
  - 192.168.50.21  # MUST match SNO node IP
```

---

## Configuration Validation

### Pre-Deployment Checks

Before generating ISOs, validate your configuration:

```bash
# Validate cluster.yml syntax
yamllint examples/sno-4.20-standard/cluster.yml

# Validate NMState network config
nmstatectl gc examples/sno-4.20-standard/nodes.yml

# Check for common issues
./hack/validate-kvm-examples.sh
```

### Common Configuration Errors

**Error**: "VIPs must be in machine_network_cidrs"
```yaml
# Wrong:
machine_network_cidrs:
  - 192.168.50.0/24
api_vips:
  - 192.168.100.50  # ❌ Different network

# Correct:
machine_network_cidrs:
  - 192.168.50.0/24
api_vips:
  - 192.168.50.21  # ✅ Same network
```

**Error**: "OpenShiftSDN not supported in 4.21+"
```yaml
# Wrong (4.21+):
network_type: OpenShiftSDN  # ❌ Removed in 4.21

# Correct:
network_type: OVNKubernetes  # ✅ Required for 4.21+
```

**Error**: "SNO must use platform_type: none"
```yaml
# Wrong (SNO):
platform_type: baremetal  # ❌ Invalid for SNO
control_plane_replicas: 1

# Correct:
platform_type: none  # ✅ Required for SNO
control_plane_replicas: 1
```

---

## Configuration Best Practices

### Network Configuration

1. **Use bond0 + VLAN for production**
   - Provides NIC redundancy
   - LACP (802.3ad) for load balancing
   - Fallback: active-backup if LACP unavailable

2. **DNS Configuration (KVM Deployments)**
   - Use libvirt dnsmasq: `192.168.122.1`
   - Standard VLAN: 1924 (192.168.50.0/24)
   - Gateway: 192.168.50.1 (VyOS router)

3. **VIP Selection**
   - SNO: VIPs = node IP
   - HA: VIPs ≠ any node IP (separate IPs)
   - Keep API and App VIPs in same subnet for simplicity

### Version Management

1. **Always specify ocp_version**
   ```yaml
   ocp_version: "4.20"  # Ensures correct CLI tools downloaded
   ```

2. **Check version compatibility**
   - 4.19: Legacy support
   - 4.20: Current stable, ImageDigestMirrorSet migration
   - 4.21: Latest, OVNKubernetes required, Nutanix support

### Storage Configuration

1. **Root Device Selection**
   - Prefer `deviceName` for simplicity
   - Use `wwn` for multipath SAN storage
   - Use `minSizeGigabytes` + `rotational: false` for SSD filtering

2. **ODF/CNV Deployments**
   - Add ODF storage disks via `rootDeviceHints`
   - Use separate disks for workloads vs system

---

## Configuration Templates by Use Case

### Edge Computing / Remote Sites
- **Profile**: SNO, minimal resources, remote management
- **Template**: `examples/sno-bond0-signal-vlan/`
- **Key Settings**: `platform_type: none`, `control_plane_replicas: 1`

### Data Center HA
- **Profile**: 3-node or 5-node cluster, high availability
- **Template**: `examples/cnv-bond0-tagged/`
- **Key Settings**: `platform_type: baremetal`, `control_plane_replicas: 3`, `app_node_replicas: 3+`

### VMware Enterprise
- **Profile**: VSphere platform, enterprise integration
- **Template**: `examples/vmware-example/`
- **Key Settings**: `platform_type: vsphere`, vsphere credentials

### Air-Gapped Deployments
- **Profile**: Disconnected, mirror registry
- **Template**: `examples/ha-4.21-disconnected/`
- **Key Settings**: `disconnected_registries`, `additional_trust_bundle_path`

### Kubernetes at the Edge
- **Profile**: 3-node compact cluster, edge locations
- **Template**: `examples/baremetal-example/` (modified: `app_node_replicas: 0`)
- **Key Settings**: `control_plane_replicas: 3`, `app_node_replicas: 0`

---

## Additional Resources

### Reference Examples
- **SNO**: `examples/sno-bond0-signal-vlan/` (KVM), `examples/sno-4.20-standard/` (basic)
- **HA**: `examples/cnv-bond0-tagged/` (6-node), `examples/ha-4.21-disconnected/` (air-gap)
- **VMware**: `examples/vmware-example/`, `examples/vmware-disconnected-example/`
- **Networking**: `examples/bond0-single-bond0-vlan/`, `examples/converged-bond0-signal-vlan/`
- **Nutanix**: `examples/nutanix-sno/`, `examples/nutanix-ha/`

### Tools & Scripts
- **ISO Generation**: `/hack/create-iso.sh` - See [Script Reference](/hack/REFERENCE.md)
- **Validation**: `/hack/validate-kvm-examples.sh` - Check DNS/VLAN/network compliance
- **Deployment Standards**: `/hack/validate-deployment-standards.sh` - Version-specific validation

### Documentation Links
- [Installation Guide](installation-guide) - Step-by-step deployment walkthrough
- [Network Configuration](network-configuration) - Advanced networking patterns
- [Networking Architecture](networking-architecture) - KVM/VyOS topology deep dive
- [Deployment Patterns](deployment-patterns) - SNO vs 3-node vs HA architectures
- [Version Compatibility Matrix](version-compatibility-matrix) - Supported versions and features
- [Deployment Standards: 4.19](deployment-standards-4.19) - Version-specific requirements
- [Deployment Standards: 4.20](deployment-standards-4.20) - Version-specific requirements
- [Deployment Standards: 4.21](deployment-standards-4.21) - Version-specific requirements
- [Disconnected Installation](disconnected-installation) - Air-gap deployment guide
- [BMC Management](bmc-management) - Redfish/IPMI configuration

### Additional Files
- **llm.txt** - Comprehensive AI-friendly reference (3,481 lines)
- **disconnected-info.md** - Disconnected deployment details
- **DNS_AUTOMATION.md** - DNS automation implementation
- **ADRs** - [Architectural Decision Records](/docs/adr/)

---

**Last Updated**: 2026-05-29  
**Maintained By**: OpenShift Agent-Install Contributors 