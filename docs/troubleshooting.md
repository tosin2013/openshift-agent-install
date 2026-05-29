---
layout: default
title: Troubleshooting Guide
description: Guide for troubleshooting common issues with the OpenShift Agent Install Helper
parent: How-to Guides
nav_order: 15
---

# Troubleshooting Guide

This guide provides solutions for common issues encountered when using the OpenShift Agent Install Helper.

## Common Issues

### 1. Environment Setup Issues

#### Package Installation Failures
```bash
# Issue: Package installation errors
Error: Failed to install required packages

# Solution:
# 1. Check repository access
sudo dnf clean all
sudo dnf repolist

# 2. Update system
sudo dnf update -y

# 3. Retry installation
sudo dnf install -y nmstate ansible-core bind-utils
```

#### Service Configuration Problems
```bash
# Issue: Service fails to start
Error: Failed to start libvirtd.service

# Solution:
# 1. Check service status
sudo systemctl status libvirtd

# 2. Check logs
journalctl -u libvirtd

# 3. Resolve dependencies
sudo dnf install -y libvirt-daemon libvirt-daemon-driver-qemu

# 4. Restart service
sudo systemctl restart libvirtd
```

### 2. Network Issues

#### DNS Resolution Failures
```bash
# Issue: DNS resolution not working
Error: Could not resolve hostname

# Solution:
# 1. Check DNS configuration
cat /etc/resolv.conf

# 2. Test DNS resolution
dig +short api.cluster.domain

# 3. Update DNS settings
sudo nmcli con mod eth0 ipv4.dns "8.8.8.8"
```

#### Network Interface Problems
```bash
# Issue: Network interface not available
Error: Could not find interface bond0

# Solution:
# 1. Check interface status
nmcli device show

# 2. Create bond interface
sudo nmcli con add type bond con-name bond0 ifname bond0

# 3. Verify configuration
ip addr show bond0
```

### 3. Virtual Machine Issues

#### VM Creation Failures
```bash
# Issue: VM creation fails
Error: Could not create virtual machine

# Solution:
# 1. Check libvirt status
sudo systemctl status libvirtd

# 2. Verify storage pool
sudo virsh pool-list --all

# 3. Check resources
free -h
df -h
```

#### VM Network Problems
```bash
# Issue: VM network connectivity issues
Error: VM cannot access network

# Solution:
# 1. Check network definition
sudo virsh net-list --all

# 2. Verify bridge configuration
brctl show

# 3. Test connectivity
ping -c 4 vm_ip
```

### 4. ISO Creation Issues

#### ISO Generation Failures
```bash
# Issue: ISO creation fails
Error: Failed to create ISO

# Solution:
# 1. Check space
df -h /var/tmp

# 2. Verify permissions
ls -l /var/tmp

# 3. Clean up old files
sudo rm -f /var/tmp/*.iso

# 4. Retry creation
./hack/create-iso.sh <config_dir>
```

#### ISO Boot Problems
```bash
# Issue: ISO won't boot
Error: Boot failed

# Solution:
# 1. Verify ISO checksum
sha256sum generated.iso

# 2. Check VM configuration
virsh dumpxml vm_name

# 3. Regenerate ISO
./hack/create-iso.sh <config_dir>
```

### 5. Installation Issues

#### Bootstrap Failures
```bash
# Issue: Bootstrap process fails
Error: Bootstrap failed to complete

# Solution:
# 1. Check logs
./hack/watch-and-reboot-kvm-vms.sh <config_dir>

# 2. Verify network
./hack/configure_dns_entries.sh <config_dir>

# 3. Review configuration
cat examples/<config_dir>/cluster.yml
```

#### Installation Timeouts
```bash
# Issue: Installation times out
Error: Installation did not complete in time

# Solution:
# 1. Check resources
top -b -n 1

# 2. Monitor progress
tail -f /var/log/messages

# 3. Review timeouts
cat e2e-tests/run_e2e.sh
```

## Log Collection

### 1. System Logs
```bash
# Collect system logs
journalctl -xe > system.log

# Get service logs
systemctl status libvirtd > service.log

# Check VM logs
virsh console vm_name
```

### 2. Installation Logs
```bash
# Get installation logs
./hack/collect-logs.sh <config_dir>

# Check bootstrap logs
./hack/watch-and-reboot-kvm-vms.sh <config_dir>
```

## Best Practices

### 1. Environment Preparation
- Clean up old resources
- Verify system requirements
- Update system packages
- Check available space

### 2. Installation Process
- Monitor resource usage
- Check network connectivity
- Review logs regularly
- Document issues

### 3. Problem Resolution
- Collect relevant logs
- Document steps taken
- Test solutions thoroughly
- Update documentation

## Prevention Tips

### 1. Regular Maintenance
- Update packages regularly
- Monitor resource usage
- Clean up old files
- Check service status

### 2. Configuration Management
- Back up configurations
- Version control changes
- Document modifications
- Test changes

### 3. Resource Management
- Monitor disk space
- Track memory usage
- Check CPU utilization
- Manage network resources

---

## Bare Metal Issues

### ISO Not Booting on Physical Server

