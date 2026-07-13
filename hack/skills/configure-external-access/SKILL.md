---
name: Configure External Access
description: Set up HAProxy forwarding, Route53 public DNS, and Let's Encrypt TLS certificates for external cluster access
triggers:
  - external access
  - configure HAProxy
  - Route53 DNS
  - Let's Encrypt certificates
  - public access to cluster
  - expose cluster externally
  - configure-external-access
  - TLS certificates
---

# Configure External Access

## When to Use This Skill

Activate when a user wants to:
- Make their KVM cluster accessible from the internet or external networks
- Set up HAProxy to forward traffic from a public IP to cluster VIPs
- Create Route53 DNS records pointing to the cluster
- Obtain trusted Let's Encrypt TLS certificates
- Run `configure-external-access.sh` or its component scripts

## Prerequisites

- OpenShift cluster deployed and accessible (VIPs responding on internal network)
- KUBECONFIG set and `oc get nodes` working
- Public/external IP on the deployment host (`EXTERNAL_IP`)
- AWS account with Route53 hosted zone matching `base_domain`
- AWS credentials: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`
- Email address for Let's Encrypt registration (`EMAIL`)
- Ports 80, 443, 6443, 22623 available on EXTERNAL_IP (firewall opened)
- Host firewall configured: `sudo firewall-cmd --add-port={80,443,6443,22623}/tcp --permanent`
- Container runtime (podman or docker) for certbot

## Procedure

### Option A: One-Command Setup (Recommended)

Create a `.env` file with credentials:

```bash
cp .env.example .env
chmod 600 .env
# Edit .env with your values:
#   EXTERNAL_IP=<your-public-ip>
#   AWS_ACCESS_KEY_ID=<key>
#   AWS_SECRET_ACCESS_KEY=<secret>
#   EMAIL=<your-email>
```

Run the orchestrator:

```bash
export KUBECONFIG=~/generated_assets/<cluster-name>/auth/kubeconfig
./hack/configure-external-access.sh examples/<cluster>/cluster.yml
```

This automatically:
1. Sources `.env` for credentials
2. Deploys HAProxy forwarder
3. Creates Route53 DNS records
4. Waits for DNS propagation (1-3 minutes)
5. Obtains Let's Encrypt certificates
6. Installs certificates in OpenShift

### Option B: Step-by-Step

#### Step 1: Deploy HAProxy Forwarder

```bash
export EXTERNAL_IP="<your-host-public-ip>"
./hack/configure-haproxy-forwarder.sh examples/<cluster>/cluster.yml
```

This creates HAProxy rules:
- `EXTERNAL_IP:6443` -> `api_vip:6443` (API Server)
- `EXTERNAL_IP:22623` -> `api_vip:22623` (Machine Config)
- `EXTERNAL_IP:80` -> `app_vip:80` (HTTP Ingress)
- `EXTERNAL_IP:443` -> `app_vip:443` (HTTPS Ingress)

Verify:
```bash
curl -k https://${EXTERNAL_IP}:6443/version
```

#### Step 2: Configure Route53 DNS

```bash
export AWS_ACCESS_KEY_ID="<key>"
export AWS_SECRET_ACCESS_KEY="<secret>"
export EXTERNAL_IP="<your-host-public-ip>"
./hack/configure-route53-dns.sh add examples/<cluster>/cluster.yml
```

This creates A records:
- `api.<cluster>.<domain>` -> EXTERNAL_IP
- `*.apps.<cluster>.<domain>` -> EXTERNAL_IP

Verify propagation:
```bash
dig api.<cluster>.<domain> @8.8.8.8
dig console-openshift-console.apps.<cluster>.<domain> @8.8.8.8
```

Wait until both resolve to EXTERNAL_IP (typically 1-3 minutes).

#### Step 3: Obtain Let's Encrypt Certificates

```bash
export EMAIL="<your-email>"
export AWS_ACCESS_KEY_ID="<key>"
export AWS_SECRET_ACCESS_KEY="<secret>"
export KUBECONFIG=~/generated_assets/<cluster-name>/auth/kubeconfig
./hack/configure-letsencrypt-certs.sh
```

This uses certbot with DNS-01 challenge via Route53 to:
1. Request wildcard cert for `*.apps.<cluster>.<domain>`
2. Request cert for `api.<cluster>.<domain>`
3. Patch OpenShift ingress controller with the new certs
4. Patch API server certificate

#### Step 4: Verify

```bash
# Test API with trusted cert
curl https://api.<cluster>.<domain>:6443/version

