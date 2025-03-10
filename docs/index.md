---
layout: default
title: OpenShift Agent Install Helper
description: Documentation for OpenShift Agent-based Installer Helper utilities
---

# OpenShift Agent Install Helper

Welcome to the OpenShift Agent Install Helper documentation. This project provides utilities and automation to simplify OpenShift Agent-based installations across various environments.

## Overview

The OpenShift Agent Install Helper provides automation and configuration management to simplify the usage of the [OpenShift Agent-based Installer](https://docs.openshift.com/container-platform/latest/installing/installing_with_agent_based_installer/preparing-to-install-with-agent-based-installer.html). It supports:

- Bare metal installations
- VMware vSphere deployments
- Platform-agnostic (none) deployments
- Single-Node OpenShift (SNO)
- Three-node compact clusters
- Standard HA configurations

### Key Components

- Ansible playbooks for manifest generation (`playbooks/`)
- ISO creation utilities (`get-rhcos-iso.sh`)
- Network configuration templates (`examples/`)
- BMC management tools (`scripts/`)
- Validation scripts (`e2e-tests/`)
- Example configurations (`examples/`)

### Prerequisites

- RHEL/CentOS system for installation host
- OpenShift CLI Tools (`./download-openshift-cli.sh`)
- NMState CLI (`dnf install nmstate`)
- Ansible Core (`dnf install ansible-core`)
- Red Hat OpenShift Pull Secret
- Additional pull secrets for disconnected registries (if needed)

## Supported Architectures

| CPU Architecture | Connected Installation | Disconnected Installation |
|-----------------|:---------------------:|:------------------------:|
| x86_64          | ✓ | ✓ |
| ARM64           | ✓ | ✓ |
| ppc64le         | ✓ | ✓ |
| s390x           | ✓ | ✓ |

## Key Features

- Flexible server boot options
- Offline installation support
- Air-gapped environment support
- Multiple platform support (baremetal, vsphere, none)
- FIPS compliance capabilities
- Static and DHCP networking support
- Advanced networking configurations (bonds, VLANs, SR-IOV)

## Documentation Structure

### Getting Started
- [Installation Guide](installation-guide)
- [Configuration Guide](configuration-guide)
- [Contributing Guide](contributing)
- [Architecture Decisions](adr/)

### Installation and Configuration
- [Installation Guide](installation-guide)
- [Configuration Guide](configuration-guide)
- [Disconnected Installation](disconnected-installation)
- [Identity Management](identity-management)

### Networking and Infrastructure
- [Network Configuration Guide](network-configuration)
- [Advanced Networking](advanced-networking)
- [BMC Management](bmc-management)
- [Infrastructure Setup](infrastructure-setup)

### Testing and Validation
- [Testing Guide](testing-guide)
- [End-to-End Testing](e2e-testing)
- [Environment Validation](environment-validation)
- [Troubleshooting Guide](troubleshooting)

### Reference Architecture
- [Deployment Patterns](deployment-patterns)
- [Reference Configurations](reference-configurations)
- [Platform Guides](platform-guides)

### Architecture and Design
- [Architectural Decisions](adr/)
  - [Agent-based Installation Approach](adr/0001-agent-based-installation-approach)
  - [Advanced Networking](adr/0002-advanced-networking-configurations)
  - [Ansible Automation](adr/0003-ansible-automation-approach)
  - [Disconnected Support](adr/0004-disconnected-installation-support)
  - [Asset Management](adr/0005-iso-creation-and-asset-management)
  - [Testing Framework](adr/0006-testing-and-execution-environment)
  - [Infrastructure Testing](adr/0007-virtual-infrastructure-testing)
  - [BMC Management](adr/0008-bmc-management-and-automation)
  - [Testing Infrastructure](adr/0009-testing-infrastructure-and-iso-management)
  - [Manifest Generation](adr/0010-manifest-generation-and-templating)
  - [Identity Integration](adr/0011-identity-management-integration)
  - [Deployment Patterns](adr/0012-deployment-patterns-and-configurations)
  - [E2E Testing Framework](adr/0013-end-to-end-testing-framework)

## Deployment Types

### Single-node OpenShift (SNO)
- One node acting as both master and worker
- Minimum Requirements:
  - 8 vCPUs
  - 16 GB RAM
  - 120 GB Storage
- [SNO Configuration Guide](deployment-patterns#single-node-openshift)
- [SNO Examples]({{ site.examples_repo }}/sno-bond0-signal-vlan)

### Three-node Compact Cluster
- Three master nodes that are also worker nodes
- Minimum Requirements per Node:
  - 8 vCPUs
  - 16 GB RAM
  - 120 GB Storage
- [Compact Cluster Guide](deployment-patterns#compact-cluster)
- [Example Configurations]({{ site.examples_repo }}/bond0-single-bond0-vlan)

### Standard HA Cluster
- Three master nodes
- Two or more worker nodes
- Minimum Requirements per Node:
  - 8 vCPUs
  - 16 GB RAM
  - 120 GB Storage
- [HA Cluster Guide](deployment-patterns#ha-cluster)
- [Example Configurations]({{ site.examples_repo }}/baremetal-example)

## Platform Support

### Bare Metal
- [Bare Metal Guide](platform-guides#bare-metal)
- [Example Configurations]({{ site.examples_repo }}/baremetal-example)
- [BMC Management Guide](bmc-management)

### VMware
- [VMware Guide](platform-guides#vmware)
- [Example Configurations]({{ site.examples_repo }}/vmware-example)
- [Disconnected VMware Guide]({{ site.examples_repo }}/vmware-disconnected-example)

### Network Configuration
- [Basic Networking](network-configuration#basic)
- [Advanced Networking](network-configuration#advanced)
  - Bond Configuration
  - VLAN Setup
  - SR-IOV Support
- [Example Configurations]({{ site.examples_repo }}/bond0-single-bond0-vlan)

## Testing and Validation
- [Testing Framework Overview](testing-guide)
- [End-to-End Testing](e2e-testing)
- [Environment Validation](environment-validation)
- [Troubleshooting Guide](troubleshooting)

## Example Configurations
Browse our example configurations for common deployment scenarios in the `examples/` directory:
- Bare Metal Examples
- VMware Examples
- SNO Examples
- Network Bonding Examples
- Stretched Cluster Examples

## Utility Scripts
- `get-rhcos-iso.sh`: Download RHCOS ISO images
- `download-openshift-cli.sh`: Download OpenShift CLI tools
- Additional scripts in `scripts/` and `hack/` directories

## Testing
- End-to-end tests in `e2e-tests/`
- Execution environment setup in `execution-environment/`
- Example configurations in `examples/`

## Disconnected Installation
For disconnected installation guidance, refer to `disconnected-info.md` in the repository root.

For more detailed information, visit the [official OpenShift documentation](https://docs.redhat.com/).

## Authors

This project is maintained by:

- Ken Moini: [https://github.com/kenmoini](https://github.com/kenmoini)
- Tosin Akinosho: [https://github.com/tosin2013](https://github.com/tosin2013)

---
*Note: This documentation is regularly updated to reflect the latest features and improvements in OpenShift Agent Install.*
