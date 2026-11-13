# OpenShift Agent Install - Copilot Instructions

This file provides GitHub Copilot with repository-specific context.
See CLAUDE.md and AGENTS.md for comprehensive project guidance.









<!-- SKILLS-AUTO-START -->
## Task Skills

This repository includes task-specific skills in `hack/skills/`. When a user's request matches these patterns, read the full skill file for detailed procedures.

### bootstrap-environment (`hack/skills/bootstrap-environment/SKILL.md`)

Install packages, configure libvirt/KVM, set up dnsmasq, and validate a fresh RHEL host is ready for OpenShift ABI deployments

**Trigger patterns:**
- bootstrap environment
- set up host
- fresh install setup
- install prerequisites
- prepare KVM host
- environment setup
- first time setup
- bootstrap_env
- validate_env fails
- setup new machine

### configure-external-access (`hack/skills/configure-external-access/SKILL.md`)

Set up HAProxy forwarding, Route53 public DNS, and Let's Encrypt TLS certificates for external cluster access

**Trigger patterns:**
- external access
- configure HAProxy
- Route53 DNS
- Let's Encrypt certificates
- public access to cluster
- expose cluster externally
- configure-external-access
- TLS certificates

### create-cluster-config (`hack/skills/create-cluster-config/SKILL.md`)

Author cluster.yml and nodes.yml for SNO, 3-node compact, or HA OpenShift deployments

**Trigger patterns:**
- create cluster configuration
- new cluster config
- write cluster.yml
- write nodes.yml
- configure new cluster
- add a cluster
- SNO configuration
- HA cluster setup

### deploy-cluster-baremetal (`hack/skills/deploy-cluster-baremetal/SKILL.md`)

Deliver agent ISO to physical servers via Redfish virtual media or IPMI and monitor installation

**Trigger patterns:**
- deploy bare metal
- deploy to physical servers
- redfish deploy
- IPMI deploy
- bare metal installation
- production deployment
- deploy-iso-baremetal

### deploy-cluster-kvm (`hack/skills/deploy-cluster-kvm/SKILL.md`)

Full lifecycle KVM deployment from DNS setup through VM creation to installation monitoring (7 phases)

**Trigger patterns:**
- deploy cluster
- deploy on KVM
- create VMs
- run deployment
- deploy OpenShift
- install cluster
- deploy SNO
- deploy HA cluster

### deploy-vyos-router (`hack/skills/deploy-vyos-router/SKILL.md`)

Deploy VyOS virtual router for VLAN networking in KVM lab (requires manual Cockpit console configuration)

**Trigger patterns:**
- deploy VyOS
- VyOS router
- vyos-router
- VLAN networking setup
- lab router
- network infrastructure
- inter-VLAN routing

### destroy-cluster (`hack/skills/destroy-cluster/SKILL.md`)

Tear down a KVM cluster — removes VMs, disk images, DNS entries, and generated assets to free resources or prepare for redeployment

**Trigger patterns:**
- destroy cluster
- tear down cluster
- delete cluster
- remove cluster
- clean up cluster
- destroy on KVM
- delete VMs
- cluster cleanup
- start over
- redeploy cluster

### generate-acm-hosts (`hack/skills/generate-acm-hosts/SKILL.md`)

Convert nodes.yml BMC credentials into Kubernetes Secret and BareMetalHost manifests for RHACM/Metal3 hub-based cluster deployment

**Trigger patterns:**
- generate ACM hosts
- BareMetalHost manifest
- generate BMC hosts
- ACM deployment
- metal3 hosts
- generate_bmc_acm_hosts
- RHACM bare metal
- hub cluster deployment
- spoke cluster via ACM

### pre-release-validation (`hack/skills/pre-release-validation/SKILL.md`)

Orchestrate the full pre-release test suite across all phases (version tests, platform manifests, disconnected workflow, E2E deployment) and generate a markdown report

**Trigger patterns:**
- pre-release validation
- release validation
- pre-release-validation
- prepare release
- validate for release
- release testing
- cut a release
- release checklist
- v4.x validation

### run-e2e-tests (`hack/skills/run-e2e-tests/SKILL.md`)

Execute the full E2E test suite (ISO creation, VM deployment, installation monitoring) or version validation tests against configured cluster examples

**Trigger patterns:**
- run e2e tests
- end-to-end tests
- e2e testing
- run tests
- run_e2e
- test version validation
- full deployment test
- automated testing
- CI testing
- test deployment

### setup-sushy-emulator (`hack/skills/setup-sushy-emulator/SKILL.md`)

Configure sushy-emulator as a Redfish BMC emulator for KVM VMs, enabling bare-metal-style ISO delivery workflows on a KVM lab host

**Trigger patterns:**
- sushy emulator
- setup sushy
- redfish emulator
- virtual BMC
- sushy-emulator
- configure BMC emulation
- test libvirt ssh
- redfish for KVM
- BMC testing
- virtual redfish

### troubleshoot-dns (`hack/skills/troubleshoot-dns/SKILL.md`)

Diagnose and fix DNS issues that block OpenShift cluster deployment or access

**Trigger patterns:**
- DNS not resolving
- DNS troubleshooting
- can't resolve cluster
- NXDOMAIN
- dig fails
- dnsmasq not working
- verify-dns-resolution fails
- cluster unreachable
- API connection refused
- name resolution error

### validate-and-compare-manifests (`hack/skills/validate-and-compare-manifests/SKILL.md`)

Generate ABI manifests for multiple OCP versions, diff them to surface breaking changes, and validate against version-specific deployment standards using LLM analysis

**Trigger patterns:**
- validate manifests
- compare manifests
- version manifests
- generate version manifests
- deployment standards validation
- version comparison
- compare version manifests
- manifest validation
- LLM manifest analysis
- OCP version upgrade check

<!-- SKILLS-AUTO-END -->

