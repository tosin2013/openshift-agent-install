# IBM Cloud Deployment with Route 53 DNS Integration

**Author**: OpenShift Agent Install Contributors  
**Date**: 2026-05-29  
**Validated**: OpenShift 4.21.16

## Overview

This guide documents deploying OpenShift clusters on IBM Cloud bare metal servers with external access via HAProxy forwarder and AWS Route 53 DNS integration.

**Key Differences from Standard Deployments**:
- IBM Cloud uses **NAT** (public IP maps to private IP)
- HAProxy must bind to `0.0.0.0` (all interfaces) not just the private IP
- Route 53 DNS points to the **public IP**, not the private IP
- IBM Cloud firewall rules required for external access

## Network Architecture

### IBM Cloud NAT

```
Internet (your workstation)
    ↓
169.59.189.20 (IBM Cloud Public IP)
    ↓ [IBM Cloud NAT]
10.241.64.8 (Private IP - eth0)
    ↓ [HAProxy on 0.0.0.0:6443/22623/80/443]
192.168.50.253 (API VIP) / 192.168.50.252 (Ingress VIP)
    ↓
OpenShift Cluster Nodes
```

### Why 0.0.0.0 Binding is Required

**Problem**: If HAProxy binds to `10.241.64.8` only, it won't receive traffic from IBM Cloud's NAT.

**Solution**: Bind to `0.0.0.0` (all interfaces) so HAProxy receives traffic on any IP address.

## Prerequisites

1. **IBM Cloud Bare Metal Server** with:
   - Public IP address (e.g., 169.59.189.20)
   - Private IP on eth0 (e.g., 10.241.64.8)
   - Sufficient resources for OpenShift cluster

2. **AWS Account** with:
   - Route 53 hosted zone for your domain
   - IAM credentials with Route 53 permissions

3. **OpenShift Agent Install** repository cloned

4. **IBM Cloud Firewall Rules** allowing:
   - Port 6443 (Kubernetes API)
   - Port 22623 (Machine Config Server)
   - Port 80 (HTTP)
   - Port 443 (HTTPS)

## Deployment Steps

### 1. Identify Your Network Configuration

```bash
# Find your private IP (eth0)
PRIVATE_IP=$(ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
echo "Private IP: $PRIVATE_IP"

# Find your public IP
PUBLIC_IP=$(curl -s ifconfig.me)
echo "Public IP: $PUBLIC_IP"
```

**Example**:
- Private IP: `10.241.64.8`
- Public IP: `169.59.189.20`

### 2. Deploy OpenShift Cluster

Follow the standard deployment process:

```bash
# Create cluster configuration
cd /path/to/openshift-agent-install

# Use or create site-config with your domain
cp -r examples/ha-4.21-disconnected site-config/my-cluster

# Edit cluster.yml
vim site-config/my-cluster/cluster.yml
# Set base_domain to your Route 53 domain
# Set cluster_name appropriately

# Generate ISO and deploy
./hack/create-iso.sh my-cluster
./hack/deploy-on-kvm.sh site-config/my-cluster/nodes.yml --redfish

# Monitor installation
export KUBECONFIG=~/generated_assets/<cluster-name>/auth/kubeconfig
./bin/openshift-install agent wait-for install-complete --dir ~/generated_assets/<cluster-name>
```

### 3. Configure HAProxy Forwarder for IBM Cloud

**CRITICAL**: HAProxy must bind to `0.0.0.0`, not the private IP.

#### Option A: Using the Script (Recommended)

```bash
# Set EXTERNAL_IP to your PUBLIC IP (not private IP)
export EXTERNAL_IP="169.59.189.20"  # Your IBM Cloud public IP

# Configure HAProxy
./hack/configure-haproxy-forwarder.sh site-config/my-cluster/cluster.yml

# Fix HAProxy to listen on all interfaces (IBM Cloud NAT requirement)
sudo sed -i "s/bind ${PRIVATE_IP}:/bind 0.0.0.0:/g" /etc/haproxy/haproxy.cfg

# Restart HAProxy
sudo systemctl restart haproxy
```

