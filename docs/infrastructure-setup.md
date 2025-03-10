---
layout: default
title: Infrastructure Setup
description: Guide for setting up infrastructure for OpenShift Agent-based installations using this helper utility
---

# Infrastructure Setup Guide

This guide covers the infrastructure setup requirements and procedures for OpenShift Agent-based installations using this helper utility.

## Overview

Proper infrastructure setup is crucial for a successful OpenShift deployment. This guide covers:
- Hardware Requirements
- Network Infrastructure
- Storage Configuration
- BMC Setup
- Platform-specific Requirements

## Hardware Requirements

### Minimum Specifications
See `examples/` directory for specific configuration examples for different deployment types.

#### Control Plane Nodes
- CPU: 8 cores
- RAM: 32 GB
- Storage: 120 GB
- Network: 2x 10 GbE NICs (recommended)

#### Worker Nodes
- CPU: 8 cores
- RAM: 16 GB
- Storage: 120 GB
- Network: 2x 10 GbE NICs (recommended)

### BIOS/UEFI Configuration
Our validation scripts in `e2e-tests/` help verify these settings:

```yaml
BIOS Settings:
  - Virtualization Technology: Enabled
  - Intel VT-d/AMD IOMMU: Enabled
  - Power Management: Maximum Performance
  - CPU Power and Performance: Maximum Performance
  - C-States: Disabled
  - Secure Boot: Optional (Required for FIPS)
```

## Network Infrastructure

### Network Configuration
Use our example configurations in `examples/` for reference implementations:

1. Management Network (BMC/IPMI Access)
2. Cluster Network (OpenShift Communication)
3. Application Network (Workload Traffic)

### Network Setup Tools
- Network configuration templates in `examples/`
- NMState configuration examples
- Validation scripts in `e2e-tests/`

## Storage Configuration

### Local Storage
Refer to example configurations in `examples/` directory for storage layouts.

### Shared Storage (Optional)
Examples and configurations available in `examples/` directory.

## BMC Setup

### Supported Management
- IPMI
- Redfish
- iDRAC
- iLO
- XCC

### BMC Management Tools
- Scripts available in `scripts/` directory
- Playbooks for automation in `playbooks/`
- Example configurations in `examples/`

## Platform-specific Requirements

### Bare Metal
Use our automation tools:
- ISO creation: `get-rhcos-iso.sh`
- OpenShift CLI setup: `download-openshift-cli.sh`
- Example configurations in `examples/`

### VMware
Reference our VMware-specific examples in `examples/` directory.

## Validation

### Automated Validation
Use our validation tools:
```bash
# From repository root
cd e2e-tests
./validate-environment.sh  # If available
```

### Manual Validation Steps
Scripts available in `scripts/` directory for:
- Network connectivity testing
- DNS resolution verification
- Load balancer testing
- BMC connectivity validation

## Related Repository Components
- `playbooks/`: Ansible playbooks for automation
- `scripts/`: Utility scripts
- `examples/`: Example configurations
- `e2e-tests/`: Validation tests
- `hack/`: Additional helper scripts
- `execution-environment/`: Testing environment setup

For disconnected installation guidance, refer to `disconnected-info.md` in the repository root. 