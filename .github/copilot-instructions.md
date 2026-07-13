# OpenShift Agent Install - Copilot Instructions

This file provides GitHub Copilot with repository-specific context.
See CLAUDE.md and AGENTS.md for comprehensive project guidance.



<!-- SKILLS-AUTO-START -->
## Task Skills

This repository includes task-specific skills in `hack/skills/`. When a user's request matches these patterns, read the full skill file for detailed procedures.

### Configure External Access (`hack/skills/configure-external-access/SKILL.md`)

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

### Create Cluster Configuration (`hack/skills/create-cluster-config/SKILL.md`)

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

### Deploy Cluster on Bare Metal (`hack/skills/deploy-cluster-baremetal/SKILL.md`)

Deliver agent ISO to physical servers via Redfish virtual media or IPMI and monitor installation

**Trigger patterns:**
- deploy bare metal
- deploy to physical servers
- redfish deploy
- IPMI deploy
- bare metal installation
- production deployment
- deploy-iso-baremetal

### Deploy Cluster on KVM (`hack/skills/deploy-cluster-kvm/SKILL.md`)

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

### Deploy VyOS Router (`hack/skills/deploy-vyos-router/SKILL.md`)

Deploy VyOS virtual router for VLAN networking in KVM lab (requires manual Cockpit console configuration)

**Trigger patterns:**
- deploy VyOS
- VyOS router
- vyos-router
- VLAN networking setup
- lab router
- network infrastructure
- inter-VLAN routing

### Troubleshoot DNS Resolution (`hack/skills/troubleshoot-dns/SKILL.md`)

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

<!-- SKILLS-AUTO-END -->