```bash
# Check 1: Verify UEFI boot mode is enabled (BIOS legacy not supported)
# Access BIOS/UEFI on target server and confirm:
#   - Boot mode: UEFI (not Legacy/BIOS)
#   - Secure Boot: Disabled
#   - Virtual media / NIC PXE: First in boot order

# Check 2: Verify ISO integrity before delivery
sha256sum ~/generated_assets/<cluster-name>/agent.x86_64.iso

# Check 3: Test virtual media mount via Redfish
curl -sk -u "root:${BMC_PASSWORD}" \
  "https://<idrac-ip>/redfish/v1/Managers/iDRAC.Embedded.1/VirtualMedia/CD" \
  | python3 -m json.tool | grep -E "Inserted|Image"

# Check 4: Access BMC serial console to watch boot messages
ipmitool -I lanplus -H <bmc-ip> -U <user> -P "${BMC_PASSWORD}" sol activate
```

### Node Not Appearing in Agent Discovery

After booting from the ISO, nodes should register with the agent discovery service within 10 minutes.

```bash
# Watch bootstrap-complete for discovery progress
./bin/openshift-install agent wait-for bootstrap-complete \
  --dir ~/generated_assets/<cluster-name>/ --log-level=debug 2>&1 | grep -i "host\|discovered\|registered"

# If no nodes appear after 15 minutes:
# 1. Check network connectivity from the server (SOL console)
ipmitool -I lanplus -H <bmc-ip> -U <user> -P "${BMC_PASSWORD}" sol activate
# Inside the booted node:
ip addr show
ping -c 3 <rendezvous-ip>

# 2. Verify DNS resolves from inside the node
dig api.<cluster>.<domain>

# 3. Verify the NIC name in nodes.yml matches the actual interface
ip link show
```

### Wrong NIC Name in nodes.yml

The node boots but uses an unexpected interface name (`enp97s0f0` instead of `eno1`).

```bash
# Access node via BMC console after boot
ipmitool -I lanplus -H <bmc-ip> -U <user> -P "${BMC_PASSWORD}" sol activate

# List interfaces
ip link show

# Update nodes.yml with the correct name, then regenerate the ISO
# and reboot the node from the new ISO
```

Common interface naming patterns on physical hardware:

| Pattern | Example | Vendor / Driver |
|---------|---------|----------------|
| `eno<N>` | `eno1` | Onboard (Dell, HPE) |
| `enp<slot>s<port>` | `enp97s0f0` | PCIe slot |
| `ens<N>f<port>` | `ens3f0` | Intel NIC naming |
| `eth<N>` | `eth0` | Predictable naming disabled |

### BMC Connectivity Failures

```bash
# Test IPMI access
ipmitool -I lanplus -H <bmc-ip> -U <user> -P "${BMC_PASSWORD}" power status

# Test Redfish access
curl -sk -u "<user>:${BMC_PASSWORD}" \
  https://<bmc-ip>/redfish/v1/Systems | python3 -m json.tool

# Common Redfish paths by vendor:
#   Dell iDRAC:  /redfish/v1/Systems/System.Embedded.1
#   HPE iLO:     /redfish/v1/Systems/1
#   Supermicro:  /redfish/v1/Systems/1

# If certificate errors:
# Add disableCertificateVerification: true in nodes.yml bmc block
# Or use -k with curl to bypass for testing
```

### VIP Not Reachable After Installation

The API (`api.<cluster>.<domain>`) or apps VIP (`*.apps.<cluster>.<domain>`) is not accessible after installation completes.

```bash
# Check 1: Verify VIPs are in the machine_network_cidr
# cluster.yml must have both VIPs on the same /24 (or wider) as node IPs

# Check 2: Verify keepalived is running (platform_type: baremetal manages VIPs via keepalived)
export KUBECONFIG=~/generated_assets/<cluster-name>/auth/kubeconfig
oc get pod -n openshift-ovn-kubernetes -l app=ovnkube-master | head -5

# Check 3: VIPs require L2 (same broadcast domain) reachability
# The VIP must be on the same VLAN/subnet as the cluster nodes
# If on a routed (L3) network, platform_type: baremetal will not work — use an external load balancer

# Check 4: Ping VIP from another host on the same subnet
ping -c 3 <api-vip>
```

### NMState networkConfig Syntax Errors

```bash
# Validate NMState syntax before generating the ISO
nmstatectl gc site-config/<cluster-name>/nodes.yml

# Common errors:
# - 'mac-address' must match 'mac_address' in the interfaces[] block exactly
# - 'next-hop-address' gateway must be reachable from the node's subnet
# - IPv6 must be explicitly disabled if not used: ipv6: {enabled: false}
```

### Installation Hangs with No Progress

```bash
# Check bootstrap node logs (the rendezvous IP node)
ssh -i ~/.ssh/id_rsa core@<rendezvous-ip>
journalctl -u bootkube --no-pager | tail -30

# Check for registry pull failures (disconnected environments)
journalctl -u release-image | tail -20

# Check cluster operator status after bootstrap-complete
export KUBECONFIG=~/generated_assets/<cluster-name>/auth/kubeconfig
oc get co | grep -v "True.*False.*False"
oc get nodes
```

---

## Related Documentation
- [Bare Metal Production Guide](bare-metal-production-guide.md)
- [BMC Management Guide](bmc-management.md)
- [Corporate DNS Integration](corporate-dns-integration.md)
- [Testing Framework Overview](testing-guide)
- [End-to-End Testing](e2e-testing)
- [Environment Validation](environment-validation)
- [ADR-013: End-to-End Testing Framework](adr/0013-end-to-end-testing-framework)
- [ADR-006: Testing and Execution Environment](adr/0006-testing-and-execution-environment)
- [ADR-007: Virtual Infrastructure Testing](adr/0007-virtual-infrastructure-testing) 