# Test console (should redirect to OAuth)
curl -I https://console-openshift-console.apps.<cluster>.<domain>

# Verify cert issuer
echo | openssl s_client -connect api.<cluster>.<domain>:6443 2>/dev/null | \
  openssl x509 -noout -issuer
# Should show: Let's Encrypt
```

### Removing External Access

```bash
# Remove Route53 records
./hack/configure-route53-dns.sh remove examples/<cluster>/cluster.yml

# HAProxy removal is manual:
sudo systemctl stop haproxy
sudo systemctl disable haproxy
```

## Environment Variables

| Variable | Required | Purpose |
|----------|----------|---------|
| `EXTERNAL_IP` | Yes | Public IP for HAProxy and DNS records |
| `AWS_ACCESS_KEY_ID` | Yes (Route53) | AWS credential for DNS management |
| `AWS_SECRET_ACCESS_KEY` | Yes (Route53) | AWS credential for DNS management |
| `EMAIL` | Yes (certs) | Let's Encrypt registration email |
| `KUBECONFIG` | Yes (certs) | Path to cluster kubeconfig |
| `CERT_STAGING` | No | Set `true` to use Let's Encrypt staging (testing) |

## Validation Criteria

External access is fully configured when:
1. HAProxy is running and forwarding ports 80/443/6443
2. Route53 shows A records for api.* and *.apps.*
3. `dig api.<cluster>.<domain> @8.8.8.8` returns EXTERNAL_IP
4. `curl https://api.<cluster>.<domain>:6443/version` returns valid JSON
5. Browser can reach `https://console-openshift-console.apps.<cluster>.<domain>`
6. Certificate issuer shows "Let's Encrypt" (not self-signed)

## Common Failure Modes

| Phase | Symptom | Cause | Fix |
|-------|---------|-------|-----|
| HAProxy | "Cannot assign requested address" | EXTERNAL_IP is NAT/floating (not on local interface) | Script auto-detects and binds to `*`; verify with `ip addr show` |
| HAProxy | Port already in use | Another service on 6443/443/80 | `ss -tlnp \| grep <port>`; stop conflicting service |
| HAProxy | Connection refused to VIP | HAProxy can't reach cluster network | Verify host has route to VIP subnet |
| Firewall | ERR_CONNECTION_REFUSED from browser | Host firewall blocks incoming traffic | `sudo firewall-cmd --add-port={80,443,6443,22623}/tcp --permanent && sudo firewall-cmd --reload` |
| Route53 | "No hosted zone found" | base_domain doesn't match a Route53 zone | Verify zone exists: `aws route53 list-hosted-zones` |
| Route53 | "Access denied" | Wrong AWS credentials or missing permissions | Need `route53:ChangeResourceRecordSets` permission |
| DNS | Propagation timeout | DNS TTL or caching | Wait longer; test with `dig @8.8.8.8` (bypasses local cache) |
| Certs | "DNS problem: NXDOMAIN" | DNS not propagated before cert request | Wait for `dig @8.8.8.8` to resolve before running certbot |
| Certs | Rate limit exceeded | Too many cert requests in short time | Use `CERT_STAGING=true` for testing; wait 1 hour for production |
| Certs | "unauthorized" from oc | KUBECONFIG invalid or cluster unreachable | Verify `oc whoami` works |
| Certs | Container runtime missing | No podman or docker | `sudo dnf install podman` |
| General | EXTERNAL_IP wrong | IP doesn't match actual host | `curl ifconfig.me` to verify public IP |

## Security Notes

- `.env` file should be `chmod 600` (owner-only read)
- AWS credentials should use minimal IAM permissions (Route53 only)
- Let's Encrypt certs auto-renew but renewal must be scheduled
- HAProxy exposes cluster to the public internet -- restrict with firewall if needed

## Key Files

- `hack/configure-external-access.sh` - Full orchestrator (sources .env)
- `hack/configure-haproxy-forwarder.sh` - HAProxy deployment via Ansible role
- `hack/configure-route53-dns.sh` - Route53 A record management (add/remove/list)
- `hack/configure-letsencrypt-certs.sh` - Certbot with DNS-01 via Route53
- `.env.example` - Template for credentials file
- `docs/haproxy-forwarder-guide.md` - Detailed HAProxy documentation
- `llm.txt` - "Phase 6.5: External Access Configuration" section
