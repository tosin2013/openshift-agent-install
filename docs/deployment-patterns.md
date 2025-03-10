# Deployment Patterns Guide

This guide describes the supported deployment patterns and configurations for OpenShift Agent-based installations, providing detailed information about each pattern and its use cases.

## Table of Contents

- [Overview](#overview)
- [Single Node OpenShift](#single-node-openshift)
- [Three-Node Compact Cluster](#three-node-compact-cluster)
- [Standard HA Cluster](#standard-ha-cluster)
- [Stretched Clusters](#stretched-clusters)
- [Platform-Specific Patterns](#platform-specific-patterns)

## Overview

OpenShift Agent-based Installer supports various deployment patterns to accommodate different requirements and use cases. Each pattern has specific characteristics, requirements, and recommended configurations.

## Single Node OpenShift (SNO)

### Description
Single Node OpenShift combines control plane and worker node functions in a single node, ideal for edge computing and small deployments. For detailed deployment instructions, see [OpenShift SNO Documentation](https://docs.openshift.com/container-platform/latest/installing/installing_sno/install-sno-preparing-to-install-sno.html).

### Requirements
```yaml
Minimum Hardware:
- CPU: 8 vCPUs
- RAM: 32 GB
- Storage: 120 GB
```

### Example Configuration
```yaml
nodes:
  - hostname: sno-node
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
              - ip: 192.168.122.2
                prefix-length: 24
```

### Use Cases
- Edge Computing
- Remote Office/Branch Office (ROBO)
- Development Environments
- Small Production Deployments

## Three-Node Compact Cluster

### Description
Three control plane nodes that also run workloads, providing high availability with minimal hardware requirements. For official requirements and guidelines, see [OpenShift 3-Node Clusters](https://docs.openshift.com/container-platform/latest/installing/installing_platform_agnostic/installing-platform-agnostic.html#installation-three-node-cluster_installing-platform-agnostic).

### Requirements
```yaml
Per Node:
- CPU: 8 vCPUs
- RAM: 32 GB
- Storage: 120 GB
```

### Example Configuration
```yaml
nodes:
  - hostname: master-0
    role: master
    rootDeviceHints:
      deviceName: /dev/sda
    interfaces:
      - name: bond0
        mac_address: "52:54:00:00:00:01"
    networkConfig:
      bonds:
        - name: bond0
          interfaces:
            - enp1s0
            - enp2s0
          options:
            mode: active-backup
```

### Use Cases
- Medium-sized Deployments
- Resource-constrained Environments
- Cost-optimized Clusters

## Standard HA Cluster

### Description
Traditional high-availability cluster with separate control plane and worker nodes. For detailed HA configuration, see [OpenShift HA Installation](https://docs.openshift.com/container-platform/latest/installing/installing_bare_metal/installing-bare-metal.html).

### Requirements
```yaml
Control Plane Nodes (3):
- CPU: 8 vCPUs
- RAM: 32 GB
- Storage: 120 GB

Worker Nodes (2+):
- CPU: 8 vCPUs
- RAM: 32 GB
- Storage: 120 GB
```

### Example Configuration
```yaml
nodes:
  - hostname: master-0
    role: master
    networkConfig:
      bonds:
        - name: bond0
          interfaces:
            - enp1s0
            - enp2s0
  - hostname: worker-0
    role: worker
    networkConfig:
      bonds:
        - name: bond0
          interfaces:
            - enp1s0
            - enp2s0
```

### Use Cases
- Production Environments
- Enterprise Deployments
- Scalable Workloads

## Stretched Clusters

### Description
Clusters deployed across multiple physical locations or data centers. For details on multi-site deployments, see [OpenShift Stretched Clusters](https://docs.openshift.com/container-platform/latest/installing/installing_bare_metal/installing-bare-metal-network-customizations.html#installation-about-stretched-clusters_installing-bare-metal-network-customizations) and [Network Latency Requirements](https://docs.openshift.com/container-platform/latest/installing/installing_bare_metal/installing-bare-metal-network-customizations.html#installation-network-latency-requirements_installing-bare-metal-network-customizations).

### Requirements
```yaml
Per Location:
- Minimum 2 Control Plane Nodes
- Network Latency < 100ms
- Dedicated WAN Connection
```

### Example Configuration
```yaml
# Site A Configuration
nodes:
  - hostname: master-site-a-1
    role: master
    networkConfig:
      interfaces:
        - name: enp1s0
          type: ethernet
          state: up
          ipv4:
            address:
              - ip: 192.168.1.10
                prefix-length: 24

# Site B Configuration
nodes:
  - hostname: master-site-b-1
    role: master
    networkConfig:
      interfaces:
        - name: enp1s0
          type: ethernet
          state: up
          ipv4:
            address:
              - ip: 192.168.2.10
                prefix-length: 24
```

### Use Cases
- Disaster Recovery
- Geographic Distribution
- High Availability Requirements

## Platform-Specific Patterns

### Bare Metal
For detailed hardware requirements and configuration, see [OpenShift Bare Metal Installation](https://docs.openshift.com/container-platform/latest/installing/installing_bare_metal/installing-bare-metal.html).

1. **Standard Configuration**
```yaml
platform:
  baremetal:
    apiVIP: 192.168.1.5
    ingressVIP: 192.168.1.6
```

2. **BMC Configuration**
```yaml
nodes:
  - bmc:
      address: ipmi://192.168.1.100
      username: admin
      password: password
```

### VMware
For detailed vSphere requirements and setup, see [OpenShift VMware vSphere Installation](https://docs.openshift.com/container-platform/latest/installing/installing_vsphere/preparing-to-install-on-vsphere.html).

1. **Standard vSphere**
```yaml
platform:
  vsphere:
    vcenter: vcenter.example.com
    username: administrator@vsphere.local
    password: password
    datacenter: datacenter1
    defaultDatastore: datastore1
```

2. **Disconnected vSphere**
For complete disconnected installation requirements, see [OpenShift Disconnected Installation](https://docs.openshift.com/container-platform/latest/installing/disconnected_install/installing-mirroring-disconnected.html).
```yaml
imageContentSources:
  - mirrors:
    - registry.example.com:5000/ocp4/openshift4
    source: quay.io/openshift-release-dev/ocp-release
```

## Network Patterns
For comprehensive networking configuration, see [OpenShift Networking Configuration](https://docs.openshift.com/container-platform/latest/networking/understanding-networking.html) and [RHEL Network Bonding](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/managing_networking_infrastructure_and_configurations/configuring-network-bonding_managing-networking-infrastructure-and-configurations).

### Single Network Bond
```yaml
networkConfig:
  interfaces:
    - name: bond0
      type: bond
      state: up
      ipv4:
        enabled: true
      link-aggregation:
        mode: 802.3ad
        options:
          miimon: '140'
```

### VLAN over Bond
```yaml
networkConfig:
  interfaces:
    - name: bond0.100
      type: vlan
      state: up
      vlan:
        base-iface: bond0
        id: 100
```

## Related Documentation

### Internal References
- [Deployment Patterns ADR](adr/0012-deployment-patterns-and-configurations.md)
- [Network Configuration Guide](network-configuration.md)
- [BMC Management Guide](bmc-management.md)
- [Example Configurations](examples/)
- [End-to-End Testing Guide](e2e-testing.md)
- [Installation Guide](installation-guide.md)

### External References
- [OpenShift Documentation](https://docs.openshift.com/container-platform/latest/installing/installing_with_agent_based_installer/preparing-to-install-with-agent-based-installer.html)
- [OpenShift Agent-Based Installation Overview](https://docs.openshift.com/container-platform/latest/installing/installing_with_agent_based_installer/preparing-to-install-with-agent-based-installer.html)
- [OpenShift Networking Guidelines](https://docs.openshift.com/container-platform/latest/networking/understanding-networking.html)
- [Red Hat Enterprise Linux - Network Bond Configuration](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/managing_networking_infrastructure_and_configurations/configuring-network-bonding_managing-networking-infrastructure-and-configurations)
- [IPMI Specification v2.0](https://www.intel.com/content/www/us/en/products/docs/servers/ipmi/ipmi-second-gen-interface-spec-v2-rev1-1.html)
- [IEEE 802.3ad Link Aggregation](https://standards.ieee.org/ieee/802.3ad/3137/)
- [RFC 7348 - VXLAN](https://datatracker.ietf.org/doc/html/rfc7348)

### Hardware Vendor BMC Documentation
- [Dell iDRAC](https://www.dell.com/support/kbdoc/en-us/000178115/idrac9-versions-and-features)
- [HPE iLO](https://www.hpe.com/us/en/servers/integrated-lights-out-ilo.html)
- [Lenovo XClarity](https://sysmgt.lenovofiles.com/help/topic/com.lenovo.systems.management.xcc.doc/dw1lm_c_chapter1_introduction.html)
- [Supermicro IPMI](https://www.supermicro.com/en/solutions/management-software/ipmi)

## Pattern Selection Matrix

| Pattern | HA | Workload Size | Resource Efficiency | Geographic Distribution |
|---------|----|--------------|--------------------|------------------------|
| SNO | No | Small | High | Single Site |
| Compact | Yes | Medium | High | Single Site |
| Standard HA | Yes | Large | Medium | Single Site |
| Stretched | Yes | Large | Low | Multi-Site |

---
*Note: Choose the deployment pattern that best matches your requirements for availability, scalability, and resource constraints.*
