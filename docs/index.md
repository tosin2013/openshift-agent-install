---
layout: default
title: Home
nav_order: 1
description: "OpenShift Agent-Based Installer Documentation"
permalink: /
---

# OpenShift Agent-Based Installer Documentation

## 🎯 Start Here

**New to this repository?**
- 📘 [Developer Guide](developer-guide.md) - KVM development environment setup and fork workflow
- 📖 [Installation Guide](installation-guide.md) - Step-by-step deployment walkthrough

**Development Workflow**: KVM Development → Fork Repository → Bare Metal Production

---

## Documentation Organization (Diataxis Framework)

This documentation follows the [Diataxis framework](https://diataxis.fr/) for technical documentation:

### 📚 Tutorials (Learning-Oriented)

**Goal**: Learn by doing - complete a specific task from start to finish

- [Installation Guide](installation-guide.md) - Deploy your first cluster on KVM
- [Disconnected Installation](disconnected-installation.md) - Air-gapped deployment tutorial
- [E2E Testing Guide](e2e-testing.md) - Automated testing walkthrough

**When to use**: You're new to OpenShift Agent-Based Installer and want hands-on experience

### 📖 How-To Guides (Problem-Oriented)

**Goal**: Solve a specific problem - achieve a particular outcome

- [Developer Guide](developer-guide.md) - Set up KVM development environment
- [DNS Setup](dns-setup.md) - Configure DNS for clusters
- [HAProxy Forwarder Guide](haproxy-forwarder-guide.md) - External access configuration
- [BMC Management](bmc-management.md) - IPMI/Redfish configuration
- [Network Configuration](network-configuration.md) - VLANs, bonds, static IPs
- [Identity Management](identity-management.md) - LDAP/AD integration

**When to use**: You have a specific task and need to know how to accomplish it

### 📋 Reference (Information-Oriented)

**Goal**: Find factual information - look up configuration options

- [Configuration Guide](configuration-guide.md) - All cluster.yml and nodes.yml parameters
- [Platform Guides](platform-guides.md) - Platform-specific settings
- [Reference Configurations](reference-configurations.md) - Example configurations catalog
- [Version Compatibility Matrix](version-compatibility-matrix.md) - OpenShift version support
- [Deployment Standards (4.19)](deployment-standards-4.19.md) - Version-specific requirements
- [Deployment Standards (4.20)](deployment-standards-4.20.md) - Version-specific requirements
- [Deployment Standards (4.21)](deployment-standards-4.21.md) - Version-specific requirements

**When to use**: You need to look up a specific configuration parameter or requirement

### 💡 Explanation (Understanding-Oriented)

**Goal**: Understand concepts - gain deeper knowledge

- [Deployment Patterns](deployment-patterns.md) - SNO vs 3-Node vs HA architectures
- [Advanced Networking](advanced-networking.md) - Network architecture deep dive
- [Infrastructure Setup](infrastructure-setup.md) - Foundation concepts
- [Testing Guide](testing-guide.md) - Testing philosophy and strategies
- [Environment Validation](environment-validation.md) - Why validation matters

**When to use**: You want to understand why things work the way they do

---

## Quick Navigation by Role

### 👨‍💻 For Developers

**Setting up local development**:
1. [Developer Guide](developer-guide.md) - KVM environment setup
2. [Installation Guide](installation-guide.md) - Deploy first cluster
3. [E2E Testing](e2e-testing.md) - Automated testing

**Prerequisites**:
- VyOS router (mandatory for KVM)
- Cockpit web interface
- Libvirt/KVM infrastructure

### 🏢 For Organizations

**Adapting for production**:
1. [Developer Guide - Forking Workflow](developer-guide.md#adapting-for-your-organization)
2. [Deployment Patterns](deployment-patterns.md) - Choose architecture
3. [HAProxy Forwarder Guide](haproxy-forwarder-guide.md) - External access

**From KVM to Bare Metal**:
- Test configurations on KVM
- Fork repository for customization
- Adapt for bare metal infrastructure
- Apply security hardening

### 🔧 For Operations

**Day 2 operations**:
1. [BMC Management](bmc-management.md) - Hardware control
2. [Network Configuration](network-configuration.md) - Network troubleshooting
3. [Troubleshooting](troubleshooting.md) - Common issues

### 🚀 For CI/CD

**Automated deployments**:
1. [E2E Testing Guide](e2e-testing.md) - Automated validation
2. [Testing Guide](testing-guide.md) - Test strategies
3. [Version Validation](version-validation-quick-start.md) - Multi-version testing

---

## Key Concepts

### Development vs Production

| Aspect | KVM Development | Bare Metal Production |
|--------|-----------------|----------------------|
| **Networking** | VyOS VLAN networks | Physical switch VLANs |
| **MAC Addresses** | Generated | Real hardware MACs |
| **IPMI/BMC** | Redfish mock | Real IPMI/iDRAC/iLO |
| **DNS** | dnsmasq or VyOS | Corporate DNS server |
| **Storage** | qcow2 virtual disks | Physical disks |
| **Purpose** | Testing, validation | Production workloads |

See: [Developer Guide](developer-guide.md) for complete comparison

### Hard Requirements for KVM Development

1. **VyOS Router** - Provides VLAN networking (networks 1924-1928)
   - Manual configuration required via Cockpit console
   - See: [Developer Guide - VyOS Router Setup](developer-guide.md#hard-requirement-vyos-router)

2. **Cockpit Web Interface** - VM management and console access
   - Access at: `https://<host>:9090`
   - Required for VyOS router configuration
   - See: [Developer Guide - Cockpit](developer-guide.md#cockpit-web-interface)

3. **Libvirt/KVM** - Virtualization infrastructure
   - Standard KVM/libvirt installation
   - See: [Developer Guide - Prerequisites](developer-guide.md#prerequisites)

### HAProxy External Access

Two deployment modes:

**Development (example.com)**:
- Local KVM testing
- IP-based access
- Simple configuration

**Production (AWS/Corporate)**:
- Elastic IP + Route53 DNS
- SSL/TLS certificates
- Corporate domain integration

See: [HAProxy Forwarder Guide](haproxy-forwarder-guide.md)

---

## Version-Specific Documentation

### OpenShift 4.19
- [Deployment Standards 4.19](deployment-standards-4.19.md)
- ImageContentSourcePolicy (deprecated)
- OpenShiftSDN supported

### OpenShift 4.20
- [Deployment Standards 4.20](deployment-standards-4.20.md)
- **ImageDigestMirrorSet** (new API for disconnected)
- OpenShiftSDN deprecated (warning only)

### OpenShift 4.21
- [Deployment Standards 4.21](deployment-standards-4.21.md)
- **OVNKubernetes mandatory** (OpenShiftSDN removed)
- UpdateService for disconnected clusters

See: [Version Compatibility Matrix](version-compatibility-matrix.md)

---

## Common Workflows

### 1. First-Time Setup (Developer)

Steps:
1. Fork repository: [Developer Guide - Fork Workflow](developer-guide.md#fork-and-customize-workflow)
2. Setup KVM: [Developer Guide - Prerequisites](developer-guide.md#prerequisites)
3. Deploy VyOS: [Developer Guide - VyOS Setup](developer-guide.md#vyos-router-setup)
4. Deploy cluster: [Installation Guide](installation-guide.md)

### 2. Multi-Version Testing

```bash
# Generate manifests for versions 4.19, 4.20, 4.21
./hack/generate-version-manifests.sh sno-disconnected "4.19 4.20 4.21"

# Validate against version-specific standards
./hack/validate-deployment-standards.sh \
  ~/generated_assets/version-compare/sno-disconnected-4.20 4.20

# Compare critical boundaries
./hack/compare-version-manifests.sh 4.19 4.20 sno-disconnected
```

See: [Version Validation Quick Start](version-validation-quick-start.md)

### 3. Production Deployment Preparation

Steps:
1. Test on KVM: [Installation Guide](installation-guide.md)
2. Customize: [Developer Guide - Adapting](developer-guide.md#adapting-for-your-organization)
3. Security: [Deployment Patterns - Security](deployment-patterns.md#security-considerations)
4. Deploy: [Infrastructure Setup](infrastructure-setup.md)

---

## Additional Resources

### External Documentation
- [VyOS Router Configuration](https://github.com/tosin2013/demo-virt/blob/rhpds/demo.redhat.com/docs/step1.md)
- [OpenShift Forwarder Repository](https://github.com/tosin2013/openshift-forwarder)
- [Cockpit Project Documentation](https://cockpit-project.org/documentation.html)

### Repository Files
- [README.md](../README.md) - Repository overview
- [CONTRIBUTING.md](../CONTRIBUTING.md) - Contribution guidelines
- [CHANGELOG.md](../CHANGELOG.md) - Release history
- [TODO.md](../TODO.md) - Current development tasks

### LLM-Friendly References
- [llm.txt](../llm.txt) - Comprehensive guide for AI assistants
- [CLAUDE.md](../CLAUDE.md) - Claude Code instructions

---

## Contributing

Found an issue? Want to contribute?

See: [CONTRIBUTING.md](../CONTRIBUTING.md)

---

## Support

- **Issues**: [GitHub Issues](https://github.com/tosin2013/openshift-agent-install/issues)
- **Discussions**: [GitHub Discussions](https://github.com/tosin2013/openshift-agent-install/discussions)
- **Troubleshooting**: [Troubleshooting Guide](troubleshooting.md)
