---
layout: default
title: "ADR-006: Testing and Execution Environment"
description: "Architecture Decision Record for Testing and Execution Environment"
---

# ADR-006: Testing and Execution Environment

## Date
2025-03-09

## Status
Accepted

## Decision Makers
- OpenShift Platform Team
- Quality Engineering Team

## Context
The OpenShift Agent-Based Installer Helper requires a consistent and reliable environment for:
- End-to-end testing of OpenShift installations
- System dependency management
- Infrastructure validation
- Execution consistency across different platforms

## Considered Options

### 1. Basic Script Testing
- Pros:
  - Simple implementation
  - Minimal overhead
- Cons:
  - Inconsistent environments
  - Manual dependency management
  - Limited test coverage

### 2. Comprehensive Testing Framework (Selected)
- Pros:
  - Consistent execution environment
  - Automated dependency resolution
  - Comprehensive test coverage
  - Infrastructure validation
- Cons:
  - Additional setup complexity
  - More maintenance required
  - Learning curve for contributors

## Decision
Implement a comprehensive testing framework with:

1. **Core Testing Components**
   ```bash
   e2e-tests/
   ├── bootstrap_env.sh    # Environment setup and dependencies
   ├── validate_env.sh     # Environment validation
   ├── run_e2e.sh         # Test orchestration
   └── delete_e2e.sh      # Environment cleanup
   ```

2. **Infrastructure Management**
   ```bash
   hack/
   ├── create-iso.sh              # ISO generation
   ├── deploy-on-kvm.sh           # VM deployment
   ├── watch-and-reboot-kvm-vms.sh # VM monitoring
   ├── configure_dns_entries.sh    # DNS configuration
   └── deploy-freeipa.sh          # Identity management
   ```

## Implementation

### System Dependencies
Required packages and tools:
- nmstate
- ansible-core
- bind-utils
- libguestfs
- cloud-init
- virt-install
- qemu-img
- virt-manager
- podman
- OpenShift CLI tools

### Test Framework Components

1. **Environment Setup (bootstrap_env.sh)**
   - System package installation
   - Ansible collection setup
   - OpenShift CLI tools installation
   - Container runtime configuration
   - SELinux configuration
   - Infrastructure setup
   - Registry authentication

2. **Environment Validation (validate_env.sh)**
   - System requirements verification
   - Network configuration validation
   - Required tools availability
   - Infrastructure service status

3. **Test Execution (run_e2e.sh)**
   - Site configuration validation
   - ISO creation and validation
   - VM deployment and monitoring
   - Installation progress tracking
   - Test case execution
   - Results collection

4. **Environment Cleanup (delete_e2e.sh)**
   - VM cleanup
   - Network configuration cleanup
   - Resource removal
   - Environment restoration

### Test Flow

1. **Pre-execution Setup**
   ```bash
   # Bootstrap environment
   ./e2e-tests/bootstrap_env.sh

   # Validate environment
   ./e2e-tests/validate_env.sh
   ```

2. **Test Execution**
   ```bash
   # Run end-to-end tests with site config
   ./e2e-tests/run_e2e.sh <site_config_dir>
   ```

3. **Cleanup**
   ```bash
   # Clean up test environment
   ./e2e-tests/delete_e2e.sh
   ```

## Consequences

### Positive
1. Automated end-to-end testing
2. Consistent test environments
3. Comprehensive validation
4. Infrastructure management
5. Clear error reporting
6. Support for different deployment scenarios

### Negative
1. Complex setup requirements
2. Resource-intensive testing
3. External dependencies
4. Platform-specific considerations

## Test Coverage

### Installation Scenarios
1. Connected installations
2. Disconnected installations
3. Single-node deployments
4. Multi-node clusters

### Infrastructure Testing
1. Network configuration
2. Storage setup
3. DNS management
4. Identity integration

### Validation Testing
1. Environment prerequisites
2. Tool availability
3. Resource requirements
4. Configuration validation

## Related ADRs
- [ADR-013: End-to-End Testing Framework](0013-end-to-end-testing-framework)
- [ADR-007: Virtual Infrastructure Testing](0007-virtual-infrastructure-testing)
- [ADR-009: Testing Infrastructure and ISO Management](0009-testing-infrastructure-and-iso-management)

## Related
- [Installation Guide](../installation-guide)
- [Configuration Guide](../configuration-guide)
- [Network Configuration](../network-configuration)
- [Example Configurations](../../examples/)
