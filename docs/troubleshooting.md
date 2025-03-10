---
layout: default
title: Troubleshooting Guide
description: Guide for troubleshooting common issues with the OpenShift Agent Install Helper
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

## Related Documentation
- [Testing Framework Overview](testing-guide)
- [End-to-End Testing](e2e-testing)
- [Environment Validation](environment-validation)
- [ADR-013: End-to-End Testing Framework](adr/0013-end-to-end-testing-framework)
- [ADR-006: Testing and Execution Environment](adr/0006-testing-and-execution-environment)
- [ADR-007: Virtual Infrastructure Testing](adr/0007-virtual-infrastructure-testing) 