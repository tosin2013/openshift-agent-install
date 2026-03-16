---
layout: default
title: "ADR-0008-bmc-management-and-automation: ---"
description: "Architecture Decision Record for BMC Management and Infrastructure Automation"
---

# 8. BMC Management and Infrastructure Automation

## Date
2025-03-09

## Status
Accepted

## Decision Makers
- Development Team
- Infrastructure Team

## Stakeholders
- DevOps Engineers
- System Administrators
- Development Team

## Context
The project requires robust automation for managing Baseboard Management Controllers (BMC) and infrastructure components. This includes DNS configuration, storage management, and deployment automation. The solution needs to support both development and production environments while maintaining consistency and reliability.

## Considered Options
1. Manual configuration with documentation
2. Custom Python/Shell scripts without standardization
3. Ansible-based automation
4. Standardized shell scripts with modular design
5. Third-party management tools

## Decision
We have implemented a comprehensive set of automation tools through standardized shell scripts:

1. **BMC Management through Redfish**
   - Implemented in `configure-sushy-unix.sh`
   - Standardized BMC interface through Redfish API
   - Container-based emulation for testing

2. **Infrastructure Configuration**
   - DNS Management (`configure_dns_entries.sh`)
   - LVM Storage Configuration (`configure-lvm.sh`)
   - FreeIPA Integration (`deploy-freeipa.sh`)

3. **Deployment Automation**
   - KVM Deployment Scripts (`deploy-on-kvm.sh`)
   - ISO Creation Tools (`create-iso.sh`)
   - Network Configuration (`vyos-router.sh`)

4. **Monitoring and Maintenance**
   - VM State Management (`watch-and-reboot-kvm-vms.sh`)
   - Testing Tools (`test-libvirt-ssh.sh`)
   - BMC Host Generation (`generate_bmc_acm_hosts.py`)

## Rationale
- Shell scripts provide native OS integration
- Modular design allows for easy maintenance
- Standardized approach ensures consistency
- Built-in error handling and logging
- Support for both development and production use cases

## Consequences

### Positive
1. Consistent deployment process
2. Reduced manual intervention
3. Reproducible configurations
4. Easy troubleshooting
5. Version control friendly
6. Cross-environment compatibility

### Negative
1. Requires shell scripting knowledge
2. Platform-specific considerations
3. Maintenance overhead for scripts
4. Requires regular updates for new OS versions

## Implementation Details

### DNS Configuration (`configure_dns_entries.sh`)
- Automated DNS record management
- Support for multiple zones
- Integration with existing DNS infrastructure

### Storage Management (`configure-lvm.sh`)
- LVM volume creation and management
- Flexible storage allocation
- Support for various storage configurations

### FreeIPA Integration (`deploy-freeipa.sh`)
- Identity management setup
- Authentication integration
- Directory services configuration

### Network Automation (`vyos-router.sh`)
- VyOS router configuration
- Network segregation
- VLAN management

## Links

### Test Cases
- Integration tests in `e2e-tests/`
- Network validation scripts
- Storage configuration tests

### Related ADRs
- ADR-0007: Virtual Infrastructure Testing Environment
- ADR-0003: Ansible Automation Approach
- ADR-0004: Disconnected Installation Support

### Code References
- `hack/configure_dns_entries.sh`
- `hack/configure-lvm.sh`
- `hack/deploy-freeipa.sh`
- `hack/vyos-router.sh`
- `hack/generate_bmc_acm_hosts.py`

### External References
- Redfish API Specification
- VyOS Documentation
- FreeIPA Implementation Guide

## Related
- [Installation Guide](../installation-guide)
- [Configuration Guide](../configuration-guide)
- [Network Configuration](../network-configuration)
- [Example Configurations](../../examples/)
