---
layout: default
title: End-to-End Testing Guide
description: Comprehensive guide for running end-to-end tests with the OpenShift Agent Install Helper
---

# End-to-End Testing Guide

This guide provides detailed instructions for running end-to-end tests using the OpenShift Agent Install Helper testing framework.

## Overview

The end-to-end testing framework validates complete OpenShift installations from start to finish, including:
- Environment setup and validation
- ISO creation and customization
- VM deployment and configuration
- OpenShift installation
- Post-installation validation

## Prerequisites

1. **System Requirements**
   - RHEL/CentOS system
   - Minimum 32GB RAM
   - 500GB available storage
   - Internet connectivity (for connected tests)

2. **Required Packages**
   ```bash
   # Core packages
   - libvirt
   - qemu-kvm
   - virt-manager
   - ansible-core
   - nmstate
   - bind-utils
   ```

## Test Structure

### 1. Test Scripts
```bash
e2e-tests/
├── bootstrap_env.sh    # Environment setup
├── validate_env.sh     # Validation
├── run_e2e.sh         # Test execution
└── delete_e2e.sh      # Cleanup
```

### 2. Support Scripts
```bash
hack/
├── create-iso.sh              # ISO creation
├── deploy-on-kvm.sh           # VM deployment
├── watch-and-reboot-kvm-vms.sh # VM monitoring
└── configure_dns_entries.sh    # DNS setup
```

## Running Tests

### 1. Environment Setup
```bash
# Bootstrap the environment
./e2e-tests/bootstrap_env.sh

# Validate setup
./e2e-tests/validate_env.sh
```

### 2. Test Execution
```bash
# Run tests with a specific configuration
./e2e-tests/run_e2e.sh examples/sno-bond0-signal-vlan

# Monitor progress
tail -f /var/log/messages
```

### 3. Cleanup
```bash
# Clean up after tests
./e2e-tests/delete_e2e.sh
```

## Test Scenarios

### 1. Single-Node OpenShift (SNO)
```bash
# Run SNO test
./e2e-tests/run_e2e.sh examples/sno-bond0-signal-vlan
```

### 2. Three-Node Compact Cluster
```bash
# Run compact cluster test
./e2e-tests/run_e2e.sh examples/compact-cluster
```

### 3. Standard HA Cluster
```bash
# Run HA cluster test
./e2e-tests/run_e2e.sh examples/baremetal-example
```

## Test Flow Details

### 1. Environment Preparation
- System package installation
- Tool configuration
- Network setup
- Service initialization

### 2. ISO Creation
- Configuration validation
- ISO generation
- Customization application
- Validation checks

### 3. Infrastructure Setup
- VM creation
- Network configuration
- DNS setup
- Storage allocation

### 4. Installation Process
- Node boot
- Discovery phase
- Installation phase
- Configuration application

### 5. Validation
- Node status
- Cluster operators
- Network connectivity
- Storage configuration

## Monitoring and Debugging

### 1. Installation Progress
```bash
# Monitor VM status
./hack/watch-and-reboot-kvm-vms.sh examples/cluster/nodes.yml

# Check DNS entries
./hack/configure_dns_entries.sh examples/cluster
```

### 2. Log Collection
```bash
# Collect VM logs
virsh console vm_name

# Monitor system logs
journalctl -f
```

## Common Issues and Solutions

### 1. VM Deployment Issues
- Check libvirt service status
- Verify network configuration
- Ensure sufficient resources

### 2. Network Problems
- Validate DNS configuration
- Check network connectivity
- Verify VLAN setup

### 3. Installation Failures
- Review installation logs
- Check resource availability
- Verify configurations

## Best Practices

1. **Test Environment**
   - Use clean environment for each test
   - Validate prerequisites
   - Monitor resource usage

2. **Test Execution**
   - Follow standard procedures
   - Document deviations
   - Save test artifacts

3. **Problem Resolution**
   - Collect relevant logs
   - Document issues
   - Track resolutions

## Related Documentation
- [Testing Framework Overview](testing-guide)
- [Environment Validation](environment-validation)
- [Troubleshooting Guide](troubleshooting)
- [ADR-013: End-to-End Testing Framework](adr/0013-end-to-end-testing-framework)
- [ADR-006: Testing and Execution Environment](adr/0006-testing-and-execution-environment)
