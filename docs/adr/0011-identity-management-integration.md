---
layout: default
title: "ADR-0011: DNS Infrastructure for OpenShift Testing"
description: "Architecture Decision Record for DNS Infrastructure"
---

# 11. DNS Infrastructure for OpenShift Testing

## Date
- Original: 2025-03-09 (FreeIPA approach)
- Superseded: 2026-03-16 (dnsmasq approach)

## Status
**Superseded** - Original FreeIPA-based approach replaced with lightweight dnsmasq solution

## Decision Makers
- Development Team
- Infrastructure Team

## Stakeholders
- System Administrators
- Development Teams
- Test Engineers

## Context

The project requires DNS resolution for OpenShift cluster deployments in KVM testing environments. Each cluster needs only 3 DNS records:

- `api.<cluster_name>.<base_domain>` → API VIP
- `api-int.<cluster_name>.<base_domain>` → API VIP
- `*.apps.<cluster_name>.<base_domain>` → App VIP

### Original Approach (Deprecated)
The original implementation used FreeIPA (Red Hat Identity Management) for DNS resolution. This proved problematic:

- **Outdated**: Targeted RHEL 8, incompatible with RHEL 9 environments
- **Over-engineered**: Full identity management server (Kerberos, LDAP, CA, audit) for simple DNS
- **Complex**: Required full VM deployment, bootstrap scripts, workshop deployer
- **Resource Heavy**: ~2GB RAM, full VM resources for 3 DNS A records per cluster
- **Maintenance Burden**: Security patches, updates for unused features
- **Setup Failures**: Image download errors, GPG key issues, CentOS/RHEL conflicts

**Reality Check**: Despite claiming "full identity management integration", ZERO identity features were implemented. Only DNS was used.

## Considered Options

1. **FreeIPA** (original approach)
   - ❌ Over-engineered for DNS-only use
   - ❌ RHEL 8 dependency, RHEL 9 incompatible
   - ❌ High resource overhead

2. **dnsmasq** (selected approach)
   - ✅ Lightweight (~100MB RAM vs 2GB VM)
   - ✅ Simple text file configuration
   - ✅ Fast setup (< 1 min vs 10-15 min)
   - ✅ RHEL 9 compatible
   - ✅ Widely used in virtualization

3. **CoreDNS**
   - ✅ Modern, cloud-native
   - ❌ More complex than needed for simple testing

4. **BIND**
   - ✅ Industry standard
   - ❌ Over-engineered for test environment

5. **External DNS Service**
   - ❌ Requires external dependencies
   - ❌ Not suitable for isolated testing

## Decision

**We have implemented a lightweight dnsmasq-based DNS solution**, replacing the FreeIPA approach entirely.

### Key Components

1. **dnsmasq Installation and Configuration**
   - Minimal package installation
   - Single configuration file: `/etc/dnsmasq.d/openshift.conf`
   - Systemd service management

2. **Automation Scripts**
   - `hack/setup-dnsmasq.sh` - Install and configure dnsmasq
   - `hack/configure-dnsmasq-entries.sh` - Manage DNS entries from cluster configs
   - Integration with `e2e-tests/bootstrap_env.sh`

3. **DNS Entry Management**
   - Automatic parsing of `cluster.yml` files
   - Dynamic DNS entry generation
   - Support for multiple clusters

### Implementation

```bash
# Install and configure dnsmasq
sudo ./hack/setup-dnsmasq.sh

# Add DNS entries for a cluster
sudo ./hack/configure-dnsmasq-entries.sh add examples/sno-4.20-standard/cluster.yml

# Test DNS resolution
dig @localhost api.sno-4-20.example.com
```

## Rationale

### Why dnsmasq?

1. **Right-sized for the task**: Provides exactly what we need (DNS) without unnecessary features
2. **Battle-tested**: Widely used in KVM/libvirt environments for similar purposes
3. **Simple**: Text file configuration, no complex APIs or databases
4. **Fast**: Immediate setup, no VM provisioning delays
5. **Maintainable**: Single package, standard RHEL/Fedora tooling
6. **Resource Efficient**: ~100MB RAM vs 2GB for FreeIPA VM

### Performance Comparison

