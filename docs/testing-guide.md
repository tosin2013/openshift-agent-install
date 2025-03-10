---
layout: default
title: Testing Framework Overview
description: Overview of the OpenShift Agent Install Helper Testing Framework
---

# Testing Framework Overview

The OpenShift Agent Install Helper includes a comprehensive testing framework designed to validate OpenShift installations across various environments and configurations. This guide provides an overview of the testing components and how to use them.

## Framework Components

### 1. Core Testing Scripts
```bash
e2e-tests/
├── bootstrap_env.sh    # Environment setup and dependencies
├── validate_env.sh     # Environment validation
├── run_e2e.sh         # Test orchestration
└── delete_e2e.sh      # Environment cleanup
```

### 2. Infrastructure Management
```bash
hack/
├── create-iso.sh              # ISO generation
├── deploy-on-kvm.sh           # VM deployment
├── watch-and-reboot-kvm-vms.sh # VM monitoring
├── configure_dns_entries.sh    # DNS configuration
└── deploy-freeipa.sh          # Identity management
```

## System Requirements

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

## Getting Started

1. **Environment Setup**
   ```bash
   # Bootstrap the environment
   ./e2e-tests/bootstrap_env.sh
   
   # Validate the environment
   ./e2e-tests/validate_env.sh
   ```

2. **Running Tests**
   ```bash
   # Execute end-to-end tests with a site configuration
   ./e2e-tests/run_e2e.sh <site_config_dir>
   ```

3. **Cleanup**
   ```bash
   # Clean up test environment
   ./e2e-tests/delete_e2e.sh
   ```

## Test Categories

### 1. Installation Testing
- Connected installations
- Disconnected installations
- Single-node deployments
- Multi-node clusters

### 2. Infrastructure Testing
- Network configuration
- Storage setup
- DNS management
- Identity integration

### 3. Validation Testing
- Environment prerequisites
- Tool availability
- Resource requirements
- Configuration validation

## Test Flow

1. **Environment Setup**
   - System package installation
   - Ansible collection setup
   - OpenShift CLI installation
   - Container tools configuration
   - SELinux setup
   - Infrastructure configuration
   - Registry authentication

2. **Environment Validation**
   - System requirements check
   - Network configuration validation
   - Required tools verification
   - Infrastructure service status

3. **Test Execution**
   - Site configuration validation
   - ISO creation
   - VM deployment
   - Installation monitoring
   - Test case execution
   - Results collection

4. **Cleanup**
   - VM cleanup
   - Network configuration cleanup
   - Resource removal
   - Environment restoration

## Key Features

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

## Best Practices

1. **Environment Setup**
   - Always run validation before tests
   - Keep system packages updated
   - Monitor resource usage
   - Maintain clean test environments

2. **Test Execution**
   - Use appropriate site configurations
   - Monitor test progress
   - Save test results
   - Document issues

3. **Resource Management**
   - Clean up after tests
   - Monitor disk space
   - Track resource usage
   - Maintain system health

## Related Documentation
- [End-to-End Testing](e2e-testing)
- [Environment Validation](environment-validation)
- [Troubleshooting Guide](troubleshooting)
- [ADR-013: End-to-End Testing Framework](adr/0013-end-to-end-testing-framework)
- [ADR-006: Testing and Execution Environment](adr/0006-testing-and-execution-environment)
- [ADR-007: Virtual Infrastructure Testing](adr/0007-virtual-infrastructure-testing)
- [ADR-009: Testing Infrastructure and ISO Management](adr/0009-testing-infrastructure-and-iso-management) 