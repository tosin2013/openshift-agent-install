---
layout: default
title: Installation Guide
description: A comprehensive guide for installing OpenShift using the Agent-based Installer
---

# Installation Guide

A comprehensive guide for installing OpenShift using the Agent-based Installer, covering all major deployment scenarios and configurations.

> **Important**: OpenShift documentation will be moving to docs.redhat.com on March 12, 2025. Links will be updated accordingly. For the current status of all external links used in this documentation, please refer to [External Links](external-links.md).

> **Related ADR**: [ADR-0001: Agent-based Installation Approach](adr/0001-agent-based-installation-approach.md)

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Installation Methods](#installation-methods)
  - [Declarative Method](#declarative-method)
  - [Manual Method](#manual-method)
- [Post-installation](#post-installation)
- [Troubleshooting](#troubleshooting)

## Overview

The OpenShift Agent-based Installer Helper provides utilities to easily leverage the OpenShift Agent-Based Installer. It supports bare metal, vSphere, and platform=none deployments in SNO/3 Node/HA configurations.

> **Related ADR**: [ADR-0012: Deployment Patterns and Configurations](adr/0012-deployment-patterns-and-configurations.md)

## Prerequisites

### System Requirements

1. **Base System**:
   - RHEL system for installation host
   - Network access to target nodes

2. **Software Requirements**:
```bash
# Install required packages
sudo dnf install -y \
    nmstate \
    ansible-core \
    bind-utils \
    libguestfs-tools \
    podman
```

```bash
# Install OpenShift CLI Tools
./download-openshift-cli.sh
sudo cp ./bin/* /usr/local/bin/
```

```bash
# Install Ansible Collections
ansible-galaxy collection install -r playbooks/collections/requirements.yml
```

3. **Required Files**:
   - [Red Hat OpenShift Pull Secret](https://console.redhat.com/openshift/downloads#tool-pull-secret)
   - Any additional pull secrets for disconnected registries (if needed)

## Installation Methods

### Declarative Method

1. **Prepare Configuration**:
   - Create a directory in `examples/` with your cluster configuration
   - Add `cluster.yml` and `nodes.yml` files based on examples

2. **Generate Installation Media**:
```bash
./hack/create-iso.sh $FOLDER_NAME
```

This will:
- Generate templates with Ansible
- Create the ISO
- Provide next-step instructions

### Manual Method

**Generate Manifests**:

```bash
# Navigate to playbooks directory
cd playbooks/
```

```bash
# Create manifests using your configuration
ansible-playbook -e "@your-cluster-vars.yml" create-manifests.yml
```

**Create Installation ISO**:

```bash
# Generate ISO
openshift-install agent create image --dir ./generated_manifests/<cluster_name>

# Monitor bootstrap process
openshift-install agent wait-for bootstrap-complete --dir ./generated_manifests/<cluster_name>

# Monitor installation
openshift-install agent wait-for install-complete --dir ./generated_manifests/<cluster_name>
```

### Configuration Examples

#### Basic Cluster Configuration (cluster.yml)
```yaml
pull_secret_path: ~/ocp-install-pull-secret.json

# Cluster metadata
base_domain: example.com
cluster_name: test-cluster

# Platform configuration
platform_type: baremetal  # Options: baremetal, vsphere, none

# Network configuration
api_vips:
  - 192.168.1.5
app_vips:
  - 192.168.1.6

# Network settings
cluster_network_cidr: 10.128.0.0/14
cluster_network_host_prefix: 23
service_network_cidrs:
  - 172.30.0.0/16
machine_network_cidrs:
  - 192.168.1.0/24
network_type: OVNKubernetes
```

#### Node Configuration (nodes.yml)
```yaml
# Node counts
control_plane_replicas: 3
app_node_replicas: 2

# Node definitions
nodes:
  - hostname: master-0
    role: master
    rootDeviceHints:
      deviceName: /dev/sda
    interfaces:
      - name: enp1s0
        mac_address: "52:54:00:00:00:01"
    networkConfig:
      interfaces:
        - name: enp1s0
          type: ethernet
          state: up
          ipv4:
            enabled: true
            address:
              - ip: 192.168.1.10
                prefix-length: 24
```

## Post-installation

1. **Verify Installation**:
```bash
# Check cluster status
oc get clusterversion
oc get nodes
oc get co
```

2. **Configure Additional Features**:
   - Identity Management
   - Storage
   - Networking
   - Monitoring

## Troubleshooting

### Common Issues

1. **Installation Failures**:
   - Check installation logs
   - Verify network connectivity
   - Review node configurations

2. **Network Issues**:
   - Verify VIP accessibility
   - Check DNS resolution
   - Validate network configurations

### Diagnostic Commands

```bash
# Review bootstrap progress
openshift-install agent wait-for bootstrap-complete --dir ./generated_manifests/<cluster_name> --debug

# Check node status
oc get nodes -o wide

# View cluster operators
oc get co

# Check pod status
oc get pods --all-namespaces
```

## Related Documentation

### Internal References
- [Network Configuration](network-configuration.md)
- [BMC Management](bmc-management.md)
- [Deployment Patterns](deployment-patterns.md)
- [Disconnected Installation](disconnected-installation.md)

### ADR References
- [ADR-0001: Agent-based Installation Approach](adr/0001-agent-based-installation-approach.md)
- [ADR-0002: Advanced Networking Configurations](adr/0002-advanced-networking-configurations.md)
- [ADR-0003: Ansible Automation Approach](adr/0003-ansible-automation-approach.md)
- [ADR-0004: Disconnected Installation Support](adr/0004-disconnected-installation-support.md)
- [ADR-0005: ISO Creation and Asset Management](adr/0005-iso-creation-and-asset-management.md)

### OpenShift Documentation
- [OpenShift Agent-Based Installation Overview](https://docs.openshift.com/container-platform/latest/installing/installing_with_agent_based_installer/preparing-to-install-with-agent-based-installer.html)
- [Installation Requirements](https://docs.openshift.com/container-platform/latest/installing/installing_bare_metal/installing-bare-metal.html#installation-requirements-user-infra_installing-bare-metal)
- [Agent-Based Installer Configuration](https://docs.openshift.com/container-platform/latest/installing/installing_with_agent_based_installer/installing-with-agent-based-installer.html)
- [Post-Installation Configuration](https://docs.openshift.com/container-platform/latest/post_installation_configuration/cluster-tasks.html)

### Platform-Specific Guides
- [Bare Metal Installation](https://docs.openshift.com/container-platform/latest/installing/installing_bare_metal/installing-bare-metal.html)
- [VMware vSphere Installation](https://docs.openshift.com/container-platform/latest/installing/installing_vsphere/preparing-to-install-on-vsphere.html)
- [Platform-Agnostic Installation](https://docs.openshift.com/container-platform/latest/installing/installing_platform_agnostic/installing-platform-agnostic.html)

### Red Hat Documentation
- [RHEL Network Configuration](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/configuring_and_managing_networking/index)
- [Ansible Documentation](https://docs.ansible.com/ansible/latest/index.html)
- [Podman Container Management](https://docs.podman.io/en/latest/)
- [RHEL System Administration](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/system_design_guide/index)

### Tools and Utilities
- [OpenShift CLI Documentation](https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html)
- [NMState Network Configuration](https://nmstate.io/examples.html)
- [Libguestfs Tools Documentation](https://libguestfs.org/)

### Best Practices and Guidelines
- [OpenShift Deployment Best Practices](https://docs.openshift.com/container-platform/latest/scalability_and_performance/recommended-host-practices.html)
- [OpenShift Security Guide](https://docs.openshift.com/container-platform/latest/security/index.html)
- [OpenShift Backup and Disaster Recovery](https://docs.openshift.com/container-platform/latest/backup_and_restore/index.html)

## Support Matrix

| Feature | SNO | 3-Node | HA Cluster |
|---------|-----|--------|------------|
| Bare Metal | ✓ | ✓ | ✓ |
| vSphere | ✓ | ✓ | ✓ |
| Platform None | ✓ | ✓ | ✓ |
| Bond Networking | ✓ | ✓ | ✓ |
| VLAN Support | ✓ | ✓ | ✓ |
| Disconnected | ✓ | ✓ | ✓ |

---
*Note: For detailed examples of networking configurations (VLAN, Bond, Bond+VLAN), refer to the [Network Configuration Guide](network-configuration.md).*
