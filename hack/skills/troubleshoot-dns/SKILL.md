---
name: Troubleshoot DNS Resolution
description: Diagnose and fix DNS issues that block OpenShift cluster deployment or access
triggers:
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
---

# Troubleshoot DNS Resolution

## When to Use This Skill

Activate when:
- `hack/verify-dns-resolution.sh` fails
- `dig api.<cluster>.<domain>` returns NXDOMAIN
- Deployment fails at DNS verification phase
- Cluster was working but is now unreachable by name
- Nodes report "unable to resolve host" during installation
- User reports "connection refused" when accessing the cluster

## Diagnostic Decision Tree

```
DNS not resolving
├── Is dnsmasq running?
│   ├── NO → Step 1: Fix dnsmasq service
│   └── YES → Are entries configured?
│       ├── NO → Step 2: Add DNS entries
│       └── YES → Does dig @localhost work?
│           ├── NO → Step 3: Fix dnsmasq config
│           └── YES → Does dig (without @) work?
│               ├── NO → Step 4: Fix host DNS resolution
│               └── YES → Can nodes resolve?
│                   ├── NO → Step 5: Fix node DNS config
│                   └── YES → Problem is elsewhere
```

## Step 1: Verify dnsmasq is Running

```bash
sudo systemctl status dnsmasq
```

**If not running:**
```bash
# Check for errors
sudo journalctl -u dnsmasq --no-pager -n 20

# Common fix: port 53 conflict with systemd-resolved
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved
sudo rm /etc/resolv.conf
echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf

# Start dnsmasq
sudo systemctl start dnsmasq
sudo systemctl enable dnsmasq
```

**If it won't start (port conflict):**
```bash
# Find what's on port 53
sudo ss -tlnp | grep :53

# If systemd-resolved:
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved

# If another dnsmasq instance (libvirt):
# This is OK - libvirt runs its own dnsmasq on virbr0
# The system dnsmasq should bind to lo/primary interface
```

## Step 2: Verify DNS Entries Exist

```bash
# List configured entries
sudo ./hack/configure-dnsmasq-entries.sh list

# Or check the config file directly
sudo grep -i "<cluster-name>" /etc/dnsmasq.d/openshift.conf
```

**If entries are missing:**
```bash
sudo ./hack/configure-dnsmasq-entries.sh add examples/<cluster>/cluster.yml
```

**Verify the entry format in `/etc/dnsmasq.d/openshift.conf`:**
```
# Expected format:
address=/api.<cluster>.<domain>/<api-vip>
address=/api-int.<cluster>.<domain>/<api-vip>
address=/console-openshift-console.apps.<cluster>.<domain>/<app-vip>
address=/oauth-openshift.apps.<cluster>.<domain>/<app-vip>
# ... more app routes
```

## Step 3: Test Resolution via dnsmasq Directly

```bash
# Query dnsmasq on localhost
dig @localhost api.<cluster>.<domain>
dig @127.0.0.1 api.<cluster>.<domain>

# Query libvirt dnsmasq (192.168.122.1)
dig @192.168.122.1 api.<cluster>.<domain>
```

**If @localhost fails but entries exist:**
```bash
# Restart dnsmasq to reload config
sudo systemctl restart dnsmasq

# Check for syntax errors
sudo dnsmasq --test
# Should output: "dnsmasq: syntax check OK"

# Check dnsmasq is listening on expected interface
sudo ss -tlnp | grep dnsmasq
```

**If @192.168.122.1 works but @localhost doesn't:**
- The entries might be in libvirt's dnsmasq, not the system dnsmasq
- This is fine for VM resolution but the host needs different config

## Step 4: Fix Host DNS Resolution Path

The host must use dnsmasq (localhost) as its DNS:

```bash
# Check what DNS the host is using
cat /etc/resolv.conf

# If it shows something other than 127.0.0.1:
# Find your primary NetworkManager connection
nmcli connection show --active

# Set DNS to localhost (dnsmasq)
PRIMARY_CONN="<your-connection-name>"
sudo nmcli connection modify "$PRIMARY_CONN" ipv4.dns "127.0.0.1"
sudo nmcli connection modify "$PRIMARY_CONN" ipv4.dns-priority -1
sudo nmcli connection up "$PRIMARY_CONN"

# Verify
cat /etc/resolv.conf
# Should show: nameserver 127.0.0.1

# Test
dig api.<cluster>.<domain>
```

