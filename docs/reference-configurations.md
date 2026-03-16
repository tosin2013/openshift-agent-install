---
layout: default
title: Reference Configurations
description: Reference configurations for the OpenShift Agent-based Installation Helper
---

# Reference Configurations

This guide provides reference configurations for using the OpenShift Agent-based Installation Helper tools.

## Overview

This helper repository provides pre-defined configurations and automation for common OpenShift deployment patterns:
- Single-Node OpenShift (SNO)
- Three-Node Compact Cluster
- Standard HA Cluster
- Platform-specific configurations (Bare Metal, vSphere, platform=none)

## Using the Configuration Templates

### 1. Basic Usage

```bash
# Copy an example configuration
cp examples/sno/cluster.yml my-cluster/
cp examples/sno/nodes.yml my-cluster/

# Generate the installation media
./hack/create-iso.sh my-cluster
```

## Single-Node OpenShift (SNO)

### Basic SNO Configuration

```yaml
# cluster.yml
cluster_name: my-sno
base_domain: example.com
platform_type: none
control_plane_replicas: 1
app_node_replicas: 0

network_config:
  api_vips:
    - 192.168.70.46
  app_vips:
    - 192.168.70.46
  machine_network_cidrs:
    - 192.168.70.0/23

# nodes.yml
nodes:
  - hostname: sno-node
    role: master
    rootDeviceHints:
      deviceName: /dev/sda
    interfaces:
      - name: ens3
        mac_address: "52:54:00:00:00:01"
    networkConfig:
      interfaces:
        - name: ens3
          type: ethernet
          state: up
          ipv4:
            enabled: true
            address:
              - ip: 192.168.70.46
                prefix-length: 23
```

## Three-Node Compact Cluster

### Basic Compact Configuration

```yaml
# cluster.yml
cluster_name: compact-cluster
base_domain: example.com
platform_type: baremetal
control_plane_replicas: 3
app_node_replicas: 0

# nodes.yml
nodes:
  - hostname: master-0
    role: master
    rootDeviceHints:
      deviceName: /dev/sda
    networkConfig:
      interfaces:
        - name: ens3
          type: ethernet
          state: up
          ipv4:
            enabled: true
            address:
              - ip: 192.168.70.10
                prefix-length: 23
  # ... master-1 and master-2 configurations
```

## Platform-Specific Examples

### Bare Metal Configuration

```yaml
# cluster.yml
platform_type: baremetal
bmc_config:
  username: ADMIN
  password: ADMIN
  disable_certificate_verification: true

# nodes.yml
nodes:
  - hostname: master-0
    role: master
    bmc:
      address: redfish://192.168.1.100/redfish/v1/Systems/1
      username: ADMIN
      password: ADMIN
    rootDeviceHints:
      deviceName: /dev/sda
```

### VMware Configuration

```yaml
# cluster.yml
platform_type: vsphere
vsphere_config:
  vcenter: vcenter.example.com
  username: administrator@vsphere.local
  password: password
  datacenter: datacenter1
  cluster: cluster1
  network: VM Network
  datastore: datastore1
```

## Helper Scripts

The repository provides several helper scripts for common tasks:

```bash
# Generate installation media
./hack/create-iso.sh <cluster-dir>

# Validate configuration
./hack/validate-config.sh <cluster-dir>

# Deploy using Ansible
cd playbooks/
ansible-playbook -e "@../my-cluster/cluster.yml" deploy.yml
```

## Related Documentation

- [Installation Guide](./installation-guide.md)
- [Network Configuration](./network-configuration.md)
- [Platform Guides](./platform-guides.md)
- [Deployment Patterns](./deployment-patterns.md)

## External Resources

- [OpenShift Agent-Based Installation Overview](https://docs.openshift.com/container-platform/latest/installing/installing_with_agent_based_installer/preparing-to-install-with-agent-based-installer.html)
- [Platform-Specific Installation Guides](https://docs.openshift.com/container-platform/latest/installing/index.html)
- [Post-Installation Configuration](https://docs.openshift.com/container-platform/latest/post_installation_configuration/cluster-tasks.html) 