| Aspect | FreeIPA (Old) | dnsmasq (New) |
|--------|---------------|---------------|
| RAM Usage | ~2GB | ~100MB |
| Disk Usage | ~10GB | ~50MB |
| Setup Time | 10-15 min | < 1 min |
| Dependencies | Full RHEL 8 VM | Single package |
| Configuration | Multiple playbooks | Single text file |
| RHEL 9 Support | ❌ No | ✅ Yes |
| Maintenance | VM patching | Package updates |

## Consequences

### Positive

1. **Simplified Infrastructure**: No dedicated VM required
2. **Faster Bootstrap**: Setup completes in seconds vs minutes
3. **Better Maintainability**: Simple text configuration vs complex playbooks
4. **Lower Resource Usage**: 95% reduction in RAM/disk overhead
5. **RHEL 9 Compatible**: Uses standard packages
6. **Easier Debugging**: Standard logging, familiar tools

### Negative

1. **Breaking Change**: Requires migration from existing FreeIPA setups
2. **No Identity Features**: Pure DNS only (but identity features were never used anyway)
3. **Single Point**: DNS runs on host (but suitable for test environments)

### Neutral

- For production OpenShift deployments, DNS should be provided by production DNS infrastructure
- This solution targets development/testing environments only

## Implementation Details

### File Structure

```
hack/
├── setup-dnsmasq.sh                    # Install and configure dnsmasq
├── configure-dnsmasq-entries.sh        # Manage DNS entries
└── deploy-freeipa.sh                   # Deprecated, kept for reference

e2e-tests/
└── bootstrap_env.sh                    # Updated to use dnsmasq

docs/
└── dns-setup.md                        # Complete DNS documentation

/etc/dnsmasq.d/
└── openshift.conf                      # DNS configuration
```

### DNS Entry Format

```bash
# /etc/dnsmasq.d/openshift.conf
address=/api.cluster-name.domain.com/192.168.100.50
address=/api-int.cluster-name.domain.com/192.168.100.50
address=/.apps.cluster-name.domain.com/192.168.100.50
```

### Usage Examples

```bash
# List all DNS entries
sudo ./hack/configure-dnsmasq-entries.sh list

# Add entries for a cluster
sudo ./hack/configure-dnsmasq-entries.sh add site-config/my-cluster/cluster.yml

# Remove entries
sudo ./hack/configure-dnsmasq-entries.sh remove my-cluster example.com

# Test resolution
dig @localhost api.my-cluster.example.com
```

## Migration Path

For users migrating from FreeIPA:

1. **Stop FreeIPA VM**: `sudo kcli delete vm freeipa` (optional)
2. **Install dnsmasq**: `sudo ./hack/setup-dnsmasq.sh`
3. **Add DNS entries**: For each cluster, run the configure script
4. **Update cluster configs**: Point `dns_servers` to dnsmasq host
5. **Verify**: Test DNS resolution before deployment

## Links

### Documentation
- [DNS Setup Guide](../dns-setup.md) - Complete setup and troubleshooting
- [Migration Guide](../dns-setup.md#migration-from-freeipa)

### Related ADRs
- ADR-0003: Ansible Automation Approach
- ADR-0007: Virtual Infrastructure Testing
- ADR-0013: End-to-End Testing Framework

### Code References
- `hack/setup-dnsmasq.sh` - dnsmasq installation
- `hack/configure-dnsmasq-entries.sh` - DNS entry management
- `e2e-tests/bootstrap_env.sh` - Bootstrap integration
- `hack/deploy-freeipa.sh` - Deprecated FreeIPA deployment

### External References
- [dnsmasq Documentation](http://www.thekelleys.org.uk/dnsmasq/doc.html)
- [OpenShift Agent-Based Installation](https://docs.openshift.com/container-platform/latest/installing/installing_with_agent_based_installer/)

## Future Considerations

1. **Optional HAProxy Integration**: For HA testing, the [openshift-forwarder](https://github.com/tosin2013/openshift-forwarder) tool can provide HAProxy-based load balancing (separate from DNS)

2. **DNS Cache Tuning**: Adjust cache size based on cluster count

3. **Multi-host DNS**: For larger test environments, consider DNS replication

4. **CoreDNS Migration**: If REST API management becomes needed

## Related

- [DNS Setup Guide](../dns-setup.md)
- [E2E Testing Guide](../e2e-testing.md)
- [Bootstrap Documentation](../../e2e-tests/README.md)
- [Example Configurations](../../examples/)
