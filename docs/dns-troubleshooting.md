---
layout: default
title: "DNS Troubleshooting Guide"
parent: Testing & Validation
nav_order: 5
---

# DNS Troubleshooting Guide

## Quick Fix - Most Common Issue ⚡

**Problem**: DNS not resolving after VyOS router deployment

**Root Cause**: dnsmasq configuration file not created before adding DNS entries

**Solution** (run in order):
```bash
# 1. Create dnsmasq config file (REQUIRED FIRST)
sudo ./hack/setup-dnsmasq.sh

# 2. Add DNS entries for your cluster
sudo ./hack/configure-dnsmasq-entries.sh add examples/<your-cluster>/cluster.yml

# 3. Verify DNS works
./hack/verify-dns-resolution.sh examples/<your-cluster>/cluster.yml
```

**Expected Output**: All 5 tests pass ✅

---

## Complete DNS Diagnostic Workflow

### Step 1: Run DNS Verification

```bash
./hack/verify-dns-resolution.sh examples/<your-cluster>/cluster.yml
```

### Step 2: Interpret Results

#### ✅ All 5 tests pass
- **Status**: DNS working correctly
- **Action**: Proceed with deployment

#### ❌ Error: "dnsmasq OpenShift configuration not found"
- **Status**: Initial setup not done
- **Action**: Run `sudo ./hack/setup-dnsmasq.sh`

#### ❌ All tests show "NOT RESOLVED"
- **Status**: DNS entries not added
- **Action**: Run `sudo ./hack/configure-dnsmasq-entries.sh add <cluster.yml>`

#### ⚠️ IPv6 warnings but IPs resolve correctly
- **Status**: Cosmetic issue, DNS actually works
- **Explanation**: `dig` tries IPv6 first, gets refused, falls back to IPv4 successfully
- **Action**: No action needed (optional: use `dig -4` to suppress warnings)

### Step 3: Verify Host DNS Configuration

```bash
# Check system DNS
cat /etc/resolv.conf

# Should contain: nameserver 127.0.0.1 (or 192.168.122.1)
```

If localhost not in resolv.conf:
```bash
PRIMARY_CONN="$(nmcli -t -f NAME connection show --active | grep -v 'lo\|virbr' | head -1 | cut -d: -f1)"
sudo nmcli connection modify "$PRIMARY_CONN" ipv4.dns "127.0.0.1"
sudo nmcli connection up "$PRIMARY_CONN"
```

---

## Common Scenarios

### Scenario 1: Fresh Installation

**Workflow**:
```bash
# 1. Bootstrap environment (installs dnsmasq)
sudo ./e2e-tests/bootstrap_env.sh

# 2. Setup dnsmasq config
sudo ./hack/setup-dnsmasq.sh

# 3. Deploy VyOS router (creates networks)
ACTION=create ./hack/vyos-router.sh

# 4. Add DNS entries
sudo ./hack/configure-dnsmasq-entries.sh add examples/<cluster>/cluster.yml

# 5. Verify DNS
./hack/verify-dns-resolution.sh examples/<cluster>/cluster.yml
```

### Scenario 2: Migrating from FreeIPA to dnsmasq

**Why migrate?**
- ✅ Lighter weight (dnsmasq ~1MB vs FreeIPA ~500MB)
- ✅ Faster deployment (seconds vs minutes)
- ✅ Simpler to troubleshoot
- ✅ No external VM required

**Migration steps**:
```bash
# 1. Install dnsmasq
sudo ./hack/setup-dnsmasq.sh

# 2. Add DNS entries (same as FreeIPA workflow)
sudo ./hack/configure-dnsmasq-entries.sh add examples/<cluster>/cluster.yml

# 3. Verify
./hack/verify-dns-resolution.sh examples/<cluster>/cluster.yml

# 4. Optional: Remove FreeIPA if no longer needed
# ./hack/destroy-freeipa.sh
```

### Scenario 3: Multiple Clusters

```bash
# Add DNS for first cluster
sudo ./hack/configure-dnsmasq-entries.sh add examples/cluster1/cluster.yml

# Add DNS for second cluster
sudo ./hack/configure-dnsmasq-entries.sh add examples/cluster2/cluster.yml

# List all DNS entries
sudo ./hack/configure-dnsmasq-entries.sh list

# Remove DNS for a cluster
sudo ./hack/configure-dnsmasq-entries.sh remove examples/cluster1/cluster.yml
```

---

## Advanced Troubleshooting

### Check dnsmasq is running

```bash
systemctl status dnsmasq
```

**Fix if not running**:
```bash
sudo systemctl restart dnsmasq
sudo systemctl enable dnsmasq
```

### Check DNS entries exist

```bash
sudo cat /etc/dnsmasq.d/openshift.conf
```

**Should contain** (example):
```
# OpenShift DNS entries managed by configure-dnsmasq-entries.sh

# Cluster: sno-4-20.example.com (Added: 2026-05-28 22:27:58)
address=/api.sno-4-20.example.com/192.168.100.50
address=/api-int.sno-4-20.example.com/192.168.100.50
address=/.apps.sno-4-20.example.com/192.168.100.50
```

