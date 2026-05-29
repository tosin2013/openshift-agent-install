---
layout: default
title: "VyOS Router Manual Configuration Guide"
parent: Getting Started
nav_order: 4
---

# VyOS Router Manual Configuration Guide

## Overview

The VyOS router deployment requires **manual configuration** via Cockpit web console. This is a necessary step that **cannot be automated** because VyOS boots from a live ISO and requires interactive installation to disk before network configuration can be applied.

**Time Required**: 10-15 minutes  
**Skill Level**: Beginner (copy/paste commands)  
**Prerequisites**: Cockpit access configured

---

## Prerequisites

### 1. Cockpit Access

Verify Cockpit is accessible and you have credentials:

```bash
# Check Cockpit is running
systemctl status cockpit.socket

# View credentials (if using SSH key-only authentication)
cat ~/cockpit-credentials.txt
```

**Expected Output**:
```
============================================
Cockpit Web Console Credentials
============================================

Access URL: https://10.241.64.8:9090

Username: cockpit-admin
Password: <random-password>
============================================
```

### 2. VyOS Router VM Created

The VyOS router VM should be created by `hack/vyos-router.sh` BEFORE you start manual configuration:

```bash
# Check VyOS VM exists and is running
sudo virsh list | grep vyos-router
```

**Expected Output**:
```
vyos-router            running
```

---

## Configuration Steps

### Step 1: Access Cockpit Web Console

1. Open browser to: `https://<your-host-ip>:9090`
   - Get host IP: `hostname -I | awk '{print $1}'`
   - Example: `https://10.241.64.8:9090`

2. Login with credentials from `~/cockpit-credentials.txt`
   - Username: `cockpit-admin`
   - Password: (shown in credentials file)

3. Accept self-signed certificate warning (click "Advanced" → "Proceed")

---

### Step 2: Open VyOS VM Console

1. Click **"Virtual Machines"** in left sidebar
2. Find **"vyos-router"** in the list
3. Click on **"vyos-router"** to open VM details
4. Click **"Console"** tab at the top

You should see the VyOS boot screen or login prompt.

---

### Step 3: Install VyOS to Disk

**Login to VyOS**:
- Username: `vyos`
- Password: `vyos`

**Run Installation**:
```bash
install image
```

**Installation Prompts** (press ENTER for defaults):
```
Would you like to continue? (Yes/No) [Yes]: Yes
Partition (Auto/Parted/Skip) [Auto]: Auto
Install the image on? [sda]: sda
Continue? (Yes/No) [No]: Yes
How big of a root partition should I create? (2000MB - 20480MB) [20480]: 20480
What would you like to name this image? [1.5.x-rolling-xxx]: <ENTER>
Which one should I copy to sda? [/opt/vyatta/etc/config/config.boot]: <ENTER>
Which drive should GRUB modify the boot partition on? [sda]: sda
```

**VM will reboot automatically after installation.**

---

### Step 4: Restart VM and Reconfigure Console

After installation completes and VM reboots:

1. The console may show a blank screen or boot messages
2. In Cockpit, click **"Power Off"** button
3. Wait for VM to fully stop (status shows "shut off")
4. Click **"Run"** button to start VM
5. Click **"Console"** tab again
6. Wait for VyOS login prompt (may take 30-60 seconds)

---

### Step 5: Configure Network Interfaces

**Login to VyOS** (after reboot):
- Username: `vyos`
- Password: `vyos`

**Enter configuration mode**:
```bash
configure
```

**Configure eth0 (Internet-facing interface)**:
```bash
set interfaces ethernet eth0 address 192.168.122.2/24
set interfaces ethernet eth0 description 'Internet-Facing'
set protocols static route 0.0.0.0/0 next-hop 192.168.122.1
```

**Configure DNS forwarder**:
```bash
set service dns forwarding listen-address 192.168.122.2
set service dns forwarding allow-from 192.168.0.0/16
set service dns forwarding name-server 192.168.122.1
```

**Commit and save**:
```bash
commit
save
exit
```

---

### Step 6: Enable SSH Access

**Enter configuration mode**:
```bash
configure
```

**Enable SSH**:
```bash
set service ssh port 22
set service ssh listen-address 0.0.0.0
commit
save
exit
```

**Verify SSH is running**:
```bash
show service ssh
```

**Test connectivity from host**:
```bash
# From another terminal on the hypervisor host:
ping -c 3 192.168.122.2
```

---

### Step 7: Apply VyOS Configuration Script

The `vyos-router.sh` script downloads a configuration template to `~/vyos-config.sh`. This configures VLAN interfaces and routing.

**Copy script to VyOS router**:
```bash
# From hypervisor host terminal:
scp ~/vyos-config.sh vyos@192.168.122.2:/tmp/
```