#### Option B: Manual Configuration

Edit `/etc/haproxy/haproxy.cfg`:

```haproxy
# API Server (6443)
frontend api-server
    bind 0.0.0.0:6443  # NOT 10.241.64.8:6443
    mode tcp
    option tcplog
    default_backend api-server-backend

backend api-server-backend
    mode tcp
    balance roundrobin
    server api 192.168.50.253:6443 check

# Machine Config Server (22623)
frontend machine-config-server
    bind 0.0.0.0:22623  # NOT 10.241.64.8:22623
    mode tcp
    option tcplog
    default_backend machine-config-server-backend

backend machine-config-server-backend
    mode tcp
    balance roundrobin
    server mcs 192.168.50.253:22623 check

# HTTP Ingress (80)
frontend http-ingress
    bind 0.0.0.0:80  # NOT 10.241.64.8:80
    mode tcp
    option tcplog
    default_backend http-ingress-backend

backend http-ingress-backend
    mode tcp
    balance roundrobin
    server ingress-http 192.168.50.252:80 check

# HTTPS Ingress (443)
frontend https-ingress
    bind 0.0.0.0:443  # NOT 10.241.64.8:443
    mode tcp
    option tcplog
    default_backend https-ingress-backend

backend https-ingress-backend
    mode tcp
    balance roundrobin
    server ingress-https 192.168.50.252:443 check
```

**Restart HAProxy**:
```bash
sudo systemctl restart haproxy
sudo systemctl status haproxy
```

### 4. Verify HAProxy Binding

```bash
# Should show 0.0.0.0:6443, 0.0.0.0:22623, 0.0.0.0:80, 0.0.0.0:443
sudo ss -tlnp | grep haproxy
```

**Expected output**:
```
LISTEN 0  3000  0.0.0.0:6443   0.0.0.0:*  users:(("haproxy",pid=XXXXX,fd=7))
LISTEN 0  3000  0.0.0.0:22623  0.0.0.0:*  users:(("haproxy",pid=XXXXX,fd=8))
LISTEN 0  3000  0.0.0.0:80     0.0.0.0:*  users:(("haproxy",pid=XXXXX,fd=9))
LISTEN 0  3000  0.0.0.0:443    0.0.0.0:*  users:(("haproxy",pid=XXXXX,fd=10))
```

### 5. Configure Route 53 DNS

**IMPORTANT**: Use your **PUBLIC IP**, not the private IP.

```bash
# Set EXTERNAL_IP to your PUBLIC IP
export EXTERNAL_IP="169.59.189.20"  # IBM Cloud public IP

# Configure Route 53 DNS
./hack/configure-route53-dns.sh add site-config/my-cluster/cluster.yml
```

This creates DNS records:
- `api.<cluster>.<domain>` → 169.59.189.20
- `api-int.<cluster>.<domain>` → 169.59.189.20
- `*.apps.<cluster>.<domain>` → 169.59.189.20

### 6. Verify DNS Propagation

```bash
# Test from external DNS (not local dnsmasq)
dig @8.8.8.8 api.<cluster-name>.<domain> +short
# Should return: 169.59.189.20

dig @8.8.8.8 console-openshift-console.apps.<cluster-name>.<domain> +short
# Should return: 169.59.189.20
```

### 7. Configure Local Firewall (CRITICAL)

**RHEL/Fedora systems run firewalld by default** - you must open the HAProxy ports:

```bash
# Add HAProxy ports to firewalld
sudo firewall-cmd --permanent --add-port=6443/tcp   # Kubernetes API
sudo firewall-cmd --permanent --add-port=22623/tcp  # Machine Config Server
sudo firewall-cmd --permanent --add-port=80/tcp     # HTTP Ingress
sudo firewall-cmd --permanent --add-port=443/tcp    # HTTPS Ingress
sudo firewall-cmd --permanent --add-port=8404/tcp   # HAProxy Stats (optional)

# Reload firewall rules
sudo firewall-cmd --reload

# Verify rules are active
sudo firewall-cmd --list-all
```

