---
layout: default
title: How-to Guides
nav_order: 3
has_children: true
---

# How-to Guides

How-to guides are **task-oriented**. They help you accomplish a specific goal and assume you already have basic knowledge of the tooling. Unlike tutorials, they do not hold your hand — they are practical directions for people who know what they want to do.

## Deployment

| Guide | Goal |
|-------|------|
| [Bare Metal Production Guide](bare-metal-production-guide.md) | Deploy OpenShift on physical servers end-to-end |
| [Fork & Adapt Checklist](fork-and-adapt-checklist.md) | Migrate a KVM configuration to bare metal production |
| [Platform Guides](platform-guides.md) | Configure bare metal, vSphere, or platform=none deployments |

## DNS

| Guide | Goal |
|-------|------|
| [DNS Setup](dns-setup.md) | Configure dnsmasq for cluster DNS in KVM environments |
| [Corporate DNS Integration](corporate-dns-integration.md) | Register cluster records in BIND, Infoblox, or Active Directory |
| [DNS Troubleshooting](dns-troubleshooting.md) | Diagnose and fix DNS resolution failures |

## Networking

| Guide | Goal |
|-------|------|
| [Network Configuration](network-configuration.md) | Configure VLANs, bonds, and static IPs via NMState |
| [Advanced Networking](advanced-networking.md) | Configure complex multi-NIC and bonded VLAN topologies |

## Hardware & BMC

| Guide | Goal |
|-------|------|
| [BMC Management](bmc-management.md) | Manage iDRAC, iLO, IPMI, and sushy virtual BMC |
| [VyOS Router Configuration](vyos-manual-configuration.md) | Manually configure the VyOS router via Cockpit console |

## External Access

| Guide | Goal |
|-------|------|
| [HAProxy Forwarder Guide](haproxy-forwarder-guide.md) | Expose cluster API and apps via HAProxy |
| [OpenShift Forwarder Role](openshift-forwarder-role.md) | Use the openshift-forwarder Ansible role directly |

## Identity & Operations

| Guide | Goal |
|-------|------|
| [Identity Management](identity-management.md) | Integrate LDAP or Active Directory with the cluster |
| [Environment Validation](environment-validation.md) | Validate prerequisites before deployment |
| [Troubleshooting](troubleshooting.md) | Resolve common deployment and runtime issues |
| [Infrastructure Setup](infrastructure-setup.md) | Prepare the foundational KVM/libvirt infrastructure |

## Version Management

| Guide | Goal |
|-------|------|
| [Version Validation Quick Start](version-validation-quick-start.md) | Run multi-version manifest validation |
| [Contributing](contributing.md) | Contribute documentation or code to this repository |
