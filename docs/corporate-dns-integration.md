---
layout: default
title: Corporate DNS Integration
description: Registering OpenShift DNS records in enterprise DNS servers (BIND, Infoblox, Active Directory)
parent: How-to Guides
nav_order: 5
---

# Corporate DNS Integration

OpenShift requires specific DNS records to exist in your DNS infrastructure **before** any cluster node boots. This guide covers how to register those records in common enterprise DNS systems and how to verify them from the deployment host.

For development/KVM environments, use `hack/setup-dnsmasq.sh` and `hack/configure-dnsmasq-entries.sh` instead — this guide is for production environments with a corporate DNS server.

## Required DNS Records

For a cluster named `prod-ocp4` in domain `corp.example.com` with:
- API VIP: `10.0.0.100`
- App VIP: `10.0.0.101`

The following records are **required**:

| Record | Type | Value | Used By |
|--------|------|-------|---------|
| `api.prod-ocp4.corp.example.com` | A | `10.0.0.100` | kubectl, oc, all clients |
| `api-int.prod-ocp4.corp.example.com` | A | `10.0.0.100` | Internal node-to-node API calls |
| `*.apps.prod-ocp4.corp.example.com` | A | `10.0.0.101` | All application routes (wildcard) |

The `api` and `api-int` records point to the **same VIP**. Both must exist separately — the installer checks for both.

**Note on wildcards**: Not all DNS servers support `*.apps.*` wildcard A records equally. See the server-specific sections below for how to register the wildcard.

## Deriving Record Values from cluster.yml

Your `cluster.yml` (in `site-config/<cluster-name>/`) contains all the values you need:

```bash
# Extract values from cluster.yml
CLUSTER=$(grep "^cluster_name:" site-config/<cluster-name>/cluster.yml | awk '{print $2}' | tr -d '"')
DOMAIN=$(grep "^base_domain:" site-config/<cluster-name>/cluster.yml | awk '{print $2}' | tr -d '"')
API_VIP=$(grep -A1 "^api_vips:" site-config/<cluster-name>/cluster.yml | tail -1 | awk '{print $2}' | tr -d '- "')
APP_VIP=$(grep -A1 "^app_vips:" site-config/<cluster-name>/cluster.yml | tail -1 | awk '{print $2}' | tr -d '- "')

echo "Zone: ${CLUSTER}.${DOMAIN}"
echo "api.${CLUSTER}.${DOMAIN}     A  ${API_VIP}"
echo "api-int.${CLUSTER}.${DOMAIN} A  ${API_VIP}"
echo "*.apps.${CLUSTER}.${DOMAIN}  A  ${APP_VIP}"
```

---

## BIND / named

### Add Records to Zone File

Edit your zone file (typically `/var/named/<domain>.db` or `/etc/bind/zones/<domain>`):

```bind
; OpenShift cluster: prod-ocp4
api.prod-ocp4          IN  A    10.0.0.100
api-int.prod-ocp4      IN  A    10.0.0.100
*.apps.prod-ocp4       IN  A    10.0.0.101
```

### Reload BIND

```bash
# Check zone file syntax
named-checkzone corp.example.com /var/named/corp.example.com.db

# Reload without restart (preserves cache)
sudo rndc reload corp.example.com

# Or full reload
sudo systemctl reload named
```

### Verify

```bash
dig @<bind-server-ip> api.prod-ocp4.corp.example.com
dig @<bind-server-ip> api-int.prod-ocp4.corp.example.com
dig @<bind-server-ip> console-openshift-console.apps.prod-ocp4.corp.example.com
```

### BIND Wildcard Note

BIND fully supports `*.apps.prod-ocp4` wildcard A records. If your zone file uses `$ORIGIN`, write:

```bind
$ORIGIN prod-ocp4.corp.example.com.
api              IN  A    10.0.0.100
api-int          IN  A    10.0.0.100
*.apps           IN  A    10.0.0.101
```

---

## Infoblox

### Via Web UI

1. Log in to the Infoblox Grid Manager
2. Navigate to **Data Management → DNS → Zones**
3. Select your zone (`corp.example.com`)
4. Click **Add → A Record**

Add these records:

| Name | Type | IP Address |
|------|------|-----------|
| `api.prod-ocp4` | A | `10.0.0.100` |
| `api-int.prod-ocp4` | A | `10.0.0.100` |
| `*.apps.prod-ocp4` | A | `10.0.0.101` |

Click **Save & Close** after each record. Then click **Deploy** in the toolbar to push changes to DNS members.

### Via Infoblox REST API (WAPI)

```bash
INFOBLOX_HOST="infoblox.corp.example.com"
INFOBLOX_USER="admin"
INFOBLOX_PASS="${INFOBLOX_PASSWORD}"  # export before running
ZONE="corp.example.com"
CLUSTER="prod-ocp4"
API_VIP="10.0.0.100"
APP_VIP="10.0.0.101"

# api record
curl -sk -u "${INFOBLOX_USER}:${INFOBLOX_PASS}" \
  -X POST "https://${INFOBLOX_HOST}/wapi/v2.10/record:a" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"api.${CLUSTER}.${ZONE}\",\"ipv4addr\":\"${API_VIP}\"}"

# api-int record
curl -sk -u "${INFOBLOX_USER}:${INFOBLOX_PASS}" \
  -X POST "https://${INFOBLOX_HOST}/wapi/v2.10/record:a" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"api-int.${CLUSTER}.${ZONE}\",\"ipv4addr\":\"${API_VIP}\"}"

# wildcard apps record
curl -sk -u "${INFOBLOX_USER}:${INFOBLOX_PASS}" \
  -X POST "https://${INFOBLOX_HOST}/wapi/v2.10/record:a" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"*.apps.${CLUSTER}.${ZONE}\",\"ipv4addr\":\"${APP_VIP}\"}"
```

