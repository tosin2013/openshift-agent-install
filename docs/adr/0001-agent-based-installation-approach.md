---
layout: default
title: "ADR-0001-agent-based-installation-approach: ---"
description: "Architecture Decision Record for Agent-based Installation Approach for OpenShift Deployment"
---

# ADR-001: Agent-based Installation Approach for OpenShift Deployment

## Date
2025-03-09

## Status
Accepted

## Decision Makers
- OpenShift Platform Team
- Infrastructure Architecture Team

## Context
OpenShift Container Platform requires a reliable, flexible installation method that can:
- Work in both connected and disconnected environments
- Support air-gapped installations
- Handle various infrastructure types (bare metal, VMware, etc.)
- Support advanced networking configurations
- Work consistently across different CPU architectures

The traditional installation methods have limitations in disconnected environments and require complex infrastructure setup.

## Considered Options

### 1. Installer-Provisioned Infrastructure (IPI)
- Pros:
  - Automated infrastructure provisioning
  - Integrated with cloud providers
- Cons:
  - Requires internet connectivity
  - Limited flexibility in disconnected environments
  - Complex infrastructure requirements

### 2. User-Provisioned Infrastructure (UPI)
- Pros:
  - More control over infrastructure
  - Works in disconnected environments
- Cons:
  - Manual infrastructure setup
  - Complex orchestration required
  - Higher risk of human error

### 3. Agent-based Installation (Selected)
- Pros:
  - Works offline and in air-gapped environments
  - Combines ease of use of Assisted Installation
  - Flexible server boot options
  - Platform-agnostic approach
  - Supports advanced networking (bonds, VLANs, SR-IOV)
- Cons:
  - Requires bootable ISO creation
  - Initial setup complexity

## Decision
We chose the Agent-based Installation approach because it provides:
1. Maximum flexibility for different environments
2. Support for disconnected and air-gapped installations
3. Built-in validation and automation capabilities
4. Platform-agnostic deployment options

## Implementation

### Core Components
1. Agent Discovery Service
   - Embedded in bootable ISO
   - Handles node discovery and configuration

2. Configuration Management
   - `install-config.yaml` for cluster configuration
   - `agent-config.yaml` for host-specific settings

3. Network Configuration
   - Support for DHCP and static IP
   - Advanced networking (bonds, VLANs)
   - SR-IOV capability

### Example Structure
```
examples/
├── baremetal-example/
├── vmware-example/
├── sno-bond0-signal-vlan/
└── various network configurations/
```

## Consequences

### Positive
1. Simplified deployment in disconnected environments
2. Consistent installation experience across platforms
3. Reduced dependency on external services
4. Flexible networking configuration
5. Support for all major CPU architectures

### Negative
1. Initial learning curve for ISO creation
2. Additional storage requirements for ISO
3. Boot media management overhead

## Related
- [Installation Guide](../installation-guide)
- [Configuration Guide](../configuration-guide)
- [Network Configuration](../network-configuration)
- [Example Configurations](../../examples/)

## Notes
This approach is particularly well-suited for:
- Edge computing deployments
- Highly secure environments
- Multi-architecture deployments
- Complex networking requirements

## Test Cases
Key test cases are implemented in the e2e-tests directory:
```bash
e2e-tests/
├── bootstrap_env.sh
├── run_e2e.sh
└── validate_env.sh
