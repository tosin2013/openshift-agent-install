---
layout: default
title: Platform Guides
description: Platform-specific guides for OpenShift Agent-based installations
---

# Platform Guides

This guide provides platform-specific instructions for OpenShift Agent-based installations.

## Overview

OpenShift Agent-based installations support multiple platforms, each with unique requirements and configurations:
- Bare Metal
- VMware vSphere
- Platform None (Generic x86)

## Bare Metal

### Prerequisites

```yaml
Requirements:
  Hardware:
    - Supported servers with IPMI/Redfish
    - Network switches with VLAN support
    - Storage systems (if using external storage)
  Network:
    - DHCP server (optional)
    - DNS server
    - Load balancer
  BMC:
    - IPMI or Redfish access
    - Administrative credentials
```

### Network Configuration

```yaml
apiVersion: v1alpha1
kind: AgentConfig
metadata:
  name: baremetal-cluster
spec:
  networking:
    machineNetwork:
      - cidr: 192.168.1.0/24
    clusterNetwork:
      - cidr: 10.128.0.0/14
        hostPrefix: 23
    serviceNetwork:
      - 172.30.0.0/16
```

### BMC Configuration

```yaml
apiVersion: v1alpha1
kind: AgentConfig
metadata:
  name: baremetal-node
spec:
  hosts:
    - hostname: master-0
      role: master
      bmcAddress: redfish://192.168.1.100/redfish/v1/Systems/1
      bmcCredentialsName: bmc-secret
      bootMACAddress: "52:54:00:00:00:01"
      rootDeviceHints:
        deviceName: /dev/sda
```

## VMware vSphere

### Prerequisites

```yaml
Requirements:
  vSphere:
    - vCenter 7.0 U2 or later
    - ESXi 7.0 U2 or later
    - Datacenter with sufficient resources
    - Storage with sufficient space
  Network:
    - VM Network with DHCP
    - DNS configured
    - Load balancer
```

### vSphere Configuration

```yaml
apiVersion: v1alpha1
kind: AgentConfig
metadata:
  name: vsphere-cluster
spec:
  platform:
    vsphere:
      vcenters:
        - server: vcenter.example.com
          username: administrator@vsphere.local
          password: password
          datacenters:
            - datacenter1
      workspace:
        server: vcenter.example.com
        datacenter: datacenter1
        datastore: datastore1
        folder: /datacenter1/vm/folder1
        network: "VM Network"
```

### Resource Requirements

```yaml
Minimum Resources:
  Control Plane:
    CPU: 8 vCPU
    Memory: 32 GB
    Storage: 120 GB
  Worker Nodes:
    CPU: 8 vCPU
    Memory: 16 GB
    Storage: 120 GB
```

## Platform None (Generic x86)

### Prerequisites

```yaml
Requirements:
  Hardware:
    - x86_64 systems
    - UEFI or BIOS boot
    - Network connectivity
  Network:
    - Static IP or DHCP
    - DNS configuration
    - Load balancer
```

### Configuration

```yaml
apiVersion: v1alpha1
kind: AgentConfig
metadata:
  name: generic-cluster
spec:
  hosts:
    - hostname: master-0
      role: master
      interfaces:
        - name: ens3
          macAddress: "52:54:00:00:00:01"
      networkConfig:
        interfaces:
          - name: ens3
            type: ethernet
            state: up
            ipv4:
              enabled: true
              address:
                - ip: 192.168.1.10
                  prefix-length: 24
```

## Common Platform Tasks

### Network Configuration

#### Static IP Configuration

```yaml
networkConfig:
  interfaces:
    - name: ens3
      type: ethernet
      state: up
      ipv4:
        enabled: true
        dhcp: false
        address:
          - ip: 192.168.1.10
            prefix-length: 24
```

#### DHCP Configuration

```yaml
networkConfig:
  interfaces:
    - name: ens3
      type: ethernet
      state: up
      ipv4:
        enabled: true
        dhcp: true
```

### Storage Configuration

#### Local Storage

```yaml
storage:
  disks:
    - device: /dev/sda
      partitions:
        - size: 100GiB
          start: 0GiB
          label: data
```

#### Shared Storage

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: shared-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
```

## Platform-specific Troubleshooting

### Bare Metal

```bash
# Check BMC connectivity
ipmitool -I lanplus -H bmc_host -U username -P password power status

# Verify PXE boot
tcpdump -i interface port 67 or port 68 -n
```

### VMware

```bash
# Check vSphere connectivity
govc about

# Verify VM resources
govc vm.info master-0
```

### Generic x86

```bash
# Check system requirements
lscpu
free -h
df -h

# Verify network
ip addr show
```

## Post-installation Tasks

### Platform-specific Operators

```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: platform-operator
  namespace: openshift-operators
spec:
  channel: stable
  name: platform-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
```

### Storage Configuration

```yaml
apiVersion: config.openshift.io/v1
kind: Storage
metadata:
  name: cluster
spec:
  storageClassDevices:
    - devicePaths:
        - /dev/disk/by-id/scsi-example
      storageClassName: local-storage
```

## Related Documentation

- [Installation Guide](installation-guide)
- [Network Configuration](network-configuration)
- [Storage Configuration](storage-configuration)
- [BMC Management](bmc-management)
- [Troubleshooting Guide](troubleshooting) 