**Alternative: Configure dnsmasq as upstream for NetworkManager:**
```bash
# Create NM dnsmasq config
echo "server=8.8.8.8" | sudo tee /etc/NetworkManager/dnsmasq.d/upstream.conf
sudo systemctl restart NetworkManager
```

## Step 5: Fix Node DNS (During Installation)

If nodes can't resolve during cluster bootstrap:

**Check the node's `networkConfig` in nodes.yml:**
```yaml
networkConfig:
  dns-resolver:
    config:
      server:
        - 192.168.122.1    # Must point to libvirt dnsmasq for KVM
        # - <corporate-dns>  # For bare metal
```

**For KVM deployments:** nodes should use `192.168.122.1` (libvirt network's dnsmasq)

**For bare metal:** nodes should use the corporate DNS server that has the cluster records

**If nodes are already deployed and DNS is wrong:**
- The installation will likely fail; you need to destroy and redeploy with corrected networkConfig

## Step 6: Libvirt Network DNS (Alternative to dnsmasq)

For KVM deployments, DNS entries can also live in libvirt's network:

```bash
# Check libvirt DNS entries
sudo virsh net-dumpxml default | grep -A 5 "<dns>"

# Add entries directly to libvirt (if not using system dnsmasq)
sudo virsh net-update default add dns-host \
  "<host ip='192.168.50.5'><hostname>api.<cluster>.<domain></hostname></host>" \
  --live --config
```

## Quick Fix Script

For common DNS issues on KVM:

```bash
# Nuclear option: reconfigure everything
sudo ./hack/setup-dnsmasq.sh
sudo ./hack/configure-dnsmasq-entries.sh add examples/<cluster>/cluster.yml

# Verify
./hack/verify-dns-resolution.sh examples/<cluster>/cluster.yml
```

## Verification Commands

```bash
# Full verification suite
./hack/verify-dns-resolution.sh examples/<cluster>/cluster.yml

# Manual checks
dig @localhost api.<cluster>.<domain>              # System dnsmasq
dig @192.168.122.1 api.<cluster>.<domain>          # Libvirt dnsmasq
dig api.<cluster>.<domain>                          # Host default resolution
dig +short api.<cluster>.<domain>                   # Just the IP

# From a cluster node (via virsh console)
dig api.<cluster>.<domain> @192.168.122.1

# Verify upstream resolution still works
dig google.com
dig google.com @8.8.8.8
```

## Common Root Causes Summary

| Root Cause | Symptom | One-Line Fix |
|-----------|---------|--------------|
| dnsmasq not installed | "dnsmasq: command not found" | `sudo ./hack/setup-dnsmasq.sh` |
| dnsmasq not running | systemctl shows inactive | `sudo systemctl start dnsmasq` |
| Port 53 conflict | "address already in use" | Disable systemd-resolved |
| Entries not added | dig @localhost returns NXDOMAIN | `sudo ./hack/configure-dnsmasq-entries.sh add <cluster.yml>` |
| Config syntax error | dnsmasq won't restart | `sudo dnsmasq --test`; fix syntax |
| Host not using dnsmasq | dig works with @localhost but not without | Fix NetworkManager DNS to 127.0.0.1 |
| Wrong DNS in node config | Node can't resolve during install | Fix `dns-resolver.config.server` in nodes.yml |
| Stale entries | Old cluster entries conflict | `sudo ./hack/configure-dnsmasq-entries.sh remove <name> <domain>` |
| Libvirt dnsmasq vs system | Works on @192.168.122.1 but not @localhost | Entries in wrong dnsmasq instance |
| Wildcard not supported | Specific app routes fail | Libvirt doesn't do wildcards; add explicit routes |

## Key Files

- `hack/verify-dns-resolution.sh` - Automated DNS verification (5 tests)
- `hack/configure-dnsmasq-entries.sh` - Add/remove/list DNS entries
- `hack/setup-dnsmasq.sh` - Install and configure dnsmasq
- `hack/fix-kvm-dns.sh` - Batch-fix DNS server references in examples
- `/etc/dnsmasq.d/openshift.conf` - Where cluster DNS entries live
- `/etc/resolv.conf` - Host's active DNS configuration
- `docs/dns-troubleshooting.md` - Extended documentation
- `docs/dns-setup.md` - Initial DNS setup guide
- `DNS_AUTOMATION.md` - How deploy-on-kvm.sh manages DNS automatically
