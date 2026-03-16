---
layout: default
title: "ADR-013: End-to-End Testing Framework"
description: "Architecture Decision Record for End-to-End Testing Framework"
---

# ADR-013: End-to-End Testing Framework

## Date
2025-03-09

## Status
Accepted

## Decision Makers
- Development Team
- QA Engineers

## Stakeholders
- Development Team
- QA Engineers
- System Administrators
- Platform Engineers

## Context
The project requires a comprehensive end-to-end testing framework to validate OpenShift installations across different environments and configurations. This includes environment setup, validation, test execution, and cleanup procedures.

## Considered Options
1. Manual testing procedures
2. Pure automated testing frameworks (like Robot Framework)
3. Custom shell-based testing framework
4. Container-based testing environment
5. Hybrid approach with shell scripts and automation tools

## Decision
We have implemented a modular end-to-end testing framework with the following components:

1. **Core Test Scripts**
   - `bootstrap_env.sh`: Environment setup and dependency installation
   - `validate_env.sh`: Environment validation and prerequisite checks
   - `run_e2e.sh`: Main test orchestration and execution
   - `delete_e2e.sh`: Environment cleanup and resource removal

2. **Test Flow Components**
   - Environment validation
   - Test ISO creation
   - VM deployment
   - Installation monitoring
   - Test execution
   - Environment cleanup

3. **Infrastructure Management**
   - System package installation
   - OpenShift CLI tools setup
   - Container runtime configuration
   - Network and DNS setup
   - FreeIPA integration
   - KVM/libvirt management

4. **Testing Functions**
   - ISO creation and validation
   - VM deployment and monitoring
   - DNS configuration
   - Cluster deployment validation
   - Resource cleanup

## Implementation Details

### Test Flow
```bash
1. Environment Setup (bootstrap_env.sh)
   - System package installation
   - Ansible collection setup
   - OpenShift CLI installation
   - Container tools configuration
   - SELinux setup
   - Infrastructure configuration
   - Registry authentication

2. Environment Validation (validate_env.sh)
   - System requirements check
   - Network configuration validation
   - Required tools verification
   - Infrastructure service status

3. Test Execution (run_e2e.sh)
   - Site configuration validation
   - ISO creation
   - VM deployment
   - Installation monitoring
   - Test case execution
   - Results collection

4. Cleanup (delete_e2e.sh)
   - VM cleanup
   - Network configuration cleanup
   - Resource removal
   - Environment restoration
```

### Key Features
1. **Modular Design**
   - Separate scripts for different phases
   - Reusable functions
   - Clear separation of concerns

2. **Infrastructure Management**
   - Automated VM provisioning
   - Network configuration
   - DNS management
   - Storage setup

3. **Validation Framework**
   - Comprehensive environment checks
   - Clear status reporting
   - Detailed error logging
   - Progress monitoring

4. **Configuration Management**
   - Site configuration handling
   - Cluster configuration
   - Network settings
   - DNS configuration

## Consequences

### Positive
1. Automated end-to-end testing
2. Consistent test environments
3. Comprehensive validation
4. Clear error reporting
5. Modular and maintainable
6. Support for different deployment scenarios

### Negative
1. Shell script complexity
2. Environment setup overhead
3. Dependency on external tools
4. Platform-specific requirements

## Test Cases
The framework supports testing:
- Different cluster configurations
- Various network setups
- Multiple deployment scenarios
- Infrastructure components
- Installation processes

## Related ADRs
- [ADR-006: Testing and Execution Environment](0006-testing-and-execution-environment)
- [ADR-007: Virtual Infrastructure Testing](0007-virtual-infrastructure-testing)
- [ADR-009: Testing Infrastructure and ISO Management](0009-testing-infrastructure-and-iso-management)

## Related
- [Installation Guide](../installation-guide)
- [Configuration Guide](../configuration-guide)
- [Network Configuration](../network-configuration)
- [Example Configurations](../../examples/)