### Check dnsmasq logs

```bash
sudo journalctl -u dnsmasq -f
```

### Test DNS manually

```bash
# Test localhost (dnsmasq)
dig @localhost api.<cluster>.<domain>

# Test system DNS (should use localhost via /etc/resolv.conf)
dig api.<cluster>.<domain>

# Test apps wildcard
dig @localhost test.apps.<cluster>.<domain>
dig @localhost console-openshift-console.apps.<cluster>.<domain>
```

### Verify NetworkManager DNS

```bash
# Show primary connection DNS
PRIMARY_CONN="$(nmcli -t -f NAME connection show --active | grep -v 'lo\|virbr' | head -1 | cut -d: -f1)"
nmcli -g ipv4.dns connection show "$PRIMARY_CONN"

# Should show: 127.0.0.1 (or 192.168.122.1)
```

---

## Integration with Deployment Workflow

### Automated DNS (deploy-on-kvm.sh)

The `deploy-on-kvm.sh` script automatically configures DNS if using **libvirt networks** (default network). If using VyOS router with VLAN networks, DNS must be configured manually:

```bash
# Before deployment
sudo ./hack/setup-dnsmasq.sh
sudo ./hack/configure-dnsmasq-entries.sh add <cluster.yml>
./hack/verify-dns-resolution.sh <cluster.yml>

# Then deploy
./hack/create-iso.sh <cluster-name>
./hack/deploy-on-kvm.sh <nodes.yml> --redfish
```

### DNS Cleanup (destroy-on-kvm.sh)

DNS entries are **not** automatically removed by `destroy-on-kvm.sh`. Remove manually:

```bash
# Destroy cluster
./hack/destroy-on-kvm.sh <nodes.yml>

# Remove DNS entries
sudo ./hack/configure-dnsmasq-entries.sh remove <cluster.yml>
```

---

## Known Limitations

### 1. Wildcard DNS Scope

dnsmasq wildcard `/.apps.<domain>/` matches **all subdomains**, not just OpenShift routes:
- `*.apps.sno-4-20.example.com` → works
- `anything.random.apps.sno-4-20.example.com` → also works (may not be desired)

**Workaround**: For production environments requiring strict DNS control, consider:
- Using dedicated DNS zones per cluster
- Implementing DNS filtering at network level
- Using FreeIPA for granular DNS control (legacy, heavier)

### 2. IPv6 Support

Current implementation focuses on IPv4. IPv6 dual-stack support requires:
- Adding AAAA records to dnsmasq config
- Updating verify-dns-resolution.sh to test both A and AAAA
- Configuring IPv6 network in libvirt or VyOS

**Future enhancement**: Track in GitHub issue for IPv6 support

---

## Scripts Reference

| Script | Purpose | When to Run |
|--------|---------|-------------|
| `setup-dnsmasq.sh` | Install and create initial config | Once per host (before first cluster) |
| `configure-dnsmasq-entries.sh` | Add/remove/list DNS entries | Before each cluster deployment |
| `verify-dns-resolution.sh` | Test DNS resolution | After adding entries, before deployment |

---

## FAQ

**Q: Do I need to run setup-dnsmasq.sh for every cluster?**  
A: No, only once per host. It creates `/etc/dnsmasq.d/openshift.conf` which is reused.

**Q: Can I use both dnsmasq and FreeIPA?**  
A: Not recommended. Choose one. dnsmasq is preferred for simplicity.

**Q: Why does dig show IPv6 errors but DNS works?**  
A: `dig` tries IPv6 (::1) first. If no IPv6 listener, it falls back to IPv4 (127.0.0.1) automatically. This is normal behavior.

**Q: How do I check if DNS is the problem during OpenShift installation?**  
A: Look for these symptoms in `openshift-install`:
- Bootstrap hangs at "Waiting for bootstrap to complete"
- Errors mentioning "no such host" or "DNS resolution failed"
- API endpoint not reachable

**Q: Does VyOS router automatically configure DNS?**  
A: No. VyOS creates networks but doesn't configure DNS. You must run `configure-dnsmasq-entries.sh` separately.

**Q: What if I see "connection refused" for all tests?**  
A: dnsmasq is not running. Run `sudo systemctl restart dnsmasq`

---

## Related Documentation

- [DNS Automation Implementation](../DNS_AUTOMATION.md)
- [ADR-019: Automated DNS Configuration](../docs/adr/0019-automated-dns-configuration-dnsmasq.md)
- [Developer Guide - DNS Prerequisites](developer-guide.md#hard-requirement-vyos-router)
- [llm.txt - DNS Configuration](../llm.txt) (search for "DNS")

---

## GitHub Issue Template

If DNS issues persist, open a GitHub issue using the **DNS Resolution Issue** template:

📝 [New DNS Resolution Issue](https://github.com/tosin2013/openshift-agent-install/issues/new?template=dns-resolution-issue.md)

Include output from:
```bash
./hack/verify-dns-resolution.sh <cluster.yml>
sudo cat /etc/dnsmasq.d/openshift.conf
systemctl status dnsmasq
cat /etc/resolv.conf
```
