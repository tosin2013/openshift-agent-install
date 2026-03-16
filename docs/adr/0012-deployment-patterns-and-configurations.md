---
layout: default
title: "ADR-0012-deployment-patterns-and-configurations: ---"
description: "Architecture Decision Record for standardized deployment patterns and reference configurations"
---

# 12. Deployment Patterns and Reference Configurations

## Date
2025-03-09

## Status
Accepted

## Decision Makers
- Development Team
- Platform Engineers
- Network Engineers

## Stakeholders
- Platform Engineers
- System Administrators
- Network Engineers
- Cluster Operators

## Context
The project requires standardized deployment patterns and reference configurations to support various OpenShift installation scenarios. These patterns need to address different networking configurations, platform types, and cluster architectures while maintaining consistency and reliability.

## Considered Options
1. Ad-hoc configuration approach
2. Limited set of supported configurations
3. Comprehensive reference architecture patterns
4. Platform-specific templates only
5. Network-centric pattern library

## Decision
We have implemented a comprehensive set of reference configurations and deployment patterns:

1. **Platform-Specific Patterns**
   - Baremetal deployments (`baremetal-example/`)
   - VMware deployments (`vmware-example/`)
   - VMware disconnected environments (`vmware-disconnected-example/`)
   - Single Node OpenShift (SNO) deployments

2. **Network Configuration Patterns**
   - Bond configurations with VLANs (`bond0-single-bond0-vlan/`)
   - CNV with bonded interfaces (`cnv-bond0-tagged/`)
   - Converged networking (`converged-bond0-signal-vlan/`)
   - Stretched metro clusters (`stretched-metro-cluster/`)

3. **Node Scale Patterns**
   - Single Node OpenShift variations (`sno-*` examples)
   - Three-node clusters
   - Standard clusters (3 control plane + workers)

4. **Advanced Network Configurations**
   - Link aggregation (802.3ad bonding)
   - VLAN tagging and segregation
   - Multi-network support
   - Advanced routing configurations

## Rationale
- Reference configurations ensure consistent deployments
- Standardized patterns reduce implementation errors
- Comprehensive examples cover common use cases
- Network patterns address complex requirements
- Support for various scales and architectures

## Consequences

### Positive
1. Clear deployment guidance
2. Standardized configurations
3. Reduced implementation time
4. Validated network patterns
5. Platform-specific optimizations
6. Flexible architecture options

### Negative
1. Maintenance overhead for examples
2. Need to keep patterns updated
3. May not cover all use cases
4. Complexity in pattern selection

## Implementation Details

### Deployment Patterns

1. **Single Node OpenShift (SNO)**
   - Minimal resource requirements
   - Simplified networking
   - Development and edge use cases

2. **Standard Cluster**
   - 3 control plane nodes
   - Configurable worker count
   - High availability design

3. **Stretched Clusters**
   - Metro area deployments
   - Zone awareness
   - Network redundancy

### Network Configurations

1. **Bond Configurations**
   ```yaml
   interfaces:
     - name: bond0
       type: bond
       state: up
       link-aggregation:
         mode: 802.3ad
         options:
           miimon: '140'
         port:
         - enp1s0
         - enp2s0
   ```

2. **VLAN Configurations**
   ```yaml
   - name: bond0.1924
     type: vlan
     state: up
     vlan:
       base-iface: bond0
       id: 1924
   ```

3. **Route Configurations**
   ```yaml
   routes:
     config:
     - destination: 0.0.0.0/0
       next-hop-interface: bond0.1924
       table-id: 254
   ```

### Platform-Specific Features

1. **Baremetal**
   - BMC integration
   - Hardware requirements
   - Network prerequisites

2. **VMware**
   - vSphere integration
   - Resource allocation
   - Network mapping

3. **Disconnected**
   - Registry mirroring
   - Network isolation
   - Update service configuration

## Links

### Test Cases
- End-to-end deployment tests
- Network validation tests
- Platform-specific tests

### Related ADRs
- ADR-0001: Agent-based Installation Approach
- ADR-0002: Advanced Networking Configurations
- ADR-0004: Disconnected Installation Support

### Code References
- `examples/baremetal-example/`
- `examples/vmware-example/`
- `examples/stretched-metro-cluster/`
- Various SNO configurations

### External References
- OpenShift Installation Documentation
- Network Configuration Guidelines
- Platform-specific Documentation

## Related
- [Installation Guide](../installation-guide)
- [Configuration Guide](../configuration-guide)
- [Network Configuration](../network-configuration)
- [Example Configurations](../../examples/)
