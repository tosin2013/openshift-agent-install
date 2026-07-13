---
name: Deploy VyOS Router
description: Deploy VyOS virtual router for VLAN networking in KVM lab (requires manual Cockpit console configuration)
triggers:
  - deploy VyOS
  - VyOS router
  - vyos-router
  - VLAN networking setup
  - lab router
  - network infrastructure
  - inter-VLAN routing
---

# Deploy VyOS Router

## When to Use This Skill

Activate when a user wants to:
- Set up VLAN-based networking for their KVM lab
- Deploy the VyOS virtual router required for multi-network examples
- Troubleshoot VyOS router issues
- Understand the manual configuration steps required

## CRITICAL WARNING

**This deployment REQUIRES manual human intervention via the Cockpit web console.**

The VyOS router cannot be fully automated because:
- VyOS boots from an ISO and requires interactive `install image` to disk
- Network configuration must be applied via console before SSH is available
- The script PAUSES and WAITS for manual steps (up to 30 minutes)

**Before starting:** Verify Cockpit access is working:
```bash
cat ~/cockpit-credentials.txt
# Access: https://<host-ip>:9090
```

## Prerequisites

- KVM/libvirt running (`systemctl status libvirtd`)
- Cockpit accessible at `https://<host-ip>:9090`
- dnsmasq running (`systemctl status dnsmasq`)
- Internet access (to download VyOS ISO)
- sudo/root access

## Procedure

### Step 1: Start the VyOS Deployment Script

```bash
./hack/vyos-router.sh
```

The script will:
1. Detect DNS configuration (dnsmasq preferred)
2. Create libvirt networks: 1924, 1925, 1926, 1927, 1928
3. Download the VyOS rolling release ISO
4. Create the VyOS VM via virt-install
5. Display instructions and **PAUSE** waiting for manual configuration

### Step 2: Manual VyOS Configuration (via Cockpit Console)

**Access the console:**
1. Open `https://<host-ip>:9090` in a browser
2. Log in with your host credentials
3. Navigate to: Virtual Machines -> vyos-router -> Console

**Install VyOS to disk:**
```
vyos login: vyos
Password: vyos

vyos@vyos:~$ install image
# Accept all defaults:
#   - Partition: Auto
#   - Install to: sda
#   - Image size: (default)
#   - Root password: vyos (or custom)
# Wait for installation to complete

vyos@vyos:~$ poweroff
```

**Restart the VM** (remove ISO):
- In Cockpit: Virtual Machines -> vyos-router -> Start
- Or via CLI: `sudo virsh start vyos-router`

**Configure networking:**
After VM restarts, log in again via console:
```
configure

# Set eth0 (management interface on default network)
set interfaces ethernet eth0 address 192.168.122.2/24
set protocols static route 0.0.0.0/0 next-hop 192.168.122.1

# Set DNS
set system name-server 8.8.8.8

# Enable SSH
set service ssh port 22

commit
save
exit
```

**Verify SSH access from host:**
```bash
ssh vyos@192.168.122.2
# Password: vyos
```

### Step 3: Apply VLAN Configuration

Once SSH is working, the script (or you manually) applies the full VLAN config:

```bash
# If the script is still waiting, press Enter to let it continue
# Otherwise, apply manually:
ssh vyos@192.168.122.2 < ~/vyos-config.sh
```

The VLAN configuration creates interfaces for networks 1924-1928:
- eth1 (VLAN 1924): 192.168.50.1/24
- eth2 (VLAN 1925): 192.168.51.1/24
- eth3 (VLAN 1926): 192.168.52.1/24
- eth4 (VLAN 1927): 192.168.53.1/24
- eth5 (VLAN 1928): 192.168.54.1/24

### Step 4: Verify

```bash
# Ping VyOS management interface
ping -c 3 192.168.122.2

# Verify VLAN networks are active
sudo virsh net-list --all | grep -E "192[4-8]"

# Ping VLAN gateway (from a VM on that network)
ping -c 3 192.168.50.1

# SSH to VyOS and check interfaces
ssh vyos@192.168.122.2 "show interfaces"
```

## Timeline

| Step | Duration | Notes |
|------|----------|-------|
| Script creates networks + VM | 2-5 min | Automated |
| VyOS ISO download | 1-3 min | ~400MB download |
| **Manual: install image** | 3-5 min | Interactive console |
| **Manual: configure network** | 2-3 min | Console commands |
| **Manual: enable SSH** | 1 min | Console |
| Script applies VLAN config | 1 min | Automated (after SSH) |
| **Total** | **10-20 min** | ~8 min manual |

## Validation Criteria

VyOS is fully operational when:
1. `ping 192.168.122.2` succeeds (management interface)
2. `ssh vyos@192.168.122.2` connects successfully
3. `sudo virsh net-list --all` shows networks 1924-1928 as active
4. `ping 192.168.50.1` succeeds from VyOS (VLAN gateway)
5. `./e2e-tests/validate_env.sh` passes the VyOS checks

## Common Failure Modes

| Symptom | Cause | Fix |
|---------|-------|-----|
| Blank/black console in Cockpit | VM booting or display issue | Wait 30s; try "Send key: Ctrl+Alt+Del"; check VM state |
| "vyos login:" never appears | VM failed to boot from ISO | Verify ISO downloaded correctly; check `virsh domblklist vyos-router` |
| Can't poweroff after install | VM stuck | `sudo virsh destroy vyos-router` then `sudo virsh start vyos-router` |
| VM won't start after install | Boot from ISO instead of disk | Remove cdrom: `sudo virsh change-media vyos-router --eject` |
| `install image` fails | Disk not available | Check `lsblk` inside VyOS; ensure VM has a disk attached |
| SSH refused after config | Wrong IP or SSH not enabled | Re-enter console; verify eth0 address and SSH service |
| Script timeout (30 min) | Manual steps not completed | Re-run script; complete manual steps faster |
| Networks 1924-1928 not active | virsh net-define/start failed | `sudo virsh net-start 1924`; check existing conflicts |
| VLAN gateway unreachable | VyOS config not applied | SSH in and run the config commands manually |
| VyOS not pingable at 192.168.122.2 | Wrong network or IP conflict | Check `virsh domiflist vyos-router`; verify on 'default' network |

## Destroying VyOS

To completely remove the VyOS router and networks:

```bash
# Stop and remove VM
sudo virsh destroy vyos-router
sudo virsh undefine vyos-router --remove-all-storage

# Remove networks
for net in 1924 1925 1926 1927 1928; do
    sudo virsh net-destroy $net 2>/dev/null
    sudo virsh net-undefine $net 2>/dev/null
done
```

## Key Files

- `hack/vyos-router.sh` - Main deployment script (creates VM + networks)
- `docs/vyos-manual-configuration.md` - Detailed step-by-step guide with screenshots
- `e2e-tests/bootstrap_env.sh` - Calls vyos-router.sh during full bootstrap
- `e2e-tests/validate_env.sh` - Validates VyOS networks are active
