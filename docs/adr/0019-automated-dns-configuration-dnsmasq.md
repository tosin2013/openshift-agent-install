---
layout: default
title: "ADR-0019: Use Automated DNS Configuration with dnsmasq"
parent: ADRs
nav_order: 0019
---

# ADR-0001: Use Automated DNS Configuration with dnsmasq

## Date
2026-05-28

## Status
Accepted

## Context

OpenShift cluster deployments require DNS configuration for:
- API endpoints: `api.<cluster>.<domain>` and `api-int.<cluster>.<domain>`
- Application routes: `*.apps.<cluster>.<domain>` (wildcard)

The previous approach relied on manual FreeIPA DNS configuration, which had several problems:
- Manual configuration was error-prone and time-consuming
- No automatic cleanup when clusters were destroyed
- Difficult to manage multiple clusters simultaneously
- Required separate FreeIPA infrastructure

For development and testing environments using KVM/libvirt, we needed a lightweight, automated solution that could:
- Configure DNS automatically during deployment
- Support multiple clusters with isolated DNS entries
- Clean up DNS entries automatically when clusters are destroyed
- Persist configuration across host reboots

## Decision

We will implement automated DNS configuration using dnsmasq integrated with libvirt's network DNS:

1. **DNS Server**: Use dnsmasq (lightweight DNS forwarder) as the DNS server
2. **Integration**: Integrate with libvirt's default network DNS (192.168.122.1)
3. **Automation**: Automatically configure DNS entries in deployment scripts
4. **Host DNS**: Configure host to use libvirt DNS as primary, with upstream DNS as backup

### Implementation Components

- `hack/setup-dnsmasq.sh` - Installs and configures dnsmasq server
- `hack/configure-dnsmasq-entries.sh` - CLI tool to manage DNS entries (add/remove/list)
- `hack/deploy-on-kvm.sh` - Automatically configures DNS before VM deployment
- `hack/destroy-on-kvm.sh` - Automatically removes DNS entries before cluster destruction

### DNS Entry Management

DNS entries are managed through libvirt's `virsh net-update` command with `--live --config` flags to ensure persistence:

```bash
# API endpoints
virsh net-update default add dns-host \
  "<host ip='<API_VIP>'><hostname>api.<cluster>.<domain></hostname></host>" \
  --live --config
```

Common application routes are pre-configured:
- console-openshift-console.apps
- oauth-openshift.apps
- grafana-openshift-monitoring.apps
- prometheus-k8s-openshift-monitoring.apps
- alertmanager-main-openshift-monitoring.apps

## Consequences

### Positive Consequences

- **Zero Manual Configuration**: DNS entries automatically created during deployment
- **Multi-Cluster Support**: Multiple clusters can coexist with isolated DNS entries
- **Automatic Cleanup**: DNS entries removed automatically when cluster is destroyed
- **Persistent**: Configuration survives host reboots (`--live --config` flags)
- **Host Integration**: `oc` commands work without `--server` or `--insecure-skip-tls-verify`
- **Graceful Fallback**: Deployment continues even if DNS configuration fails (warnings only)
- **Lightweight**: dnsmasq is much simpler than FreeIPA for development environments

### Negative Consequences

- **No Wildcard Support**: Libvirt dnsmasq doesn't support `*.apps.<domain>` wildcards
  - Mitigation: Pre-configure common app routes automatically
  - Impact: Less common routes may need manual addition
  
- **Sudo Required**: `virsh net-update` and `nmcli` commands require sudo privileges
  - Impact: User must have sudo access on deployment host
  
- **NetworkManager Dependency**: Host DNS configuration requires NetworkManager
  - Impact: Systems using systemd-resolved or static networking will skip host DNS setup (libvirt DNS entries still configured)

- **Development Environment Focus**: This solution is optimized for KVM development environments
  - Production bare metal deployments still need proper DNS infrastructure

### Risk Mitigation

- DNS configuration failures are logged but don't block deployment
- Duplicate entry warnings are suppressed to allow re-runs
- DNS cleanup runs before VM destruction to ensure proper teardown
- Existing upstream DNS servers are preserved as backup

## Alternatives Considered

### Continue Using Manual FreeIPA DNS Configuration
**Rejected**: Too manual, error-prone, requires separate FreeIPA infrastructure, no automatic cleanup

### Use /etc/hosts File
**Rejected**: Doesn't support wildcard routes, not scalable for multiple clusters, not suitable for VMs

### Deploy Dedicated BIND DNS Server
**Rejected**: Too heavyweight for development environment, adds complexity, requires ongoing management

### Use External DNS Service
**Rejected**: Requires external dependencies, not suitable for disconnected/air-gap scenarios, cost for commercial services

## References

- DNS_AUTOMATION.md - Implementation documentation
- hack/setup-dnsmasq.sh - DNS server setup
- hack/configure-dnsmasq-entries.sh - DNS management CLI
- hack/deploy-on-kvm.sh (lines 49-136) - Automated DNS configuration
- hack/destroy-on-kvm.sh (lines 12-53) - Automated DNS cleanup
