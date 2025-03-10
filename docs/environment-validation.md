---
layout: default
title: Environment Validation Guide
description: Guide for validating the OpenShift Agent Install Helper environment
---

# Environment Validation Guide

This guide covers the environment validation process for the OpenShift Agent Install Helper, ensuring all prerequisites and configurations are correctly set up.

## Overview

Environment validation is a critical step that:
- Verifies system requirements
- Checks required packages
- Validates configurations
- Ensures service availability
- Confirms network setup

## Validation Components

### 1. System Requirements
```bash
# Minimum requirements
- CPU: 8+ cores
- RAM: 32+ GB
- Storage: 500+ GB
- Network: 1+ GbE
```

### 2. Required Packages
```bash
# Core packages
- nmstate
- ansible-core
- bind-utils
- libguestfs
- cloud-init
- virt-install
- qemu-img
- virt-manager
- podman
```

### 3. OpenShift Tools
```bash
# Required tools
- OpenShift CLI (oc)
- OpenShift Installer
- NMState CLI
```

## Validation Process

### 1. Running Validation
```bash
# Execute validation script
./e2e-tests/validate_env.sh
```

### 2. Validation Steps
1. **System Validation**
   - OS version check
   - Resource verification
   - Package validation
   - Service status

2. **Tool Validation**
   - CLI availability
   - Version compatibility
   - Configuration check
   - Permission verification

3. **Network Validation**
   - Connectivity check
   - DNS resolution
   - Network interface status
   - VLAN availability

4. **Infrastructure Validation**
   - Virtualization support
   - Storage configuration
   - Service availability
   - Security settings

## Validation Results

### 1. Success Indicators
```bash
# Example successful validation
✓ Operating system requirements met
✓ Required packages installed
✓ OpenShift tools available
✓ Network configuration valid
✓ Infrastructure services running
```

### 2. Error Messages
```bash
# Example error messages
✗ Missing required package: nmstate
✗ Insufficient system memory
✗ Network interface not found
✗ Service not running: libvirtd
```

## Common Issues

### 1. System Requirements
- Insufficient resources
- Unsupported OS version
- Missing packages
- Permission issues

### 2. Network Configuration
- DNS resolution failures
- Interface configuration errors
- VLAN setup issues
- Connectivity problems

### 3. Service Issues
- Service not running
- Configuration errors
- Permission problems
- Resource conflicts

## Resolution Steps

### 1. Package Issues
```bash
# Install missing packages
sudo dnf install -y nmstate ansible-core bind-utils

# Verify installation
rpm -q package_name
```

### 2. Network Problems
```bash
# Check DNS resolution
dig +short api.cluster.domain

# Verify network interface
nmcli device show

# Test connectivity
ping -c 4 gateway_ip
```

### 3. Service Problems
```bash
# Check service status
systemctl status service_name

# Start service
sudo systemctl start service_name

# Enable service
sudo systemctl enable service_name
```

## Best Practices

### 1. Pre-validation
- Update system packages
- Clear temporary files
- Check resource usage
- Verify configurations

### 2. During Validation
- Monitor system logs
- Track resource usage
- Document issues
- Save error messages

### 3. Post-validation
- Review validation results
- Address any issues
- Document changes
- Update configurations

## Troubleshooting

### 1. Validation Failures
1. Check system logs
2. Verify requirements
3. Review configurations
4. Test components

### 2. Resource Issues
1. Monitor usage
2. Free resources
3. Adjust limits
4. Optimize configuration

### 3. Configuration Problems
1. Review settings
2. Check syntax
3. Verify permissions
4. Test changes

## Related Documentation
- [Testing Framework Overview](testing-guide)
- [End-to-End Testing](e2e-testing)
- [Troubleshooting Guide](troubleshooting)
- [ADR-013: End-to-End Testing Framework](adr/0013-end-to-end-testing-framework)
- [ADR-006: Testing and Execution Environment](adr/0006-testing-and-execution-environment)
- [ADR-007: Virtual Infrastructure Testing](adr/0007-virtual-infrastructure-testing) 