---
layout: default
title: Network Configuration
description: Guide for configuring networking using the OpenShift Agent-based Installation Helper
---

# Network Configuration Guide

This guide covers network configuration using the OpenShift Agent-based Installation Helper tools and playbooks.

## Overview

This helper repository simplifies network configuration for OpenShift Agent-based installations by providing:
- Pre-defined network configuration templates
- Ansible playbooks for network validation
- Helper scripts for common network setups
- Automated network configuration generation

## Using the Network Configuration Tools

### 1. Define Network Configuration

Create your network configuration in your cluster's variables file:

```yaml
# cluster.yml
network_config:
  api_vips:
    - 192.168.70.46
  app_vips:
    - 192.168.70.46
  machine_network_cidrs:
    - 192.168.70.0/23
  cluster_network_cidr: 10.128.0.0/14
  cluster_network_host_prefix: 23
  service_network_cidrs:
    - 172.30.0.0/16
  network_type: OVNKubernetes
```

### 2. Generate Network Configuration

Use the provided playbook to generate your network configuration:

```bash
cd playbooks/
ansible-playbook -e "@your-cluster-vars.yml" create-manifests.yml
```

### 3. Network Configuration Examples

#### Single Node OpenShift (SNO)
```yaml
nodes:
  - hostname: sno
    interfaces:
      - name: enp97s0f0
        mac_address: D0:50:99:DD:58:95
    networkConfig:
      interfaces:
        - name: enp97s0f0.70
          type: vlan
          state: up
          vlan:
            id: 70
            base-iface: enp97s0f0
          ipv4:
            enabled: true
            address:
              - ip: 192.168.70.46
                prefix-length: 23
```

#### Three-Node Cluster with Bonding
```yaml
nodes:
  - hostname: master-0
    interfaces:
      - name: ens3
        mac_address: "52:54:00:00:00:01"
      - name: ens4
        mac_address: "52:54:00:00:00:02"
    networkConfig:
      interfaces:
        - name: bond0
          type: bond
          state: up
          link-aggregation:
            mode: 802.3ad
            port:
              - ens3
              - ens4
```

## Network Validation

The repository provides validation tools to ensure your network configuration is correct:

```bash
# Run network validation playbook
./scripts/validate-network.sh your-cluster-vars.yml

# Verify DNS configuration
./scripts/verify-dns.sh your-cluster-name.domain
```

## Troubleshooting

### Common Issues

1. VIP Configuration
```bash
# Check VIP accessibility
./scripts/check-vips.sh your-cluster-vars.yml
```

2. Network Connectivity
```bash
# Validate node connectivity
./scripts/verify-connectivity.sh your-cluster-vars.yml
```

3. DNS Resolution
```bash
# Verify DNS setup
./scripts/verify-dns.sh your-cluster-vars.yml
```

## Related Documentation

- [Installation Guide](./installation-guide.md)
- [Configuration Guide](./configuration-guide.md)
- [Troubleshooting Guide](./troubleshooting.md)
- [Advanced Networking](./advanced-networking.md)

## External Resources

- [OpenShift Agent-Based Installation Overview](https://docs.openshift.com/container-platform/latest/installing/installing_with_agent_based_installer/preparing-to-install-with-agent-based-installer.html)
- [RHEL Network Configuration](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/configuring_and_managing_networking/index)
- [NMState Network Configuration](https://nmstate.io/examples.html)
