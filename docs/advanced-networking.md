---
layout: default
title: Advanced Networking
description: Advanced networking configurations and features for OpenShift Agent-based installations
---

# Advanced Networking Guide

This guide covers advanced networking features and configurations for OpenShift Agent-based installations.

## Network Interface Bonding

### Mode Selection

Common bonding modes:
- Mode 0 (balance-rr)
- Mode 1 (active-backup)
- Mode 4 (802.3ad)
- Mode 5 (balance-tlb)
- Mode 6 (balance-alb)

### Example Bond Configuration

```yaml
networkConfig:
  interfaces:
    - name: bond0
      type: bond
      state: up
      ipv4:
        enabled: true
        dhcp: false
        address:
          - ip: 192.168.1.10
            prefix-length: 24
      link-aggregation:
        mode: 802.3ad
        options:
          miimon: '140'
        port:
          - enp1s0
          - enp2s0
```

## VLAN Configuration

### Single VLAN Setup

```yaml
networkConfig:
  interfaces:
    - name: bond0.100
      type: vlan
      state: up
      ipv4:
        enabled: true
        dhcp: false
        address:
          - ip: 192.168.100.10
            prefix-length: 24
      vlan:
        base-iface: bond0
        id: 100
```

### Multiple VLANs

```yaml
networkConfig:
  interfaces:
    - name: bond0.100  # Management VLAN
      type: vlan
      vlan:
        base-iface: bond0
        id: 100
    - name: bond0.200  # Storage VLAN
      type: vlan
      vlan:
        base-iface: bond0
        id: 200
    - name: bond0.300  # Application VLAN
      type: vlan
      vlan:
        base-iface: bond0
        id: 300
```

## SR-IOV Configuration

### Device Configuration

```yaml
apiVersion: sriovnetwork.openshift.io/v1
kind: SriovNetworkNodePolicy
metadata:
  name: sriov-policy
  namespace: openshift-sriov-network-operator
spec:
  deviceType: vfio-pci
  nicSelector:
    pfNames: ["ens1f0"]
  nodeSelector:
    feature.node.kubernetes.io/network-sriov.capable: "true"
  numVfs: 8
  priority: 10
  resourceName: sriovnic
```

### Network Attachment

```yaml
apiVersion: sriovnetwork.openshift.io/v1
kind: SriovNetwork
metadata:
  name: sriov-network
  namespace: openshift-sriov-network-operator
spec:
  resourceName: sriovnic
  networkNamespace: default
  ipam: |
    {
      "type": "host-local",
      "subnet": "10.56.217.0/24",
      "rangeStart": "10.56.217.171",
      "rangeEnd": "10.56.217.181",
      "gateway": "10.56.217.1"
    }
```

## Multi-Network Configuration

### Secondary Network Interface

```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: secondary-network
  namespace: default
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "type": "macvlan",
      "master": "eth1",
      "mode": "bridge",
      "ipam": {
        "type": "host-local",
        "subnet": "192.168.2.0/24",
        "rangeStart": "192.168.2.100",
        "rangeEnd": "192.168.2.200",
        "gateway": "192.168.2.1"
      }
    }
```

## Quality of Service (QoS)

### Traffic Shaping

```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: qos-network
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "type": "bandwidth",
      "ingressRate": 1000000,
      "ingressBurst": 1000000,
      "egressRate": 1000000,
      "egressBurst": 1000000
    }
```

## Network Security

### Encryption Configuration

```yaml
apiVersion: operator.openshift.io/v1
kind: Network
metadata:
  name: cluster
spec:
  defaultNetwork:
    ovnKubernetesConfig:
      ipsecConfig:
        enable: true
```

### Network Policy Examples

#### Isolate Namespace

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: isolate-namespace
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: allowed-namespace
```

## Advanced Troubleshooting

### Network Performance Testing

```bash
# Install performance testing tools
oc debug node/<node_name>
chroot /host
dnf install -y iperf3

# Run iperf3 server
iperf3 -s

# Run iperf3 client
iperf3 -c <server_ip> -t 30
```

### Packet Capture

```bash
# Capture packets on node
oc debug node/<node_name>
chroot /host
tcpdump -i any -n port 6443

# Analyze pod traffic
oc exec <pod_name> -- tcpdump -i eth0 -n
```

### MTU Verification

```bash
# Check MTU settings
oc debug node/<node_name>
chroot /host
ip link show

# Test MTU
ping -s 8972 -M do <destination_ip>
```

## Performance Tuning

### Network Tuning Parameters

```yaml
apiVersion: tuned.openshift.io/v1
kind: Tuned
metadata:
  name: network-tuning
  namespace: openshift-cluster-node-tuning-operator
spec:
  profile:
  - name: network-latency
    data: |
      [main]
      summary=Optimize for network latency
      include=network-latency
      [sysctl]
      net.ipv4.tcp_fastopen=3
      net.ipv4.tcp_tw_reuse=1
      net.ipv4.tcp_timestamps=0
```

## Related Documentation

- [Network Configuration](network-configuration)
- [Installation Guide](installation-guide)
- [Security Guide](security-guide)
- [Troubleshooting Guide](troubleshooting) 