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

For disconnected environments, see our [Disconnected Installation Guide](disconnected-installation.md) and the [OpenShift 4 Disconnected Helper](https://github.com/tosin2013/ocp4-disconnected-helper).

## Hardware Requirements

### Minimum Specifications
See [OpenShift Hardware Requirements](https://docs.openshift.com/container-platform/4.17/installing/installing_bare_metal/installing-bare-metal-agent-based.html#installation-requirements-agent-based_installing-bare-metal-agent-based) and our `examples/` directory for specific configuration examples for different deployment types.

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
Our validation scripts in `e2e-tests/` help verify these settings. For vendor-specific guidance, see:
- [Dell PowerEdge BIOS Configuration](https://www.dell.com/support/kbdoc/en-us/000176874/dell-poweredge-bios-settings)
- [HPE UEFI Configuration](https://support.hpe.com/hpesc/public/docDisplay?docId=a00114942en_us)
- [Lenovo UEFI Setup](https://thinksystem.lenovofiles.com/help/index.jsp?topic=%2F7X06%2Fuefi_settings.html)

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
Use our example configurations in `examples/` for reference implementations. For detailed networking requirements, see [OpenShift Networking Requirements](https://docs.openshift.com/container-platform/4.17/installing/installing_bare_metal/installing-bare-metal-agent-based.html#installation-network-requirements_installing-bare-metal-agent-based).

1. Management Network (BMC/IPMI Access)
2. Cluster Network (OpenShift Communication)
3. Application Network (Workload Traffic)

### Network Setup Tools
- Network configuration templates in `examples/`
- [NMState Configuration Guide](https://nmstate.io/examples.html)
- Validation scripts in `e2e-tests/`
- [OpenShift Network Operator](https://docs.openshift.com/container-platform/4.17/networking/cluster-network-operator.html)

## Storage Configuration

### Local Storage
Refer to example configurations in `examples/` directory and [OpenShift Storage Documentation](https://docs.openshift.com/container-platform/4.17/storage/understanding-persistent-storage.html).

### Shared Storage (Optional)
Examples and configurations available in `examples/` directory. For supported storage options, see:
- [Red Hat OpenShift Data Foundation](https://access.redhat.com/documentation/en-us/red_hat_openshift_data_foundation/4.12)
- [OpenShift Container Storage](https://access.redhat.com/documentation/en-us/red_hat_openshift_container_storage/4.8)

## BMC Setup

### Supported Management
For detailed BMC configuration, see our [BMC Management Guide](bmc-management.md) and:
- [IPMI Specification](https://www.intel.com/content/www/us/en/products/docs/servers/ipmi/ipmi-second-gen-interface-spec-v2-rev1-1.html)
- [Redfish API](https://www.dmtf.org/standards/redfish)
- [Dell iDRAC Guide](https://www.dell.com/support/kbdoc/en-us/000178115/idrac9-versions-and-features)
- [HPE iLO Guide](https://support.hpe.com/hpesc/public/docDisplay?docId=a00018324en_us)
- [Lenovo XCC Guide](https://sysmgt.lenovofiles.com/help/topic/com.lenovo.systems.management.xcc.doc/dw1lm_c_chapter1_introduction.html)

### BMC Management Tools
- Scripts available in `scripts/` directory
- Playbooks for automation in `playbooks/`
- Example configurations in `examples/`
- [OpenShift 4 Disconnected Helper](https://github.com/tosin2013/ocp4-disconnected-helper)

## Platform-specific Requirements

### Bare Metal
Use our automation tools and see [OpenShift Bare Metal Installation](https://docs.openshift.com/container-platform/4.17/installing/installing_bare_metal/installing-bare-metal-agent-based.html):
- ISO creation: `get-rhcos-iso.sh`
- OpenShift CLI setup: `download-openshift-cli.sh`
- Example configurations in `examples/`

### VMware
Reference our VMware-specific examples in `examples/` directory and [VMware vSphere Installation](https://docs.openshift.com/container-platform/4.17/installing/installing_vsphere/preparing-to-install-on-vsphere.html).

## Registry Setup

For container registry setup, see our [Disconnected Installation Guide](disconnected-installation.md) and:
- [Red Hat Quay](https://access.redhat.com/documentation/en-us/red_hat_quay/3.10)
- [Harbor Registry](https://goharbor.io/)
- [JFrog Artifactory](https://jfrog.com/artifactory/)

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

## Related Documentation

### Internal References
- [Disconnected Installation Guide](disconnected-installation.md)
- [BMC Management Guide](bmc-management.md)
- [Network Configuration Guide](network-configuration.md)
- [Storage Configuration Guide](storage-configuration.md)

### External References
- [OpenShift 4.17 Documentation](https://docs.openshift.com/container-platform/4.17/welcome/index.html)
- [Red Hat Enterprise Linux 9 Documentation](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9)
- [OpenShift Life Cycle and Support](https://access.redhat.com/support/policy/updates/openshift)
- [OpenShift Sizing and Subscription Guide](https://access.redhat.com/documentation/en-us/openshift_container_platform/4.17/html/scalability_and_performance/recommended-host-practices_recommended-host-practices)

### Tools and Utilities
- [OpenShift 4 Disconnected Helper](https://github.com/tosin2013/ocp4-disconnected-helper)
- [OpenShift Agent-based Installer](https://docs.openshift.com/container-platform/4.17/installing/installing_with_agent_based_installer/preparing-to-install-with-agent-based-installer.html)
- [NMState Network Configuration](https://nmstate.io/)
- [RHCOS (Red Hat CoreOS)](https://docs.openshift.com/container-platform/4.17/architecture/architecture-rhcos.html) 