### Infoblox Wildcard Note

Infoblox supports wildcard A records natively. The `*.apps.prod-ocp4.corp.example.com` entry above creates a proper wildcard. After creation, verify the wildcard resolves:

```bash
dig @<infoblox-member-ip> anyrandomapp.apps.prod-ocp4.corp.example.com
```

---

## Windows / Active Directory DNS

### Via PowerShell (Remote or on DNS Server)

```powershell
$Zone    = "corp.example.com"
$Cluster = "prod-ocp4"
$ApiVip  = "10.0.0.100"
$AppVip  = "10.0.0.101"

# api record
Add-DnsServerResourceRecordA -ZoneName $Zone `
  -Name "api.$Cluster" -IPv4Address $ApiVip -TimeToLive 00:05:00

# api-int record
Add-DnsServerResourceRecordA -ZoneName $Zone `
  -Name "api-int.$Cluster" -IPv4Address $ApiVip -TimeToLive 00:05:00

# apps wildcard — AD DNS supports wildcard A records
Add-DnsServerResourceRecordA -ZoneName $Zone `
  -Name "*.apps.$Cluster" -IPv4Address $AppVip -TimeToLive 00:05:00
```

If running remotely, add `-ComputerName <dns-server-fqdn>` to each command.

### Via dnscmd (Legacy / Non-PowerShell)

```cmd
dnscmd <dns-server> /recordadd corp.example.com api.prod-ocp4 A 10.0.0.100
dnscmd <dns-server> /recordadd corp.example.com api-int.prod-ocp4 A 10.0.0.100
dnscmd <dns-server> /recordadd corp.example.com *.apps.prod-ocp4 A 10.0.0.101
```

### AD DNS Wildcard Note

Active Directory DNS **does** support wildcard A records but the behavior can depend on the forest/domain functional level and DNS server version. If wildcards do not resolve, register explicit records for each known app hostname:

```powershell
$apps = @(
  "console-openshift-console",
  "oauth-openshift",
  "grafana-openshift-monitoring",
  "prometheus-k8s-openshift-monitoring",
  "alertmanager-main-openshift-monitoring",
  "thanos-querier-openshift-monitoring",
  "downloads-openshift-console"
)
foreach ($app in $apps) {
  Add-DnsServerResourceRecordA -ZoneName $Zone `
    -Name "$app.apps.$Cluster" -IPv4Address $AppVip -TimeToLive 00:05:00
}
```

---

## Development vs Production DNS Comparison

| Feature | dnsmasq (Development) | Corporate DNS (Production) |
|---------|----------------------|--------------------------|
| Setup script | `hack/setup-dnsmasq.sh` | Manual (see above) |
| Add records | `hack/configure-dnsmasq-entries.sh add` | Zone file / API / PowerShell |
| Wildcard support | Partial (pre-defined routes only) | Full wildcard A record |
| Scope | Deployment host only | Network-wide |
| Persistence | `systemd` service | Native DNS infrastructure |
| Verification | `hack/verify-dns-resolution.sh` | `dig @<server-ip> <record>` |

---

## Verification from the Deployment Host

After registering records, verify from the machine that will run `create-iso.sh`:

```bash
# Set variables from your cluster.yml
DNS_SERVER="10.0.0.53"    # your corporate DNS server
CLUSTER="prod-ocp4.corp.example.com"

echo "Testing DNS records..."
for record in api api-int; do
  result=$(dig +short @${DNS_SERVER} ${record}.${CLUSTER})
  echo "  ${record}.${CLUSTER} → ${result:-FAILED}"
done

# Test wildcard (two different hostnames)
for app in console-openshift-console oauth-openshift test; do
  result=$(dig +short @${DNS_SERVER} ${app}.apps.${CLUSTER})
  echo "  ${app}.apps.${CLUSTER} → ${result:-FAILED}"
done
```

All records must return valid IPs before proceeding to ISO generation.

---

## Troubleshooting

### Records not resolving

```bash
# Check if record exists on the authoritative server
dig +short @<authoritative-ns> api.prod-ocp4.corp.example.com

# Find the authoritative nameserver for the zone
dig NS corp.example.com

# Check TTL — new records may take seconds to minutes to propagate
dig +ttl @<server> api.prod-ocp4.corp.example.com
```

### Wildcard not matching

```bash
# Test with a random subdomain
dig +short @<server> xyzrandom.apps.prod-ocp4.corp.example.com

# If this fails but explicit records resolve, the DNS server may not support wildcards
# Add explicit records for each app route (see AD DNS section above)
```

### Split-horizon DNS

If your corporate DNS returns different answers depending on the client's network location (split-horizon), ensure the cluster nodes and the deployment host are on the **same DNS view**. OpenShift nodes must be able to resolve `api.*` and `*.apps.*` from inside the cluster network.

---

## Related Documentation

- [Fork & Adapt Checklist](fork-and-adapt-checklist) — Step 7: Corporate DNS registration
- [Bare Metal Production Guide](bare-metal-production-guide) — Phase 2: DNS registration
- [DNS Setup Guide](dns-setup) — dnsmasq for development environments
- [DNS Troubleshooting](dns-troubleshooting) — Common DNS resolution issues
- [Verify DNS Resolution Script](../hack/verify-dns-resolution.sh) — dnsmasq-specific verification (development only)
