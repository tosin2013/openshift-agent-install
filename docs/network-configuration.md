---
layout: default
title: Network Configuration
description: Guide for configuring networking in OpenShift Agent-based installations
---

# Network Configuration Guide

This guide covers network configuration for OpenShift Agent-based installations.

## Overview

Proper network configuration is crucial for a successful OpenShift Agent-based installation. This guide covers:
- Network Requirements
- DNS Configuration
- Load Balancer Setup
- Network Policies
- Advanced Networking Features

## Network Requirements

### Minimum Requirements

- A dedicated network for cluster communication
- Non-overlapping subnets for:
  - Machine Network (for nodes)
  - Service Network (for services)
  - Cluster Network (for pods)
- Internet access (for connected installations) or appropriate proxy configuration

### Example Network Configuration

```yaml
apiVersion: v1alpha1
kind: AgentConfig
metadata:
  name: cluster-network
spec:
  networking:
    clusterNetwork:
      - cidr: 10.128.0.0/14
        hostPrefix: 23
    serviceNetwork:
      - 172.30.0.0/16
    machineNetwork:
      - cidr: 192.168.1.0/24
```

## DNS Configuration

### Required DNS Records

1. API Endpoints:
```
api.cluster_name.domain.com
api-int.cluster_name.domain.com
```

2. Ingress Wildcard:
```
*.apps.cluster_name.domain.com
```

### Example DNS Configuration

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: dns-config
  namespace: openshift-config
data:
  Corefile: |
    cluster.local:5353 {
        forward . 192.168.1.53
        errors
        health
    }
```

## Load Balancer Setup

### Required Endpoints

| Port      | Backend Protocol | Description           |
|-----------|-----------------|------------------------|
| 6443      | TCP            | Kubernetes API         |
| 22623     | TCP            | Machine Config Server  |
| 443, 80   | TCP            | Router/Ingress        |

### Example HAProxy Configuration

```
frontend kubernetes_api
    bind *:6443
    mode tcp
    option tcplog
    default_backend kubernetes_api

backend kubernetes_api
    mode tcp
    balance roundrobin
    server bootstrap bootstrap.example.com:6443 check
    server master0 master0.example.com:6443 check
    server master1 master1.example.com:6443 check
    server master2 master2.example.com:6443 check
```

## Network Policies

### Default Network Policies

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-by-default
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

### Example Allow Policy

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
spec:
  podSelector: {}
  ingress:
  - from:
    - podSelector: {}
```

## Advanced Features

### OVN-Kubernetes Configuration

```yaml
apiVersion: operator.openshift.io/v1
kind: Network
metadata:
  name: cluster
spec:
  defaultNetwork:
    ovnKubernetesConfig:
      mtu: 1400
      genevePort: 6081
```

### IPsec Encryption

```yaml
apiVersion: operator.openshift.io/v1
kind: Network
metadata:
  name: cluster
spec:
  defaultNetwork:
    ovnKubernetesConfig:
      ipsecConfig: {}
```

## Troubleshooting

### Common Network Issues

1. DNS Resolution
```bash
# Test DNS resolution
dig api.cluster_name.domain.com
dig test.apps.cluster_name.domain.com
```

2. Load Balancer Connectivity
```bash
# Test API endpoint
curl -k https://api.cluster_name.domain.com:6443/version
```

3. Pod-to-Pod Communication
```bash
# Test pod connectivity
oc debug node/<node_name>
chroot /host
ping <pod_ip>
```

### Network Diagnostics

```bash
# Check network operator status
oc get clusteroperator network

# View network configuration
oc get network.config.openshift.io cluster -o yaml

# Check pod networking
oc get pods -n openshift-network-operator
```

## Related Documentation

- [Installation Guide](installation-guide)
- [Configuration Guide](configuration-guide)
- [Troubleshooting Guide](troubleshooting)
- [Security Guide](security-guide)
