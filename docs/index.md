---
layout: default
title: Home
nav_order: 1
description: "OpenShift Agent-Based Installer Documentation"
permalink: /
---

# OpenShift Agent-Based Installer

Automated deployment tooling for OpenShift clusters using the Agent-Based Installer (ABI). Supports SNO, 3-node compact, and HA cluster deployments on bare metal, vSphere, and KVM.

**Primary workflow**: Development (KVM) → Fork & Adapt → Production (Bare Metal)

---

## Find What You Need

This documentation follows the [Diataxis framework](https://diataxis.fr/). Choose based on what you are trying to do:

| | I want to... | Go to |
|-|-------------|-------|
| **Learn** | Work through a deployment from scratch to gain experience | [Tutorials](tutorials) |
| **Do** | Accomplish a specific task I already understand | [How-to Guides](how-to-guides) |
| **Look up** | Find a specific parameter, version requirement, or example | [Reference](reference) |
| **Understand** | Learn why things work the way they do | [Explanation](explanation) |

---

## Quick Start

**New to this repository?** Start with the [Developer Guide](developer-guide.md) to set up a KVM development environment, then work through the [Installation Guide](installation-guide.md) to deploy your first cluster.

**Ready for production?** Use the [Fork & Adapt Checklist](fork-and-adapt-checklist.md) to migrate your validated KVM configuration to physical bare metal, then follow the [Bare Metal Production Guide](bare-metal-production-guide.md).

```bash
# 1. Validate your environment
./e2e-tests/validate_env.sh

# 2. Generate cluster ISO
./hack/create-iso.sh <cluster-config-name>

# 3. Deploy (KVM)
./hack/deploy-connected-full.sh examples/<cluster-config-name>

# 4. Monitor installation
./bin/openshift-install agent wait-for install-complete \
  --dir ~/generated_assets/<cluster-name>/
```

---

## KVM vs Bare Metal

| Aspect | KVM Development | Bare Metal Production |
|--------|-----------------|----------------------|
| Networking | VyOS VLAN networks | Physical switch VLANs |
| MAC Addresses | Generated | Real hardware MACs |
| BMC | sushy Redfish emulator | Real iDRAC / iLO / IPMI |
| DNS | dnsmasq / libvirt | Corporate DNS (BIND / Infoblox / AD) |
| Storage | qcow2 virtual disks | Physical disks (NVMe / SAS) |
| ISO delivery | `deploy-on-kvm.sh` (automated) | Virtual media / USB / PXE |

---

## Version-Specific Standards

| OpenShift Version | Standards |
|------------------|-----------|
| 4.21 | [Deployment Standards 4.21](deployment-standards-4.21.md) — OVNKubernetes mandatory |
| 4.20 | [Deployment Standards 4.20](deployment-standards-4.20.md) — ImageDigestMirrorSet required |
| 4.19 | [Deployment Standards 4.19](deployment-standards-4.19.md) — ImageContentSourcePolicy |

See the [Version Compatibility Matrix](version-compatibility-matrix.md) for full API change history.

---

## Additional Resources

- [README](https://github.com/tosin2013/openshift-agent-install#readme) — Repository overview and quick start
- [llm.txt](https://github.com/tosin2013/openshift-agent-install/blob/main/llm.txt) — Comprehensive reference for AI assistants
- [CONTRIBUTING.md](https://github.com/tosin2013/openshift-agent-install/blob/main/CONTRIBUTING.md) — How to contribute
- [GitHub Issues](https://github.com/tosin2013/openshift-agent-install/issues) — Bug reports and feature requests
