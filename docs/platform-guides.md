---
layout: default
title: Platform Guides
description: Platform-specific guides for OpenShift Agent-based installations using the helper utilities
parent: How-to Guides
nav_order: 3
---

# Platform Guides

This guide provides platform-specific instructions for OpenShift Agent-based installations using the helper utilities in this repository. For official OpenShift Agent-based installation documentation, see [Red Hat's official documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/4.12/html-single/installing_an_on-premise_cluster_with_the_agent-based_installer/index).

## Overview

The OpenShift Agent-based installer helper supports multiple deployment scenarios:
- Single Node OpenShift (SNO)
- 3-Node Clusters
- Standard HA Clusters
- Stretched Metro Clusters

Across various platforms:
- Bare Metal
- VMware vSphere
- Platform None (Generic x86)
- Nutanix AHV

For detailed topology recommendations, see [Agent-based Installer workflow and recommended resources](https://docs.openshift.com/container-platform/4.14/installing/installing_with_agent_based_installer/preparing-to-install-with-agent-based-installer.html#understanding-agent-based-installer_preparing-to-install-with-agent-based-installer).

### Supported Architectures

The Agent-based Installer supports the following architectures:

| CPU architecture | Connected installation | Disconnected installation | Comments |
|-----------------|------------------------|-------------------------|-----------|
| 64-bit x86      | ✓                     | ✓                      |           |
| 64-bit ARM      | ✓                     | ✓                      |           |
| ppc64le         | ✓                     | ✓                      |           |
| s390x           | ✓                     | ✓                      | ISO boot not supported. Use PXE assets |

For more details, see [Agent-based Installer supported architectures](https://docs.openshift.com/container-platform/4.15/installing/installing_with_agent_based_installer/preparing-to-install-with-agent-based-installer.html#about-agent-based-installer_preparing-to-install-with-agent-based-installer).

### Resource Requirements

| Topology | Master Nodes | Worker Nodes | vCPU | Memory | Storage |
|----------|--------------|--------------|------|--------|---------|
| Single-node | 1 | 0 | 8 vCPUs | 16GB | 120GB |
| Compact | 3 | 0 or 1 | 8 vCPUs | 16GB | 120GB |
| HA | 3 | 2+ | 8 vCPUs | 16GB | 120GB |

For detailed requirements, see [Recommended cluster resources](https://docs.openshift.com/container-platform/4.14/installing/installing_with_agent_based_installer/preparing-to-install-with-agent-based-installer.html#recommended-resources-for-topologies_understanding-agent-based-installer).

## Prerequisites

Before starting any installation, ensure you have:

```yaml
Base Requirements:
  - RHEL system to work from
  - OpenShift CLI Tools (download using ./download-openshift-cli.sh)
  - NMState CLI (dnf install nmstate)
  - Ansible Core (dnf install ansible-core)
  - Required Ansible Collections (ansible-galaxy install -r playbooks/collections/requirements.yml)
  - Red Hat OpenShift Pull Secret (https://console.redhat.com/openshift/downloads#tool-pull-secret)
  - SSH Key for cluster access
```

Additional requirements:
- [Network requirements](https://docs.openshift.com/container-platform/4.14/installing/installing_with_agent_based_installer/preparing-to-install-with-agent-based-installer.html#about-networking_preparing-to-install-with-agent-based-installer)
- [Firewall requirements](https://docs.openshift.com/container-platform/4.14/installing/installing_platform_agnostic/installing-platform-agnostic.html#configuring-firewall)
- [DNS requirements](https://docs.openshift.com/container-platform/4.14/installing/installing_bare_metal/installing-bare-metal.html#installation-dns-user-infra_installing-bare-metal)

For detailed prerequisites, see our [disconnected-info.md](../disconnected-info) guide.

## Quick Start

The fastest way to get started is using our example configurations:

```bash
# Clone the repository
git clone https://github.com/tosin2013/openshift-agent-install.git
cd openshift-agent-install

# Download OpenShift CLI tools
./download-openshift-cli.sh
sudo cp ./bin/* /usr/local/bin/

# Create ISO using an example configuration
./hack/create-iso.sh examples/sno-bond0-signal-vlan
```

For more examples, check our [examples/](../examples/) directory.

## Platform-Specific Configurations

### Bare Metal

Example configuration for a bare metal deployment (`examples/baremetal-example/`):

```yaml
# cluster.yml
pull_secret_path: ~/ocp-install-pull-secret.json
base_domain: example.com
cluster_name: baremetal-cluster
platform_type: baremetal

api_vips:
  - 192.168.1.100
app_vips:
  - 192.168.1.101

# Network configuration
cluster_network_cidr: 10.128.0.0/14
cluster_network_host_prefix: 23
service_network_cidrs:
  - 172.30.0.0/16
machine_network_cidrs:
  - 192.168.1.0/24
network_type: OVNKubernetes

# Optional but recommended
ntp_servers:
  - time.example.com
dns_servers:
  - 192.168.1.53
dns_search_domains:
  - example.com
```

For more bare metal configuration options, see:
- [Sample install-config.yaml file for bare metal](https://docs.openshift.com/container-platform/4.14/installing/installing_with_agent_based_installer/preparing-to-install-with-agent-based-installer.html#sample-install-config-yaml-file-for-bare-metal_preparing-to-install-with-agent-based-installer)
- [Bare metal installation customization](https://docs.openshift.com/container-platform/4.14/installing/installing_bare_metal/installing-bare-metal.html#installation-bare-metal-config-yaml_installing-bare-metal)

### VMware vSphere

Example configuration for vSphere (`examples/vmware-example/`):

```yaml
# cluster.yml
platform_type: vsphere
vsphere:
  vcenter: vcenter.example.com
  username: administrator@vsphere.local
  password: your-vcenter-password
  datacenter: Datacenter1
  datastore: Datastore1
  network: "VM Network"
  folder: /Datacenter1/vm/folder1

# Additional vSphere-specific settings
control_plane_replicas: 3
app_node_replicas: 2
```

For more vSphere information:
- [Installing a cluster on vSphere](https://docs.openshift.com/container-platform/4.14/installing/installing_vsphere/installing-vsphere.html)
- [vSphere prerequisites](https://docs.openshift.com/container-platform/4.14/installing/installing_vsphere/installing-vsphere-installer-provisioned.html#installation-vsphere-prerequisites_installing-vsphere-installer-provisioned)
- Disconnected example: `examples/vmware-disconnected-example/`

### Platform None (Generic x86)

Example configuration for platform none/generic x86 (`examples/sno-bond0-signal-vlan/`):

```yaml
# cluster.yml
platform_type: none
control_plane_replicas: 1  # For SNO
app_node_replicas: 0

# nodes.yml
nodes:
  - hostname: sno
    rootDeviceHints:
      deviceName: /dev/nvme0n1
    interfaces:
      - name: bond0
        mac_address: "52:54:00:00:00:01"
    networkConfig:
      interfaces:
        - name: bond0
          type: bond
          state: up
          ipv4:
            enabled: true
            address:
              - ip: 192.168.1.10
                prefix-length: 24
```

Note: Platform `none` is only supported for single-node OpenShift clusters with OVNKubernetes network type. See [Platform support limitations](https://docs.openshift.com/container-platform/4.14/installing/installing_with_agent_based_installer/preparing-to-install-with-agent-based-installer.html#understanding-agent-based-installer_preparing-to-install-with-agent-based-installer).

### Nutanix AHV

The repository includes two Nutanix reference examples:

- `examples/nutanix-sno/` — Single Node OpenShift on Nutanix AHV
- `examples/nutanix-ha/` — HA cluster (3 masters, 2 workers) on Nutanix AHV

> **Important**: The Agent-Based Installer does **not** create VMs automatically on Nutanix.
> You must upload the generated ISO to the Nutanix Image Service and create VMs manually
> in Prism Central, then boot each VM from the ISO.

#### Prerequisites

Before configuring, collect the following from your Nutanix environment:

| Value | Where to find it |
|-------|-----------------|
| Prism Central hostname/IP | Prism Central login URL |
| Prism Element UUID | Prism Central → Infrastructure → Clusters → select cluster → UUID |
| Subnet UUID | Prism Central → Network & Security → Subnets → select subnet → UUID |

Verify Prism Central connectivity from the deployment host:

```bash
curl -k -X POST \
  https://prism-central.example.com:9440/api/nutanix/v3/clusters/list \
  -H "Content-Type: application/json" \
  -u admin:changeme \
  -d '{}'
```

#### cluster.yml — SNO example (`examples/nutanix-sno/`)

```yaml
platform_type: nutanix
cluster_name: nutanix-sno
base_domain: example.com
ocp_version: "4.21"          # 4.21+ recommended for Nutanix

# Prism Central connection
nutanix_prism_central_host: prism-central.example.com
nutanix_prism_central_port: 9440
nutanix_prism_central_username: admin
nutanix_prism_central_password: "changeme"

# Prism Element
nutanix_prism_element_host: prism-element.example.com
nutanix_prism_element_port: 9440
nutanix_prism_element_uuid: "00000000-0000-0000-0000-000000000000"

# Subnet UUID
nutanix_subnet_uuids:
  - "subnet-uuid-1234-5678-90ab-cdef"

# SNO: api_vips and app_vips must equal the node IP
api_vips:
  - 192.168.1.100
app_vips:
  - 192.168.1.100

control_plane_replicas: 1
app_node_replicas: 0
rendezvous_ip: 192.168.1.100
network_type: OVNKubernetes
machine_network_cidrs:
  - 192.168.1.0/24
```

For HA (`examples/nutanix-ha/`), use separate VIPs and increase replicas:

```yaml
# HA: api_vips and app_vips are separate unused IPs
api_vips:
  - 192.168.1.100
app_vips:
  - 192.168.1.101

control_plane_replicas: 3
app_node_replicas: 2
rendezvous_ip: 192.168.1.110   # IP of the first control plane node
```

#### nodes.yml — Nutanix-specific notes

Nutanix AHV assigns MAC addresses when VMs are created. The MAC address in `nodes.yml` is a placeholder; the actual MAC is set at VM creation time in Prism Central. The typical interface name is `enp1s0` and the root disk is `/dev/sda`:

```yaml
nodes:
  - hostname: nutanix-sno-master-0
    role: master
    rootDeviceHints:
      deviceName: /dev/sda        # Nutanix virtual disk
    interfaces:
      - name: enp1s0              # Common AHV interface name; may vary
        mac-address: "52:54:00:00:00:01"   # Placeholder — Nutanix assigns actual MAC
    networkConfig:
      interfaces:
        - name: enp1s0
          type: ethernet
          state: up
          ipv4:
            enabled: true
            address:
              - ip: 192.168.1.100
                prefix-length: 24
            dhcp: false
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: 192.168.1.1
            next-hop-interface: enp1s0
            table-id: 254
```

#### Generate ISO and deploy

```bash
# Generate the agent ISO
./hack/create-iso.sh nutanix-sno

# Verify the generated Nutanix platform section in the manifest
grep -A 20 "^platform:" ~/generated_assets/nutanix-sno/install-config.yaml
```

Then in Prism Central:
1. **Upload ISO**: Prism Central → Infrastructure → Images → Add Image → upload `agent.x86_64.iso`
2. **Create VM**: set vCPU ≥ 8, RAM ≥ 32 GB, disk ≥ 120 GB, attach to the configured subnet, mount the ISO
3. **Power on** each VM
4. **Monitor** installation:

```bash
./bin/openshift-install agent wait-for install-complete \
  --dir ~/generated_assets/nutanix-sno/ --log-level=info
```

For more information:
- [Installing OpenShift on Nutanix](https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/installing_on_nutanix/)
- [Agent-Based Installer on Nutanix](https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/installing_an_on-premise_cluster_with_the_agent-based_installer/)

## Advanced Configurations

### Network Bonding

The repository includes several examples of network bonding configurations:
- `examples/bond0-single-bond0-vlan/` - Single bond with VLAN
- `examples/sno-bond0-signal-vlan/` - SNO with bonded network
- `examples/cnv-bond0-tagged/` - CNV with tagged bond

For more network configuration:
- [Example: Bonds and VLAN interface node network configuration](https://docs.openshift.com/container-platform/4.14/installing/installing_with_agent_based_installer/preparing-to-install-with-agent-based-installer.html#example-bonds-and-vlan-interface-node-network-configuration_preparing-to-install-with-agent-based-installer)
- [Networking requirements](https://docs.openshift.com/container-platform/4.14/installing/installing_platform_agnostic/installing-platform-agnostic.html#installation-network-user-infra_installing-platform-agnostic)

### Disconnected Installations

For disconnected environments, see:
- Local guide: [disconnected-info.md](../disconnected-info)
- Example: `examples/vmware-disconnected-example/`
- [Official disconnected installation guide](https://docs.openshift.com/container-platform/4.14/installing/disconnected_install/installing-disconnected.html)
- [Mirroring images for disconnected installation](https://docs.openshift.com/container-platform/4.14/installing/installing_with_agent_based_installer/installing-with-agent-based-installer.html#mirroring-images-disconnected-installation_installing-with-agent-based-installer)

Example mirror configuration:
```yaml
disconnected_registries:
  - target: disconn-registry.example.com/openshift-release-dev/ocp-release
    source: quay.io/openshift-release-dev/ocp-release
  - target: disconn-registry.example.com/openshift-release-dev/ocp-v4.0-art-dev
    source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
```

### Stretched Metro Clusters

For geographically distributed clusters, see:
- Local example: `examples/stretched-metro-cluster/`
- [About stretched clusters](https://docs.openshift.com/container-platform/4.14/installing/installing_with_agent_based_installer/preparing-to-install-with-agent-based-installer.html#about-stretched-clusters_preparing-to-install-with-agent-based-installer)
- [Stretched cluster network requirements](https://docs.openshift.com/container-platform/4.14/installing/installing_with_agent_based_installer/preparing-to-install-with-agent-based-installer.html#network-requirements-stretched-cluster_preparing-to-install-with-agent-based-installer)

## Helper Scripts

The repository includes several helper scripts:

```bash
# Download OpenShift CLI tools
./download-openshift-cli.sh

# Download RHCOS ISO
./get-rhcos-iso.sh

# Create installation ISO
./hack/create-iso.sh <example-directory>
```

## Troubleshooting

### Common Issues

1. BMC/IPMI Access
```bash
# Verify BMC access
ipmitool -I lanplus -H <bmc-address> -U <username> -P <password> power status
```

2. Network Configuration
```bash
# Verify network settings
nmcli device show
```

3. DNS Resolution
```bash
# Test DNS resolution
dig +short api.<cluster_name>.<base_domain>
dig +short *.apps.<cluster_name>.<base_domain>
```

For troubleshooting help:
- [Gathering log data from a failed Agent-based installation](https://docs.openshift.com/container-platform/4.14/installing/installing_with_agent_based_installer/installing-with-agent-based-installer.html#gathering-logs-failed-installation_installing-with-agent-based-installer)
- [Troubleshooting installation issues](https://docs.openshift.com/container-platform/4.14/support/troubleshooting/troubleshooting-installations.html)
- [Verifying node health](https://docs.openshift.com/container-platform/4.14/support/troubleshooting/verifying-node-health.html)

## Related Documentation

- [Installation Guide](installation-guide)
- [Network Configuration](network-configuration)
- [Official OpenShift Agent-based Installation Guide](https://docs.redhat.com/en/documentation/openshift_container_platform/4.12/html-single/installing_an_on-premise_cluster_with_the_agent-based_installer/index)
- [OpenShift Container Platform Documentation](https://docs.openshift.com/container-platform/4.14/welcome/index.html)
- [Red Hat Hybrid Cloud Console](https://console.redhat.com/openshift)
- [OpenShift Blog](https://www.redhat.com/en/blog/products/openshift) 