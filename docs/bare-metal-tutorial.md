---
layout: default
title: Bare Metal Deployment Tutorial
parent: Tutorials
nav_order: 6
---

# Bare Metal Deployment Tutorial

> **Contributions welcome** — Hardware environments vary widely. If you hit a step
> that does not work on your specific hardware (server model, BMC firmware, NIC naming),
> please [open an issue](https://github.com/tosin2013/openshift-agent-install/issues) or
> [submit a PR](https://github.com/tosin2013/openshift-agent-install/blob/main/CONTRIBUTING.md).
> Both the KVM and bare metal paths benefit from community experience.

This tutorial walks you through deploying OpenShift on physical bare metal servers using the Agent-Based Installer. You will configure a real cluster from scratch, validate your environment, generate an agent ISO, deliver it to your servers via BMC, and reach a running cluster.

**Primary workflow**: Development (KVM) → Fork & Adapt → **Production (Bare Metal)** ← you are here

> **Coming from KVM?** If you have already validated a cluster on KVM using the
> [Developer Guide](developer-guide), complete the
> [Fork & Adapt Checklist](fork-and-adapt-checklist) to migrate your configuration
> before Phase 2 of this tutorial. You can skip Phase 1 hardware setup if your
> servers are already known-good.

---

## What you will build

A complete OpenShift cluster on physical servers — SNO, 3-node compact, or HA — with:
- Real hardware MACs and static IPs in NMState network config
- Corporate DNS entries for API and Ingress VIPs
- ISO delivered automatically via BMC (Redfish or IPMI)
- Validated cluster operators and TLS certificates

---

## Prerequisites

### Hardware
| Requirement | SNO | 3-Node Compact | HA (3+2) |
|-------------|-----|----------------|----------|
| Control plane nodes | 1 | 3 | 3 |
| Worker nodes | 0 | 0 | 2+ |
| Min CPU per control node | 8 vCPU | 6 vCPU | 4 vCPU |
| Min RAM per control node | 32 GB | 32 GB | 16 GB |
| Min disk per node | 120 GB (NVMe preferred) | 120 GB | 120 GB |
| BIOS mode | UEFI (not legacy) | UEFI | UEFI |
| BMC | iDRAC 9+ / iLO 5+ / IPMI | required | required |

### Access and credentials
- [ ] BMC (iDRAC / iLO / IPMI) access with credentials for every server
- [ ] Red Hat pull secret — download from [console.redhat.com/openshift/install/pull-secret](https://console.redhat.com/openshift/install/pull-secret)
- [ ] SSH public key for post-install access
- [ ] Access to register DNS records in your corporate DNS server (BIND, Infoblox, AD)
- [ ] A Linux deployment host with network access to all BMC IPs and node IPs

### Software on the deployment host

```bash
# Required tools
sudo dnf install -y curl ipmitool python3 nmstate jq git

# OpenShift CLI tools (run once, from repo root)
./download-openshift-cli.sh
```

---

## Phase 1 — Hardware Preparation

### 1.1 BIOS / UEFI settings

Configure each server before starting. Required settings:

| Setting | Required Value | Notes |
|---------|---------------|-------|
| Boot mode | UEFI | Agent ISO does not support legacy BIOS |
| Secure Boot | Disabled | Re-enable after install if your policy requires it |
| Virtualization | Enabled (VT-d, VT-x) | Only required if hosting VMs after install |
| PXE boot | Enabled (optional) | Only needed for PXE delivery method |
| Boot order | Network / Virtual Media first | Return to disk after install completes |
| BMC (iDRAC / iLO / IPMI) | Enabled, static IP configured | Required for `deploy-iso-baremetal.sh` |

### 1.2 Identify disk device names

OpenShift writes to the disk identified by `rootDeviceHints` in `nodes.yml`. Find the correct device name on each server via the BMC serial-over-LAN console:

```bash
# Open console to a node
ipmitool -I lanplus -H <bmc-ip> -U <user> -P <pass> sol activate

# Inside the node (boot any live Linux), identify disks
lsblk
ls /dev/disk/by-path/
```

Common `rootDeviceHints` patterns:

```yaml
# Simplest — by device name (use when device names are consistent)
rootDeviceHints:
  deviceName: /dev/nvme0n1

# Most reliable — by WWN (SAN / multipath)
rootDeviceHints:
  wwn: "0x600508b1001c0000abcdef1234567890"

# Flexible — by minimum size
rootDeviceHints:
  minSizeGigabytes: 200
```

### 1.3 Verify BMC reachability

```bash
# Clone the repo if you have not already
git clone https://github.com/tosin2013/openshift-agent-install.git
cd openshift-agent-install

# Quick reachability check against your nodes.yml (after Phase 2)
./hack/deploy-iso-baremetal.sh site-config/<cluster-name>/nodes.yml --method check
```

---

## Phase 2 — Configuration

### 2.1 Create your cluster config directory

```bash
# Copy the bare metal example as your starting point
export CLUSTER_NAME=my-baremetal-cluster
mkdir -p site-config/${CLUSTER_NAME}
cp examples/baremetal-example/cluster.yml site-config/${CLUSTER_NAME}/
cp examples/baremetal-example/nodes.yml   site-config/${CLUSTER_NAME}/
```

### 2.2 Edit cluster.yml

Open `site-config/${CLUSTER_NAME}/cluster.yml` and update:

```yaml
cluster_name: my-baremetal-cluster       # DNS-safe name, used in all hostnames
base_domain: example.com                 # Your corporate domain

platform_type: baremetal                 # Keep as baremetal for physical servers
control_plane_replicas: 3               # 1 (SNO), 3 (compact or HA)
app_node_replicas: 0                    # 0 for SNO/3-node, 2+ for HA

# VIPs — must be unused IPs within your machine_network_cidr
api_vips:
  - 192.168.180.10                       # api.<cluster>.<domain>
app_vips:
  - 192.168.180.11                       # *.apps.<cluster>.<domain>

machine_network_cidr: 192.168.180.0/24  # Your physical network CIDR

# DNS and NTP — use your corporate servers
dns_servers:
  - 10.0.0.53                           # Corporate DNS (NOT 192.168.122.1)
ntp_sources:
  - 10.0.0.1

pull_secret_file: ~/.openshift/pull-secret.json
ssh_public_key_file: ~/.ssh/id_rsa.pub
```

> **Key differences from KVM**: `dns_servers` points to your corporate DNS, not
> `192.168.122.1`. VIPs must be IPs on your physical network. No VyOS or libvirt
> networking involved.

### 2.3 Edit nodes.yml

Update `site-config/${CLUSTER_NAME}/nodes.yml` with real hardware values:

```yaml
control_plane_replicas: 3
app_node_replicas: 0

nodes:
  - hostname: master-0
    role: master
    bmc:
      address: redfish-virtualmedia://192.168.180.100/redfish/v1/Systems/System.Embedded.1
      username: root
      password: "your-idrac-password"    # Use Ansible Vault in production
      disableCertificateVerification: true
    rootDeviceHints:
      deviceName: /dev/nvme0n1           # From Phase 1.2
    interfaces:
      - name: eno1                       # Real NIC name from lshw / ip link
        mac_address: "EC:F4:BB:C0:B9:C8" # Real MAC from hardware
    networkConfig:
      interfaces:
        - name: eno1
          type: ethernet
          state: up
          mac-address: "EC:F4:BB:C0:B9:C8"
          ipv4:
            enabled: true
            address:
              - ip: 192.168.180.21
                prefix-length: 24
            dhcp: false
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: 192.168.180.1
            next-hop-interface: eno1
            table-id: 254

  - hostname: master-1
    role: master
    bmc:
      address: redfish-virtualmedia://192.168.180.101/redfish/v1/Systems/System.Embedded.1
      username: root
      password: "your-idrac-password"
      disableCertificateVerification: true
    rootDeviceHints:
      deviceName: /dev/nvme0n1
    interfaces:
      - name: eno1
        mac_address: "EC:F4:BB:C0:B9:C9"
    networkConfig:
      interfaces:
        - name: eno1
          type: ethernet
          state: up
          mac-address: "EC:F4:BB:C0:B9:C9"
          ipv4:
            enabled: true
            address:
              - ip: 192.168.180.22
                prefix-length: 24
            dhcp: false
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: 192.168.180.1
            next-hop-interface: eno1
            table-id: 254

  - hostname: master-2
    role: master
    bmc:
      address: redfish-virtualmedia://192.168.180.102/redfish/v1/Systems/System.Embedded.1
      username: root
      password: "your-idrac-password"
      disableCertificateVerification: true
    rootDeviceHints:
      deviceName: /dev/nvme0n1
    interfaces:
      - name: eno1
        mac_address: "EC:F4:BB:C0:B9:CA"
    networkConfig:
      interfaces:
        - name: eno1
          type: ethernet
          state: up
          mac-address: "EC:F4:BB:C0:B9:CA"
          ipv4:
            enabled: true
            address:
              - ip: 192.168.180.23
                prefix-length: 24
            dhcp: false
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: 192.168.180.1
            next-hop-interface: eno1
            table-id: 254
```

**BMC address schemes by vendor**:

| Vendor | Address format |
|--------|----------------|
| Dell iDRAC 9+ | `redfish-virtualmedia://BMC-IP/redfish/v1/Systems/System.Embedded.1` |
| HPE iLO 5+ | `redfish-virtualmedia://BMC-IP/redfish/v1/Systems/1` |
| Generic IPMI | `ipmi://BMC-IP` |

> **Security**: Do not commit passwords to git. For production use Ansible Vault
> (`ansible-vault encrypt_string`) or export `BMC_PASSWORD` as an environment variable.

### 2.4 Validate NMState syntax

```bash
# Validate networkConfig blocks before generating the ISO
python3 -c "
import yaml, subprocess, sys
nodes = yaml.safe_load(open('site-config/${CLUSTER_NAME}/nodes.yml'))
for n in nodes['nodes']:
    nc = n.get('networkConfig')
    if nc:
        r = subprocess.run(['nmstatectl', 'gc', '-'], input=yaml.dump(nc),
                           capture_output=True, text=True)
        if r.returncode != 0:
            print(f'NMState error in {n[\"hostname\"]}:', r.stderr)
            sys.exit(1)
        print(f'OK: {n[\"hostname\"]}')
"
```

---

## Phase 3 — Corporate DNS Registration

OpenShift **requires** these DNS records before any node boots. Register them in your corporate DNS server — they must resolve from the node IPs, not just from the deployment host.

| Record | Type | Value |
|--------|------|-------|
| `api.<cluster-name>.<domain>` | A | API VIP (`192.168.180.10`) |
| `api-int.<cluster-name>.<domain>` | A | API VIP (`192.168.180.10`) |
| `*.apps.<cluster-name>.<domain>` | A | App VIP (`192.168.180.11`) |

**BIND example**:

```bash
# Add to your zone file
api.my-baremetal-cluster.example.com.      IN A 192.168.180.10
api-int.my-baremetal-cluster.example.com.  IN A 192.168.180.10
*.apps.my-baremetal-cluster.example.com.   IN A 192.168.180.11

# Reload BIND
sudo rndc reload example.com
```

Verify resolution from the deployment host:

```bash
DNS_SERVER=10.0.0.53
CLUSTER=my-baremetal-cluster.example.com

dig @${DNS_SERVER} api.${CLUSTER}        +short   # must return 192.168.180.10
dig @${DNS_SERVER} api-int.${CLUSTER}   +short   # must return 192.168.180.10
dig @${DNS_SERVER} console.apps.${CLUSTER} +short # must return 192.168.180.11
```

> For Infoblox, Active Directory DNS, or more detail on PTR records, see the
> [Corporate DNS Integration](corporate-dns-integration) guide.

---

## Phase 4 — Pre-flight Validation

Run the bare metal validation script — it checks tools, DNS, VIP routing, BMC reachability, NMState syntax, pull secret, and SSH key in one pass:

```bash
export SITE_CONFIG_DIR=site-config
./hack/validate-baremetal-env.sh ${CLUSTER_NAME}
```

Expected output (all checks passing):

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[1/8] Required tools
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ openshift-install found
✓ oc found
...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Summary: 8 PASSED, 0 FAILED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Fix any failures before continuing. Common issues:

| Failure | Fix |
|---------|-----|
| DNS not resolving | Verify records were added and zone was reloaded |
| BMC not reachable | Check BMC IP, firewall, VLAN tagging on management port |
| NMState invalid | Check interface names match `ip link` output on the server |
| Pull secret invalid | Re-download from console.redhat.com |

---

## Phase 5 — ISO Generation

```bash
export SITE_CONFIG_DIR=site-config
./hack/create-iso.sh ${CLUSTER_NAME}
```

This runs the Ansible playbook to template manifests, then calls `openshift-install agent create image`. The ISO lands at:

```
~/generated_assets/${CLUSTER_NAME}/agent.x86_64.iso
```

Verify it was created:

```bash
ls -lh ~/generated_assets/${CLUSTER_NAME}/agent.x86_64.iso
# Expected: ~1.1 GB
```

---

## Phase 6 — ISO Delivery

The new `deploy-iso-baremetal.sh` script automates ISO delivery to all nodes in one command. It starts a local HTTP server, mounts the ISO via Redfish virtual media, sets one-time boot to CD, and power-cycles each server.

### Option A: Redfish virtual media (recommended — iDRAC 9+ / iLO 5+)

```bash
export SITE_CONFIG_DIR=site-config

./hack/deploy-iso-baremetal.sh \
    site-config/${CLUSTER_NAME}/nodes.yml \
    --method redfish \
    --iso ~/generated_assets/${CLUSTER_NAME}/agent.x86_64.iso
```

The script will:
1. Start a Python HTTP server on port 8080 (auto-selects the correct outbound IP)
2. Mount the ISO on each node's BMC virtual media slot
3. Set one-time boot to CD for each node
4. Power-cycle each node
5. Stop the HTTP server and print monitoring commands

> **Firewall**: Ensure port 8080 is open from your BMC IPs to the deployment host.
> `sudo firewall-cmd --add-port=8080/tcp --temporary`

### Option B: IPMI chassis boot

For servers without Redfish virtual media support. You must deliver the ISO separately (USB or PXE) before running this command:

```bash
./hack/deploy-iso-baremetal.sh \
    site-config/${CLUSTER_NAME}/nodes.yml \
    --method ipmi \
    --iso ~/generated_assets/${CLUSTER_NAME}/agent.x86_64.iso
```

### Option C: USB boot (no BMC automation)

```bash
# Write ISO to USB (replace /dev/sdX with your USB device)
sudo dd if=~/generated_assets/${CLUSTER_NAME}/agent.x86_64.iso \
        of=/dev/sdX bs=4M status=progress oflag=sync

# Physically insert USB into each server and power on
```

### Verify nodes are booting

```bash
# Watch agent discovery in real-time (Redfish / IPMI only)
# Within 5-10 minutes nodes should appear in the agent console
./bin/openshift-install agent wait-for bootstrap-complete \
    --dir ~/generated_assets/${CLUSTER_NAME}/ \
    --log-level=info
```

If nodes do not appear after 15 minutes:
- Check that the node IPs are reachable from the deployment host
- Verify the ISO file is intact: `sha256sum ~/generated_assets/${CLUSTER_NAME}/agent.x86_64.iso`
- Check BMC console for boot errors (wrong UEFI mode, disk not found, NIC down)

---

## Phase 7 — Monitor Installation

```bash
# Phase 1: Bootstrap control plane (first ~30 minutes)
./bin/openshift-install agent wait-for bootstrap-complete \
    --dir ~/generated_assets/${CLUSTER_NAME}/ \
    --log-level=info

# Phase 2: Full cluster installation (additional ~30-60 minutes)
./bin/openshift-install agent wait-for install-complete \
    --dir ~/generated_assets/${CLUSTER_NAME}/ \
    --log-level=info
```

Expected timeline:

| Stage | Approximate time |
|-------|-----------------|
| Nodes boot from ISO | 2–5 min |
| Agent discovery | 5–10 min |
| Bootstrap control plane | 20–30 min |
| Full cluster install | 45–90 min |
| Cluster Operators stable | 15–30 min after install |

---

## Phase 8 — Validate Cluster

```bash
export KUBECONFIG=~/generated_assets/${CLUSTER_NAME}/auth/kubeconfig

# Check nodes
oc get nodes -o wide

# Check all Cluster Operators are Available
oc get co

# Verify API and console DNS resolution
dig api.${CLUSTER_NAME}.example.com +short        # should return API VIP
curl -kI https://api.${CLUSTER_NAME}.example.com:6443/version

# Verify console
oc whoami --show-console
```

Get your kubeadmin password:

```bash
cat ~/generated_assets/${CLUSTER_NAME}/auth/kubeadmin-password
```

### Validate all Cluster Operators are ready

```bash
oc get co | awk 'NR==1 || $3=="False" || $4=="True" || $5=="True"'
# Only the header line should print — all operators should be Available=True, Degraded=False
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Nodes don't appear in agent console | Wrong IP/MAC in nodes.yml | Verify with `ip link` on booted node console |
| Bootstrap takes > 45 min | DNS not resolving from node | Test: `dig api.<cluster>.<domain>` from a node via BMC console |
| Node fails to boot ISO | Secure Boot enabled | Disable Secure Boot in BIOS |
| ISO mounts but node won't boot it | BIOS mode = legacy, not UEFI | Switch to UEFI in BIOS |
| `deploy-iso-baremetal.sh` Redfish error | Firewall blocking port 8080 | `sudo firewall-cmd --add-port=8080/tcp --temporary` |
| Cluster Operator degraded after install | VIP not reachable from cluster | Verify VIP ARP/routing on physical switch |

For more detail, see [Troubleshooting](troubleshooting) and [BMC Management](bmc-management).

---

## What's next

- **External access**: Set up HAProxy and Route53 DNS → [HAProxy Forwarder Guide](haproxy-forwarder-guide)
- **Identity management**: Integrate LDAP or Active Directory → [Identity Management](identity-management)
- **Multi-cluster**: Register with ACM → generate BareMetalHost manifests with `./hack/generate_bmc_acm_hosts.py`
- **Understand the architecture**: [Deployment Patterns](deployment-patterns), [Networking Architecture](networking-architecture)

---

## Related documentation

- [Developer Guide](developer-guide) — KVM development environment (start here for learning)
- [Fork & Adapt Checklist](fork-and-adapt-checklist) — Field-level migration guide from KVM to bare metal
- [Bare Metal Production Guide](bare-metal-production-guide) — Production runbook (task-oriented How-to)
- [BMC Management Guide](bmc-management) — iDRAC / iLO / IPMI deep dive
- [Corporate DNS Integration](corporate-dns-integration) — BIND / Infoblox / Active Directory
- [Troubleshooting](troubleshooting) — Common issues and fixes

---

> **Contributions welcome** — If a step failed on your hardware or you found a better
> approach, the community will benefit from your experience.
> [Open an issue](https://github.com/tosin2013/openshift-agent-install/issues) or
> [submit a PR](https://github.com/tosin2013/openshift-agent-install/blob/main/CONTRIBUTING.md).