**Expected output** should include:
```
ports: 6443/tcp 22623/tcp 80/tcp 443/tcp 8404/tcp
```

### 8. Verify External Access

**From your workstation (Mac/Linux/Windows)**:

```bash
# Test API access
curl -k https://api.<cluster-name>.<domain>:6443/version

# Expected output: {"major":"1","minor":"34",...}
```

**From your browser**:
```
https://console-openshift-console.apps.<cluster-name>.<domain>
```

You should see the OpenShift login page!

## Firewall Configuration (TWO Layers)

### Layer 1: Local Firewall (firewalld)

**CRITICAL**: RHEL/Fedora systems have firewalld enabled by default. You **MUST** open ports before external access works.

```bash
# Check if firewalld is running
systemctl status firewalld

# Add all required ports
sudo firewall-cmd --permanent --add-port=6443/tcp
sudo firewall-cmd --permanent --add-port=22623/tcp
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --permanent --add-port=8404/tcp  # HAProxy stats (optional)

# Apply changes
sudo firewall-cmd --reload

# Verify
sudo firewall-cmd --list-all | grep ports
```

### Layer 2: IBM Cloud Firewall

Ensure these ports are also open in your IBM Cloud firewall rules:

| Port | Protocol | Service | Required |
|------|----------|---------|----------|
| 6443 | TCP | Kubernetes API | Yes |
| 22623 | TCP | Machine Config Server | Yes |
| 80 | TCP | HTTP Ingress | Yes |
| 443 | TCP | HTTPS Ingress | Yes |
| 22 | TCP | SSH (management) | Recommended |

**How to configure**:
1. Log into IBM Cloud Console
2. Navigate to: Classic Infrastructure → Devices → Your Server
3. Click "Firewall" tab
4. Add rules for ports 6443, 22623, 80, 443

## Troubleshooting

### Problem: Can't Access Console from Workstation

**Symptoms**:
- DNS resolves correctly (`dig` shows public IP)
- But `curl` to console times out

**Diagnosis**:
```bash
# On the IBM Cloud server
sudo ss -tlnp | grep haproxy
```

**If you see** `10.241.64.8:6443` instead of `0.0.0.0:6443`:
```bash
# HAProxy is bound to private IP only - won't receive NAT traffic
# Fix: Update HAProxy config to bind 0.0.0.0
sudo sed -i 's/bind 10\.241\.64\.8:/bind 0.0.0.0:/g' /etc/haproxy/haproxy.cfg
sudo systemctl restart haproxy
```

### Problem: DNS Resolves to Private IP

**Symptoms**:
- `dig` from local machine shows 10.241.64.8 instead of 169.59.189.20

**Cause**: Using local dnsmasq resolver instead of public DNS

**Solution**: Query public DNS directly
```bash
# Use Google DNS or Cloudflare DNS
dig @8.8.8.8 api.<cluster>.<domain>
dig @1.1.1.1 api.<cluster>.<domain>
```

**Route 53 records are correct if external DNS returns public IP**.

### Problem: HAProxy Shows Warnings

**Symptoms**:
```
[WARNING] : config : 'option forwardfor' ignored for backend 'api-server-backend' as it requires HTTP mode.
```

**Status**: **Expected and harmless**

These warnings occur because HAProxy is in TCP mode (required for TLS passthrough). The `forwardfor` option only applies to HTTP mode. This does not affect functionality.

### Problem: Firewall Blocking Traffic

**Symptoms**:
- HAProxy is configured correctly
- DNS resolves to public IP
- Still can't access from workstation

**Diagnosis**:
```bash
# Test from server itself (should work)
curl -k https://localhost:6443/version

# If this works but external access doesn't = firewall issue
```

**Solution - Check BOTH firewalls**:

1. **Local firewall (firewalld)**:
```bash
# Check if blocking
sudo firewall-cmd --list-all | grep ports

# If ports are missing, add them
sudo firewall-cmd --permanent --add-port=6443/tcp
sudo firewall-cmd --permanent --add-port=22623/tcp
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --permanent --add-port=8404/tcp
sudo firewall-cmd --reload
```

