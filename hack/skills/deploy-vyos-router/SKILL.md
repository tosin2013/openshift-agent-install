---
name: deploy-vyos-router
description: Deploy VyOS virtual router for VLAN networking in KVM lab (requires manual Cockpit console configuration)
compatibility: "RHEL 9.x or 10.x host. OpenShift 4.15-4.22 and 5.x. Requires: libvirt, ansible-core, yq, openshift-install CLI."
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

### Quick Diagnostics (run first)

```bash
# Check if VyOS router is already deployed
virsh list --all 2>/dev/null | grep -i vyos || echo "No vyos VM found"

# Check if VLAN networks exist
virsh net-list --all 2>/dev/null | grep -E "1924|1925|1926|1927|1928" || echo "VLAN networks not found"

# Check Cockpit credentials
cat ~/cockpit-credentials.txt 2>/dev/null || echo "cockpit-credentials.txt not found"

# Host IP for Cockpit access
ip -4 addr show | grep -v "127.0.0.1" | grep "inet " | awk '{print $2}' | head -3
```

**DNS check — must resolve before proceeding:**

Ask the user which DNS approach they are using:

> **Option A: dnsmasq (recommended for new deployments)**
> ```bash
> sudo systemctl is-active dnsmasq && echo "dnsmasq: OK" || echo "dnsmasq: NOT RUNNING — run: sudo ./hack/setup-dnsmasq.sh"
> # Verify DNS_FORWARDER will be set correctly
> # dnsmasq must listen on 192.168.122.1 for cluster name resolution
> sudo ss -ulnp | grep :53
> grep "^nameserver" /etc/resolv.conf
> ```
> The `DNS_FORWARDER` is read from `/etc/resolv.conf`. On cloud instances (IBM Cloud, AWS),
> this may be a public cloud DNS IP — **not** `192.168.122.1`. If so, fix it before deploying:
> ```bash
> # Verify NetworkManager is routing DNS through the local dnsmasq
> nmcli conn show $(nmcli -t -f NAME conn show --active | head -1) | grep ipv4.dns
> # If DNS is not 127.0.0.1 or 192.168.122.1, reconfigure:
> sudo nmcli conn mod <connection-name> ipv4.dns "192.168.122.1"
> sudo nmcli conn up <connection-name>
> ```

> **Option B: FreeIPA (legacy, deprecated)**
> ```bash
> ls ~/hack/freeipa_vars.sh 2>/dev/null && echo "FreeIPA vars found" || echo "FreeIPA not configured"
> ```
> Not recommended for new deployments. Use dnsmasq (Option A) instead.

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

vyos@vyos:~$ reboot
```

> **`reboot` not `poweroff`** — VyOS must restart to boot from the installed disk. The deployment script is still waiting and will detect VyOS once SSH becomes available after reboot.

**Configure networking:**
After reboot, log in again via console (login: `vyos` / password you set):
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

Once SSH is working, **the deployment script auto-detects VyOS and applies the config automatically** via SCP + `vbash` (VyOS's shell). You do not need to do anything — just wait.

If the script already timed out (30 min wait expired), apply manually:

```bash
# 1. Copy the config script to VyOS
scp ~/vyos-config.sh vyos@192.168.122.2:/tmp/

# 2. SSH in and run it with vbash (NOT bash — VyOS requires its own shell)
ssh vyos@192.168.122.2
chmod +x /tmp/vyos-config.sh
vbash /tmp/vyos-config.sh
exit
```

> **Must use `vbash`** — running `vyos-config.sh` with standard `bash` or `sh` will silently fail because `set`, `commit`, `save` are VyOS built-ins only available in `vbash`.

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

## IBM Cloud Notes

If deploying on **IBM Cloud bare metal**, the VyOS router setup is the same, but after cluster deployment you will need IBM Cloud-specific steps for external access:

- HAProxy must bind to `0.0.0.0` (not the private IP) due to IBM Cloud NAT
- Route 53 DNS records must point to the **public floating IP**, not the private IP
- Two firewall layers: `firewalld` (local) AND IBM Cloud firewall (console)

Full IBM Cloud deployment guide: **https://tosin2013.github.io/openshift-agent-install/ibm-cloud-deployment.html**

Detect if running on IBM Cloud:
```bash
# IBM Cloud instances have a public floating IP separate from the private interface
# Private IP on eth0 / ens3
ip -4 addr show | grep "inet " | grep -v "127.0.0.1"
# Public floating IP (check IBM Cloud console or metadata)
curl -s --max-time 3 http://169.254.169.254/metadata/v1/instance 2>/dev/null | python3 -m json.tool 2>/dev/null | grep "public_ip" || echo "Not IBM Cloud metadata or not reachable"
```

## Key Files

- `hack/vyos-router.sh` - Main deployment script (creates VM + networks)
- `docs/vyos-manual-configuration.md` - Detailed step-by-step guide with screenshots
- `e2e-tests/bootstrap_env.sh` - Calls vyos-router.sh during full bootstrap
- `e2e-tests/validate_env.sh` - Validates VyOS networks are active
- IBM Cloud guide: https://tosin2013.github.io/openshift-agent-install/ibm-cloud-deployment.html
