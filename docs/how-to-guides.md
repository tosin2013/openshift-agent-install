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
| [Bare Metal Production Guide](bare-metal-production-guide) | Deploy OpenShift on physical servers end-to-end |
| [Fork & Adapt Checklist](fork-and-adapt-checklist) | Migrate a KVM configuration to bare metal production |
| [Platform Guides](platform-guides) | Configure bare metal, vSphere, or platform=none deployments |

## DNS

| Guide | Goal |
|-------|------|
| [DNS Setup](dns-setup) | Configure dnsmasq for cluster DNS in KVM environments |
| [Corporate DNS Integration](corporate-dns-integration) | Register cluster records in BIND, Infoblox, or Active Directory |
| [DNS Troubleshooting](dns-troubleshooting) | Diagnose and fix DNS resolution failures |

## Networking

| Guide | Goal |
|-------|------|
| [Network Configuration](network-configuration) | Configure VLANs, bonds, and static IPs via NMState |
| [Advanced Networking](advanced-networking) | Configure complex multi-NIC and bonded VLAN topologies |

## Hardware & BMC

| Guide | Goal |
|-------|------|
| [BMC Management](bmc-management) | Manage iDRAC, iLO, IPMI, and sushy virtual BMC |
| [VyOS Router Configuration](vyos-manual-configuration) | Manually configure the VyOS router via Cockpit console |

## External Access

| Guide | Goal |
|-------|------|
| [HAProxy Forwarder Guide](haproxy-forwarder-guide) | Expose cluster API and apps via HAProxy |
| [OpenShift Forwarder Role](openshift-forwarder-role) | Use the openshift-forwarder Ansible role directly |

## Identity & Operations

| Guide | Goal |
|-------|------|
| [Identity Management](identity-management) | Integrate LDAP or Active Directory with the cluster |
| [Environment Validation](environment-validation) | Validate prerequisites before deployment |
| [Troubleshooting](troubleshooting) | Resolve common deployment and runtime issues |
| [Infrastructure Setup](infrastructure-setup) | Prepare the foundational KVM/libvirt infrastructure |

## Version Management

| Guide | Goal |
|-------|------|
| [Version Validation Quick Start](version-validation-quick-start) | Run multi-version manifest validation |
| [Contributing](contributing) | Contribute documentation or code to this repository |
