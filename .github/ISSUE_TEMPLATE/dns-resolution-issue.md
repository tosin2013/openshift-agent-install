---
name: DNS Resolution Issue
about: DNS not resolving for OpenShift cluster (api.*, *.apps.*)
title: '[DNS] DNS resolution failing for cluster'
labels: 'bug, dns, help wanted'
assignees: ''
---

## DNS Resolution Issue

**Symptom**: DNS names for my OpenShift cluster are not resolving:
- `api.<cluster>.<domain>` not resolving
- `*.apps.<cluster>.<domain>` not resolving
- OpenShift installation hangs or fails during bootstrap

**Environment**:
- **DNS Method**: [ ] dnsmasq (recommended) / [ ] FreeIPA (legacy) / [ ] Other
- **Deployment Type**: [ ] SNO / [ ] 3-Node / [ ] HA
- **Platform**: [ ] KVM / [ ] vSphere / [ ] Bare Metal / [ ] Other
- **RHEL Version**: [ ] 8 / [ ] 9 / [ ] 10

## Quick Diagnosis

Run the DNS verification script:
```bash
./hack/verify-dns-resolution.sh examples/<your-cluster>/cluster.yml
```

Paste the output here:
```
# Paste verify-dns-resolution.sh output
```

## Common Causes & Solutions

### 1. dnsmasq OpenShift configuration file missing

**Symptom**: 
```
✗ dnsmasq OpenShift configuration not found at /etc/dnsmasq.d/openshift.conf
```

**Solution**:
```bash
sudo ./hack/setup-dnsmasq.sh
```

### 2. DNS entries not added for your cluster

**Symptom**: All DNS tests fail (❌ NOT RESOLVED)

**Solution**:
```bash
sudo ./hack/configure-dnsmasq-entries.sh add examples/<your-cluster>/cluster.yml
./hack/verify-dns-resolution.sh examples/<your-cluster>/cluster.yml
```

### 3. IPv6 connection refused warnings (cosmetic issue)

**Symptom**:
```
⚠️  ;; communications error to ::1#53: connection refused
192.168.100.50 (expected: 192.168.100.50)
```

**Analysis**: This is a cosmetic warning because `dig` tries IPv6 (::1) first, gets refused, then falls back to IPv4 (localhost) and succeeds. **DNS is actually working** if you see the correct IP address.

**Solution (optional - suppress warnings)**:
```bash
# Test with IPv4 only
dig -4 @localhost api.<cluster>.<domain>

# Or update verify-dns-resolution.sh to use -4 flag
```

### 4. Host not using dnsmasq as DNS server

**Symptom**: DNS works with `dig @localhost` but not with plain `dig` or `ping`

**Check current DNS**:
```bash
cat /etc/resolv.conf
nmcli -g ipv4.dns connection show "$(nmcli -t -f NAME connection show --active | grep -v 'lo\|virbr' | head -1 | cut -d: -f1)"
```

**Solution**:
```bash
PRIMARY_CONN="$(nmcli -t -f NAME connection show --active | grep -v 'lo\|virbr' | head -1 | cut -d: -f1)"
sudo nmcli connection modify "$PRIMARY_CONN" ipv4.dns "127.0.0.1"
sudo nmcli connection up "$PRIMARY_CONN"
```

### 5. dnsmasq not running

**Check status**:
```bash
systemctl status dnsmasq
```

**Solution**:
```bash
sudo systemctl restart dnsmasq
sudo systemctl enable dnsmasq
```

### 6. VyOS router deployed without dnsmasq setup

**Symptom**: VyOS router created networks (1924-1928) but DNS not configured

**Root Cause**: In older versions, `vyos-router.sh` required FreeIPA. Now modernized to use dnsmasq.

**Solution**:
```bash
# Setup dnsmasq first
sudo ./hack/setup-dnsmasq.sh

# Add DNS entries
sudo ./hack/configure-dnsmasq-entries.sh add examples/<your-cluster>/cluster.yml

# Verify
./hack/verify-dns-resolution.sh examples/<your-cluster>/cluster.yml
```

## Additional Context

**What changed?**
- [ ] Fresh installation
- [ ] Was working, now broken
- [ ] Migrating from FreeIPA to dnsmasq
- [ ] Other: ___________

**DNS configuration files**:
```bash
# Check dnsmasq config
sudo cat /etc/dnsmasq.d/openshift.conf

# Check if entries exist for your cluster
sudo cat /etc/dnsmasq.d/openshift.conf | grep "<cluster-name>"

# Check resolv.conf
cat /etc/resolv.conf
```

Paste output here:
```
# Paste command output
```

## Expected Behavior

All 5 DNS tests should pass (✅):
```
1. API endpoint (api.<cluster>.<domain>): ✅ <IP>
2. Internal API (api-int.<cluster>.<domain>): ✅ <IP>
3. Console (console-openshift-console.apps.<cluster>.<domain>): ✅ <IP>
4. OAuth (oauth-openshift.apps.<cluster>.<domain>): ✅ <IP>
5. Generic apps (test.apps.<cluster>.<domain>): ✅ <IP>
```

## Related Documentation

- [DNS Automation Guide](../../DNS_AUTOMATION.md)
- [ADR-019: Automated DNS Configuration](../../docs/adr/0019-automated-dns-configuration-dnsmasq.md)
- [Developer Guide - DNS Setup](../../docs/developer-guide.md#dns-configuration)
- [Quick Start - DNS Prerequisites](../../docs/index.md#dns-prerequisites)

## Additional Notes

<!-- Add any other relevant information -->
