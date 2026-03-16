---
layout: default
title: "ADR-0002-advanced-networking-configurations: ---"
description: "Architecture Decision Record for Advanced Networking Configurations Support"
---

# ADR-002: Advanced Networking Configurations Support

## Date
2025-03-09

## Status
Accepted

## Decision Makers
- OpenShift Platform Team
- Network Architecture Team

## Context
OpenShift Container Platform deployments require flexible networking configurations to support:
- Various environments (bare metal, virtualized)
- Different network topologies
- High availability requirements
- Performance optimization
- Network segregation

## Considered Options

### 1. Basic Networking Only
- Pros:
  - Simpler configuration
  - Easier troubleshooting
- Cons:
  - Limited functionality
  - No performance optimization options
  - Inadequate for complex deployments

### 2. Full Advanced Networking (Selected)
- Pros:
  - Supports complex network topologies
  - Enables performance optimization
  - Provides network redundancy
  - Allows traffic segregation
- Cons:
  - More complex configuration
  - Requires more detailed documentation
  - Higher learning curve

## Decision
Implement comprehensive support for advanced networking configurations including:
1. Network Bonding
   - Multiple bonding modes
   - Link monitoring
   - Failover capabilities

2. VLAN Support
   - VLAN tagging
   - Multiple VLAN interfaces
   - Traffic segregation

3. SR-IOV Integration
   - Hardware-level network virtualization
   - Enhanced performance
   - Direct hardware access

## Implementation

### Network Configuration Structure
```yaml
networkConfig:
  interfaces:
    - name: bond0.300
      type: vlan
      state: up
      vlan:
        base-iface: bond0
        id: 300
    - name: bond0
      type: bond
      state: up
      link-aggregation:
        mode: active-backup
        options:
          miimon: "150"
```

### Supported Features
1. **Bonding Modes**
   - active-backup
   - balance-tlb
   - balance-alb
   - 802.3ad (LACP)

2. **VLAN Features**
   - Tagged VLANs
   - Multiple VLAN interfaces
   - QoS support

3. **SR-IOV Capabilities**
   - VF configuration
   - Hardware offloading
   - Resource allocation

## Example Configurations
Located in `examples/` directory:
```
examples/
├── bond0-single-bond0-vlan/
├── cnv-bond0-tagged/
├── sno-bond0-signal-vlan/
└── stretched-metro-cluster/
```

## Consequences

### Positive
1. Support for complex network requirements
2. Enhanced performance options
3. High availability capabilities
4. Network isolation and security
5. Hardware-level optimizations

### Negative
1. Increased configuration complexity
2. More extensive testing required
3. Additional documentation needed
4. Higher skill requirement for deployment

## Validation

### Configuration Validation
- Pre-installation network validation
- Hardware compatibility checks
- Configuration syntax verification

### Test Cases
Network-specific test cases in `e2e-tests/`:
```bash
e2e-tests/
├── validate_env.sh
└── run_e2e.sh
```

## Related
- [Installation Guide](../installation-guide)
- [Network Configuration Examples](../examples/)
- [ADR-001: Agent-based Installation Approach](0001-agent-based-installation-approach)

## Notes
Key considerations for implementation:
1. Hardware compatibility
2. Performance impact
3. Failover behavior
4. Monitoring requirements
5. Troubleshooting procedures

Templates for network configurations are provided in:
```
playbooks/templates/
└── agent-config.yml.j2
