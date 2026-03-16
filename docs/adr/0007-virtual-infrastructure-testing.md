---
layout: default
title: "ADR-007: Virtual Infrastructure Testing Environment"
description: "Architecture Decision Record for Virtual Infrastructure Testing Environment"
---

# ADR-007: Virtual Infrastructure Testing Environment

## Date
2025-03-09

## Status
Accepted

## Decision Makers
- Development Team
- Infrastructure Team
- QA Engineers

## Context
The project requires a reliable, reproducible testing environment for OpenShift deployments that can:
- Simulate bare metal infrastructure
- Support both connected and disconnected installations
- Provide consistent network configurations
- Enable automated testing and validation
- Support various cluster configurations

## Considered Options

### 1. VirtualBox
- Pros:
  - Cross-platform support
  - GUI management
- Cons:
  - Performance overhead
  - Limited automation capabilities
  - Network limitations

### 2. VMware Workstation/Fusion
- Pros:
  - Enterprise support
  - Mature tooling
- Cons:
  - License costs
  - Platform limitations
  - Complex automation

### 3. KVM/QEMU with libvirt (Selected)
- Pros:
  - Native Linux performance
  - Extensive automation support
  - Network flexibility
  - BMC emulation capability
- Cons:
  - Linux-specific
  - Setup complexity
  - Resource requirements

## Decision
Implement virtual infrastructure testing using KVM/QEMU with libvirt, featuring:

1. **Core Components**
   ```bash
   hack/
   ├── deploy-on-kvm.sh          # VM deployment
   ├── watch-and-reboot-kvm-vms.sh # VM monitoring
   ├── configure_dns_entries.sh   # DNS configuration
   ├── deploy-freeipa.sh         # Identity management
   └── vyos-router.sh           # Network routing
   ```

2. **Infrastructure Management**
   - KVM/QEMU for virtualization
   - Libvirt for VM management
   - VyOS for network routing
   - FreeIPA for identity services

3. **Resource Management**
   - Dynamic resource allocation
   - Automated VM provisioning
   - Network configuration
   - Storage management

## Implementation

### VM Deployment Process
1. **Environment Setup**
   ```bash
   # System requirements
   - libvirt
   - qemu-kvm
   - virt-manager
   - cloud-init
   ```

2. **Network Configuration**
   ```bash
   # Network components
   - Bridge networks
   - VLANs
   - DNS configuration
   - DHCP services
   ```

3. **VM Management**
   ```bash
   # Key operations
   - VM creation
   - Resource allocation
   - Network attachment
   - Boot monitoring
   ```

### Infrastructure Components

1. **Virtualization Layer**
   - KVM for hardware virtualization
   - QEMU for machine emulation
   - Libvirt for management API

2. **Network Infrastructure**
   - VyOS router for routing
   - Bridge networks for connectivity
   - VLAN support for segregation

3. **Support Services**
   - FreeIPA for identity management
   - DNS for name resolution
   - DHCP for IP management

### Test Integration

1. **Deployment Testing**
   ```bash
   # Test execution
   ./e2e-tests/run_e2e.sh <site_config>
   ```

2. **Infrastructure Validation**
   ```bash
   # Environment checks
   ./e2e-tests/validate_env.sh
   ```

## Consequences

### Positive
1. Native virtualization performance
2. Comprehensive automation support
3. Flexible network configuration
4. Integrated identity management
5. Resource optimization
6. Reproducible environments

### Negative
1. Linux platform dependency
2. Complex initial setup
3. High resource requirements
4. Technical expertise needed

## Test Scenarios

### Basic Testing
1. Single-node deployments
2. Multi-node clusters
3. Network configurations
4. Storage setups

### Advanced Testing
1. Disconnected installations
2. Custom network topologies
3. High-availability configurations
4. Failure scenarios

## Related ADRs
- [ADR-013: End-to-End Testing Framework](0013-end-to-end-testing-framework)
- [ADR-006: Testing and Execution Environment](0006-testing-and-execution-environment)
- [ADR-009: Testing Infrastructure and ISO Management](0009-testing-infrastructure-and-iso-management)

## Related
- [Installation Guide](../installation-guide)
- [Configuration Guide](../configuration-guide)
- [Network Configuration](../network-configuration)
- [Example Configurations](../../examples/)
