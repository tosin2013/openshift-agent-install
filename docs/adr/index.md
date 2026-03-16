---
layout: default
title: "Architecture Decision Records (ADRs)"
description: "Index of Architecture Decision Records for the OpenShift Agent Install Helper project"
---

# Architectural Decision Records (ADRs)

This directory contains the Architectural Decision Records (ADRs) for the OpenShift Agent-Based Installer Helper project. This utility provides automation and configuration management to simplify the usage of the OpenShift Agent-Based Installer.

## What is an ADR?

An Architectural Decision Record (ADR) is a document that captures an important architectural decision made along with its context and consequences. It provides a record of what was decided, why it was decided, and how it impacts the project.

## ADR Format

Each ADR follows a consistent format:
- Title and status
- Context
- Decision
- Consequences
- Implementation details
- Related documentation and test cases

## Index

### Active ADRs

1. [ADR-001: Agent-based Installation Approach](0001-agent-based-installation-approach)
   - Documents the foundational approach using OpenShift Agent-Based Installer
   - Covers connected and disconnected scenarios
   - Details platform support (baremetal, vsphere, none)

2. [ADR-002: Advanced Networking Configurations](0002-advanced-networking-configurations)
   - Details network architecture and configuration options
   - Covers bonding, VLANs, and SR-IOV support
   - Provides NMState configuration examples

3. [ADR-003: Ansible-based Automation](0003-ansible-automation-approach)
   - Establishes automation strategy using Ansible
   - Documents declarative vs manual approaches
   - Details template management and configuration

4. [ADR-004: Disconnected Installation Support](0004-disconnected-installation-support)
   - Comprehensive disconnected environment support
   - Registry mirroring and certificate management
   - Proxy and update service configuration

5. [ADR-005: ISO Creation and Asset Management](0005-iso-creation-and-asset-management)
   - Automated ISO generation process
   - Standardized asset organization
   - Post-installation instructions handling

6. [ADR-006: Testing and Execution Environment](0006-testing-and-execution-environment)
   - Comprehensive testing framework
   - Dependency management
   - Environment validation strategy

7. [ADR-007: Virtual Infrastructure Testing](0007-virtual-infrastructure-testing)
   - KVM/QEMU virtualization platform decisions
   - Resource allocation strategies
   - Network configuration approach
   - BMC emulation implementation

8. [ADR-008: BMC Management and Automation](0008-bmc-management-and-automation)
   - BMC management through Redfish
   - Infrastructure configuration automation
   - Deployment and monitoring tools
   - System integration approaches

9. [ADR-009: Testing Infrastructure and ISO Management](0009-testing-infrastructure-and-iso-management)
   - ISO creation automation
   - Testing framework architecture
   - Environment management
   - Monitoring and control systems

10. [ADR-010: Manifest Generation and Template Management](0010-manifest-generation-and-templating)
    - Centralized manifest generation
    - Template organization strategy
    - Configuration management approach
    - Platform-specific customization

11. [ADR-011: Identity Management Integration](0011-identity-management-integration)
    - FreeIPA integration strategy
    - DNS management automation
    - Certificate lifecycle management
    - Authentication and authorization approach

12. [ADR-012: Deployment Patterns and Reference Configurations](0012-deployment-patterns-and-configurations)
    - Standardized deployment patterns
    - Network configuration templates
    - Platform-specific examples
    - Scale and architecture variations

13. [ADR-013: End-to-End Testing Framework](0013-end-to-end-testing-framework)
    - Environment management framework
    - Testing components and validation
    - Test execution orchestration
    - Infrastructure setup and cleanup

14. [ADR-014: Disconnected Deployment Methods](0014-disconnected-deployment-methods)
    - Appliance method for air-gap deployments
    - Agent + Mirror Registry method
    - Complete install and upgrade workflows

15. [ADR-015: Multipath Root Device Configuration](0015-multipath-root-device-configuration)
    - Support for all rootDeviceHints parameters
    - Multipath SAN storage configuration
    - WWN-based device identification
    - Enterprise storage scenarios

## Categories

### Installation Strategy
- [ADR-001: Agent-based Installation Approach](0001-agent-based-installation-approach)
- [ADR-003: Ansible-based Automation](0003-ansible-automation-approach)
- [ADR-010: Manifest Generation and Template Management](0010-manifest-generation-and-templating)
- [ADR-012: Deployment Patterns and Reference Configurations](0012-deployment-patterns-and-configurations)

### Networking
- [ADR-002: Advanced Networking Configurations](0002-advanced-networking-configurations)
- [ADR-012: Deployment Patterns and Reference Configurations](0012-deployment-patterns-and-configurations)

### Automation & Installation
- [ADR-003: Ansible-based Automation](0003-ansible-automation-approach)
- [ADR-004: Disconnected Installation Support](0004-disconnected-installation-support)
- [ADR-005: ISO Creation and Asset Management](0005-iso-creation-and-asset-management)
- [ADR-006: Testing and Execution Environment](0006-testing-and-execution-environment)

### Infrastructure & Testing
- [ADR-007: Virtual Infrastructure Testing](0007-virtual-infrastructure-testing)
- [ADR-008: BMC Management and Automation](0008-bmc-management-and-automation)
- [ADR-009: Testing Infrastructure and ISO Management](0009-testing-infrastructure-and-iso-management)
- [ADR-013: End-to-End Testing Framework](0013-end-to-end-testing-framework)

### Configuration & Identity Management
- [ADR-010: Manifest Generation and Template Management](0010-manifest-generation-and-templating)
- [ADR-011: Identity Management Integration](0011-identity-management-integration)
- [ADR-015: Multipath Root Device Configuration](0015-multipath-root-device-configuration)

### Reference Architecture
- [ADR-012: Deployment Patterns and Reference Configurations](0012-deployment-patterns-and-configurations)

### Storage & Infrastructure
- [ADR-015: Multipath Root Device Configuration](0015-multipath-root-device-configuration)

### Testing Framework
- [ADR-006: Testing and Execution Environment](0006-testing-and-execution-environment)
- [ADR-013: End-to-End Testing Framework](0013-end-to-end-testing-framework)

## ADR States

ADRs can have the following states:
- **Proposed**: Under discussion
- **Accepted**: Approved and implemented
- **Deprecated**: No longer applicable but kept for historical record
- **Superseded**: Replaced by a newer ADR

## Contributing

When creating a new ADR:
1. Copy the template from an existing ADR
2. Use the next available number in sequence
3. Follow the established format
4. Update this index with the new ADR
5. Link related ADRs together

## Related Documentation

- [Installation Guide](../installation-guide)
- [Configuration Guide](../configuration-guide)
- [Example Configurations](../../examples/)
