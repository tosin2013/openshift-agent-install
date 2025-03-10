---
layout: default
title: Reference Configurations
description: Reference configurations for OpenShift Agent-based installations
---

# Reference Configurations

This guide provides reference configurations for various OpenShift Agent-based installation scenarios.

## Overview

Reference configurations help ensure consistent and reliable OpenShift deployments. This guide includes:
- Single-Node OpenShift (SNO)
- Three-Node Compact Cluster
- Standard HA Cluster
- Platform-Specific Configurations
- Network Configurations
- Storage Configurations

## Single-Node OpenShift (SNO)

### Basic SNO Configuration

```yaml
apiVersion: v1alpha1
kind: AgentConfig
metadata:
  name: sno-cluster
spec:
  rendezvousIP: 192.168.1.10
  hosts:
    - hostname: sno-node
      role: master
      rootDeviceHints:
        deviceName: /dev/sda
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

### SNO with Bonded Network

```yaml
apiVersion: v1alpha1
kind: AgentConfig
metadata:
  name: sno-bonded
spec:
  hosts:
    - hostname: sno-node
      role: master
      interfaces:
        - name: ens3
          macAddress: "52:54:00:00:00:01"
        - name: ens4
          macAddress: "52:54:00:00:00:02"
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
            link-aggregation:
              mode: 802.3ad
              options:
                miimon: '100'
              port:
                - ens3
                - ens4
```

## Three-Node Compact Cluster

### Basic Compact Configuration

```yaml
apiVersion: v1alpha1
kind: AgentConfig
metadata:
  name: compact-cluster
spec:
  hosts:
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
                - ip: 192.168.1.10
                  prefix-length: 24
    - hostname: master-1
      role: master
      networkConfig:
        interfaces:
          - name: ens3
            type: ethernet
            state: up
            ipv4:
              enabled: true
              address:
                - ip: 192.168.1.11
                  prefix-length: 24
    - hostname: master-2
      role: master
      networkConfig:
        interfaces:
          - name: ens3
            type: ethernet
            state: up
            ipv4:
              enabled: true
              address:
                - ip: 192.168.1.12
                  prefix-length: 24
```

## Standard HA Cluster

### HA Cluster Configuration

```yaml
apiVersion: v1alpha1
kind: AgentConfig
metadata:
  name: ha-cluster
spec:
  hosts:
    - hostname: master-0
      role: master
    - hostname: master-1
      role: master
    - hostname: master-2
      role: master
    - hostname: worker-0
      role: worker
    - hostname: worker-1
      role: worker
  networking:
    clusterNetwork:
      - cidr: 10.128.0.0/14
        hostPrefix: 23
    serviceNetwork:
      - 172.30.0.0/16
    machineNetwork:
      - cidr: 192.168.1.0/24
```

## Platform-Specific Configurations

### Bare Metal Configuration

```yaml
apiVersion: v1alpha1
kind: AgentConfig
metadata:
  name: baremetal-cluster
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

### VMware Configuration

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
```

## Network Configurations

### Advanced Network Configuration

```yaml
apiVersion: v1alpha1
kind: AgentConfig
metadata:
  name: network-config
spec:
  networking:
    networkType: OVNKubernetes
    clusterNetwork:
      - cidr: 10.128.0.0/14
        hostPrefix: 23
    serviceNetwork:
      - 172.30.0.0/16
    machineNetwork:
      - cidr: 192.168.1.0/24
  hosts:
    - hostname: master-0
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
          - name: bond0.100
            type: vlan
            state: up
            vlan:
              base-iface: bond0
              id: 100
```

## Storage Configurations

### Local Storage Configuration

```yaml
apiVersion: v1alpha1
kind: AgentConfig
metadata:
  name: storage-config
spec:
  hosts:
    - hostname: master-0
      role: master
      rootDeviceHints:
        deviceName: /dev/sda
      storage:
        disks:
          - device: /dev/sdb
            partitions:
              - size: 100GiB
                start: 0GiB
                label: data
```

### External Storage Configuration

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-storage
provisioner: kubernetes.io/nfs
parameters:
  server: nfs-server.example.com
  path: /exports
  readOnly: "false"
```

## Related Documentation

- [Installation Guide](installation-guide)
- [Network Configuration](network-configuration)
- [Storage Configuration](storage-configuration)
- [Platform Guides](platform-guides)
- [Deployment Patterns](deployment-patterns) 