# Changelog

All notable changes to the OpenShift Agent-Based Installer Helper project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html) aligned with OpenShift minor releases.

## [Unreleased]

### Planned for v4.21.0
- Deprecation remediation: Transition to ImageDigestMirrorSet for disconnected registries
- Version-aware validation: OVNKubernetes enforcement for OpenShift 4.21+
- Platform expansion: Nutanix and External platform support
- Topology expansion: Two-node cluster configurations (standard and HA with arbiter)
- Disconnected enhancements: Functional UpdateService manifest generation
- AI/ML readiness: ContainerRuntimeConfig for optimized storage (OpenShift 4.22+)
- RHACM integration: Hub cluster deployment target with Hive
- HyperShift support: Hosted control planes for edge deployments
- Developer experience: RHEL/CentOS bootstrap guide and jumpbox integration

## [4.20.0] - 2026-05-27

### OpenShift Compatibility
- **Tested OpenShift Versions**: 4.18 (EUS), 4.19, 4.20, 4.21
- **Current OpenShift Release**: 4.21 (GA: Feb 3, 2026)
- **Upcoming Release**: 4.22 (GA: ~Jun 2026)
- **Deprecated Versions**: 4.17 and earlier (EOL April 2026)

### OpenShift Lifecycle Status (as of May 2026)
- **4.21**: Current (GA Feb 3, 2026) - Full support until ~Oct 2026
- **4.20**: Maintenance phase (GA Oct 21, 2025) - Full support ended May 3, 2026
- **4.19**: Maintenance phase (GA Jun 17, 2025) - Full support ended Jan 21, 2026
- **4.18**: EUS Active (GA Feb 25, 2025) - Extended support until Aug 25, 2026
- **4.17**: End of Life (EOL April 1, 2026) - No longer supported

### Added

#### Core Installation Features
- Agent-Based Installer automation for SNO, 3-node compact, and HA cluster deployments
- Support for bare metal, vSphere, and platform=none configurations
- Comprehensive disconnected/air-gapped deployment support with registry mirroring
- Appliance-based deployment method for fully offline environments
- Advanced networking configurations (bonding, VLANs, SR-IOV, OVN-Kubernetes)
- NMState-based declarative network configuration

#### DNS and Identity Management
- Lightweight dnsmasq DNS automation (preferred approach)
- FreeIPA integration for DNS and identity management (legacy support)
- Automated DNS entry management for cluster API and ingress endpoints
- External access configuration with HAProxy, Route53, and Let's Encrypt certificates

#### Testing and Validation
- End-to-end testing framework with KVM/libvirt automation
- Environment bootstrap and validation scripts (bootstrap_env.sh, validate_env.sh)
- BMC management automation via Redfish and Sushy emulator
- VyOS router setup for network simulation

#### Deployment Patterns (19 Examples)
- **SNO Deployments**: Standard, bonded VLAN variants, disconnected, appliance-based
- **HA Deployments**: Bare metal, disconnected, stretched metro cluster
- **CNV Deployments**: Container Native Virtualization with bonded tagged VLANs
- **Platform-Specific**: VMware (connected and disconnected), JFrog integration
- **Advanced Networking**: Bond configurations (LACP, active-backup), VLAN tagging
- **Storage**: Multipath root device configuration for enterprise SAN

#### Documentation
- 15 Architectural Decision Records (ADRs) covering all major design decisions
- Comprehensive deployment guides for installation, configuration, and troubleshooting
- Platform-specific guides for bare metal, vSphere, and KVM deployments
- Advanced networking configuration examples
- Disconnected installation documentation with registry mirroring workflows

#### Automation and Tooling
- Ansible-based manifest generation with Jinja2 templates
- Automated ISO creation with openshift-install agent create image
- CLI download automation for oc, kubectl, and openshift-install
- Execution Environment (EE) container image for reproducible builds
- GitHub Actions workflows for EE builds and documentation deployment

### Known Issues

#### Deprecated API Usage (Addressed in v4.21.0)
- `imageContentSources` field used in install-config.yml.j2 (deprecated in favor of ImageDigestMirrorSet)
- OpenShiftSDN references in 25+ configuration files (removed in OpenShift 4.21)
- UpdateService template (updateservice.yml.j2) exists but not integrated into playbooks

#### Platform Support Gaps (Addressed in v4.21.0)
- Nutanix platform type not yet supported (available in OpenShift 4.20+)
- External platform type not yet supported

#### Release Infrastructure (Addressed in v4.21.0)
- No formal git tags or GitHub Releases prior to v4.20.0
- Execution Environment image uses hardcoded `latest` tag (no semantic versioning)
- Inconsistent OpenShift CLI version downloads across scripts

### Technical Debt

See the [Product Requirements Document (PRD)](docs/prd-forward-looking-roadmap.md) for comprehensive technical debt analysis and remediation roadmap.

### Contributors

- Tosin Akinosho (@tosin2013) - Project Lead and Primary Maintainer
- Community contributors via GitHub issues and pull requests

### References

- **Repository**: https://github.com/tosin2013/openshift-agent-install
- **OpenShift Documentation**: https://docs.redhat.com/en/documentation/openshift_container_platform/
- **Agent-Based Installer Guide**: https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/installing_an_on-premise_cluster_with_the_agent-based_installer/

---

## Release Notes Format

Each release documents:
- **Supported OpenShift version range** - Which OCP versions have been tested and validated
- **New features** - User-visible functionality additions
- **Bug fixes** - Resolved issues and corrections
- **Breaking changes** - Incompatible changes requiring user action
- **Deprecated features** - Features scheduled for removal in future releases
- **Known issues** - Current limitations and workarounds

## Version Alignment

This project uses a dual-track versioning model aligned with the OpenShift minor version lifecycle:

- **OCP Compatibility Releases** (e.g., v4.21.0) - Tested and stable against specific OpenShift minor version
- **Patch Releases** (e.g., v4.21.1) - Bug fixes and template corrections, safe to upgrade
- **Pre-releases** (e.g., v4.22.0-rc.1) - Early testing against OpenShift release candidates

If you are running OpenShift 4.21, use the latest v4.21.x release tag.

[Unreleased]: https://github.com/tosin2013/openshift-agent-install/compare/v4.20.0...HEAD
[4.20.0]: https://github.com/tosin2013/openshift-agent-install/releases/tag/v4.20.0