2. **IBM Cloud firewall**: Check IBM Cloud console firewall rules allow the same ports

## Example Configuration

### Real Deployment on IBM Cloud

**Cluster**: ha-test.sandbox590.opentlc.com  
**Public IP**: 169.59.189.20  
**Private IP**: 10.241.64.8  
**OpenShift Version**: 4.21.16

**HAProxy Configuration**:
```bash
# /etc/haproxy/haproxy.cfg
frontend api-server
    bind 0.0.0.0:6443
    mode tcp
    option tcplog
    default_backend api-server-backend

backend api-server-backend
    mode tcp
    balance roundrobin
    server api 192.168.50.253:6443 check
```

**Route 53 Records**:
```
api.ha-test.sandbox590.opentlc.com       → 169.59.189.20
api-int.ha-test.sandbox590.opentlc.com   → 169.59.189.20
*.apps.ha-test.sandbox590.opentlc.com    → 169.59.189.20
```

**Access**:
- Console: https://console-openshift-console.apps.ha-test.sandbox590.opentlc.com
- API: https://api.ha-test.sandbox590.opentlc.com:6443

## Key Takeaways

✅ **IBM Cloud uses NAT** - Public IP (169.x.x.x) maps to private IP (10.x.x.x)

✅ **HAProxy must bind 0.0.0.0** - Not the private IP, to receive NAT traffic

✅ **Route 53 points to PUBLIC IP** - Use 169.x.x.x, not 10.x.x.x

✅ **Firewall rules required** - Allow ports 6443, 22623, 80, 443 in IBM Cloud firewall

✅ **DNS resolution context matters**:
- Local dnsmasq: Resolves to internal VIPs (192.168.x.x)
- Public DNS: Resolves to public IP (169.x.x.x)
- Both are correct for their respective use cases

## HAProxy Statistics Dashboard (Optional)

Enable the HAProxy stats dashboard for real-time monitoring:

### Enable Stats Dashboard

Add to `/etc/haproxy/haproxy.cfg`:

```haproxy
# HAProxy Stats Dashboard
listen stats
    bind 0.0.0.0:8404
    mode http
    stats enable
    stats uri /
    stats refresh 30s
    stats show-legends
    stats show-node
    stats auth admin:<your-password>
```

**Restart HAProxy**:
```bash
sudo systemctl restart haproxy
```

**Add firewall rule**:
```bash
sudo firewall-cmd --permanent --add-port=8404/tcp
sudo firewall-cmd --reload
```

### Access Dashboard

**URL**: `http://169.59.189.20:8404/` (use your public IP)

**Features**:
- Real-time frontend/backend status
- Connection counts and rates
- Request rates per second
- Health check results
- Auto-refresh every 30 seconds

**Security Note**: Port 8404 is HTTP (unencrypted). Restrict access via IBM Cloud firewall to trusted IPs only.

## Validation

After completing the setup, validate:

1. ✅ HAProxy listening on `0.0.0.0` (not private IP)
2. ✅ Route 53 DNS resolves to public IP (`dig @8.8.8.8`)
3. ✅ API accessible from workstation (`curl -k https://api.<cluster>.<domain>:6443/version`)
4. ✅ Console accessible from browser (https://console-openshift-console.apps.<cluster>.<domain>)

## References

- **Main Documentation**: [README.md](../README.md)
- **HAProxy Configuration**: [hack/configure-haproxy-forwarder.sh](../hack/configure-haproxy-forwarder.sh)
- **Route 53 Configuration**: [hack/configure-route53-dns.sh](../hack/configure-route53-dns.sh)
- **IBM Cloud Firewall**: https://cloud.ibm.com/docs/bare-metal?topic=bare-metal-about-firewalls

## Support

For issues specific to IBM Cloud deployments:
1. Check HAProxy is bound to `0.0.0.0`
2. Verify Route 53 points to public IP
3. Confirm IBM Cloud firewall rules
4. Test from external machine (not localhost)

For general deployment issues, see the main [troubleshooting guide](../README.md#troubleshooting).