**SSH into VyOS**:
```bash
ssh vyos@192.168.122.2
# Password: vyos
```

**Apply configuration**:
```bash
chmod +x /tmp/vyos-config.sh
vbash /tmp/vyos-config.sh
```

**Expected Output**:
```
Configuration applied successfully
VLANs configured: 1924, 1925, 1926, 1927, 1928
Static routes added
DNS forwarding configured
```

**Exit SSH session**:
```bash
exit
```

---

### Step 8: Verify VyOS Configuration

**From hypervisor host**, verify VyOS is accessible on VLAN networks:

```bash
# Test VLAN network connectivity
ping -c 3 192.168.50.1   # Example VLAN gateway
ping -c 3 192.168.122.2  # VyOS primary interface
```

**Check libvirt networks created**:
```bash
sudo virsh net-list --all
```

**Expected Output**:
```
Name      State    Autostart   Persistent
--------------------------------------------
default   active   yes         yes
1924      active   yes         yes
1925      active   yes         yes
1926      active   yes         yes
1927      active   yes         yes
1928      active   yes         yes
```

---

## Troubleshooting

### Console Shows Blank Screen

**Solution**: 
1. Click away from Console tab
2. Click back to Console tab
3. Press ENTER key to refresh

### VM Won't Start After Installation

**Solution**:
```bash
# Force stop and restart
sudo virsh destroy vyos-router
sudo virsh start vyos-router
```

### Cannot SSH to VyOS (Connection Refused)

**Check VyOS is accessible**:
```bash
ping 192.168.122.2
```

**If ping works but SSH doesn't**:
1. Access VyOS console via Cockpit
2. Verify SSH is enabled: `show service ssh`
3. Check firewall: `show firewall`

### vyos-config.sh Script Fails

**Common causes**:
- DNS not configured → Rerun Step 5
- eth0 not configured → Rerun Step 5
- Script syntax error → Check script was downloaded correctly

**Re-download script**:
```bash
# On hypervisor host:
cd ~
rm -f vyos-config.sh
curl -OL https://raw.githubusercontent.com/tosin2013/demo-virt/rhpds/demo.redhat.com/vyos-config-1.5.sh
mv vyos-config-1.5.sh vyos-config.sh
chmod +x vyos-config.sh
```

---

## Next Steps

After VyOS configuration is complete:

1. **Verify DNS is configured**:
   ```bash
   sudo ./hack/setup-dnsmasq.sh
   sudo ./hack/configure-dnsmasq-entries.sh add examples/<cluster>/cluster.yml
   ./hack/verify-dns-resolution.sh examples/<cluster>/cluster.yml
   ```

2. **Create OpenShift cluster ISO**:
   ```bash
   ./hack/create-iso.sh <cluster-name>
   ```

3. **Deploy OpenShift cluster**:
   ```bash
   ./hack/deploy-on-kvm.sh examples/<cluster>/nodes.yml --redfish
   ```

---

## Related Documentation

- [DNS Troubleshooting Guide](dns-troubleshooting.md)
- [Developer Guide - Hard Requirements](developer-guide.md#hard-requirement-vyos-router)
- [VyOS Official Documentation](https://docs.vyos.io/)
- [demo-virt VyOS Configuration Guide](https://github.com/tosin2013/demo-virt/blob/rhpds/demo.redhat.com/docs/step1.md)

---

## Reference: Network Architecture

After VyOS configuration, your network topology looks like:

```
┌─────────────────────────────────────────────────────────┐
│ Hypervisor Host (10.241.64.8)                          │
│                                                         │
│  ┌─────────────────────────────────────────────┐       │
│  │ VyOS Router VM (vyos-router)               │       │
│  │  - eth0: 192.168.122.2/24 (default network)│       │
│  │  - eth1: VLAN 1924 (192.168.49.0/24)       │       │
│  │  - eth2: VLAN 1925 (192.168.50.0/24)       │       │
│  │  - eth3: VLAN 1926 (192.168.51.0/24)       │       │
│  │  - eth4: VLAN 1927 (192.168.52.0/24)       │       │
│  │  - eth5: VLAN 1928 (192.168.53.0/24)       │       │
│  └─────────────────────────────────────────────┘       │
│                                                         │
│  ┌─────────────────────────────────────────────┐       │
│  │ OpenShift VMs (when deployed)              │       │
│  │  - Connected to VLAN networks              │       │
│  │  - Routed through VyOS                     │       │
│  └─────────────────────────────────────────────┘       │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**Default Network (192.168.122.0/24)**:
- Managed by libvirt dnsmasq (192.168.122.1)
- VyOS router accessible at 192.168.122.2
- Provides internet access to VyOS

**VLAN Networks (192.168.49-58.0/24)**:
- Managed by VyOS router
- OpenShift clusters deployed here
- Isolated from default network
- Routed through VyOS to internet
