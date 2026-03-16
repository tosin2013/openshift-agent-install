---
layout: default
title: Configuration Guide
description: Comprehensive configuration guide for OpenShift Agent-based installations
---

# Configuration Guide

This guide provides detailed information about configuring OpenShift Agent-based installations.

## Configuration Files

### cluster.yml
The main configuration file that defines cluster-wide settings.

```yaml
# Site Config Usage
use_site_configs: false

# Authentication
pull_secret_path: /home/lab-user/pullsecret.json
# ssh_public_key_path: ~/.ssh/id_rsa.pub  # Optional, will generate if not specified

# Cluster metadata
base_domain: example.com
cluster_name: ocp4

# Platform configuration
platform_type: baremetal  # Options: baremetal, vsphere, none

# Network configuration
api_vips:
  - 192.168.180.4
app_vips:
  - 192.168.180.5

# Optional NTP and DNS Configuration
ntp_servers:
  - 0.rhel.pool.ntp.org
  - 1.rhel.pool.ntp.org
dns_servers:
  - 192.168.180.9
  - 192.168.180.10
dns_search_domains:
  - example.com
  - example.network

# Network settings
cluster_network_cidr: 10.128.0.0/14
cluster_network_host_prefix: 23
service_network_cidrs:
  - 172.30.0.0/16
machine_network_cidrs:
  - 192.168.180.0/23
network_type: OVNKubernetes

# Bootstrap configuration
rendezvous_ip: 192.168.180.21
```

### nodes.yml
Node-specific configuration including networking and storage.

```yaml
# Node configuration
nodes:
  - hostname: master-0
    role: master
    rootDeviceHints:
      deviceName: /dev/sda
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
              - ip: 192.168.180.21
                prefix-length: 23
          link-aggregation:
            mode: active-backup
            ports:
              - enp1s0
              - enp2s0
```

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

## Additional Resources

- Check the `examples/` directory for more configuration examples
- Review `disconnected-info.md` for disconnected installation details
- Use the playbooks in `playbooks/` for automated deployments

## Related Documentation

- [Installation Guide](installation-guide)
- [Network Configuration](network-configuration)
- [BMC Management](bmc-management)
- [Deployment Patterns](deployment-patterns) 