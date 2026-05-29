---
layout: default
title: Bare Metal Production Guide
description: End-to-end runbook for deploying OpenShift on physical bare metal servers
parent: How-to Guides
nav_order: 1
---

# Bare Metal Production Guide

This guide covers the full production deployment lifecycle for OpenShift on physical bare metal servers. It is the second half of the **Development (KVM) → Fork & Adapt → Production (Bare Metal)** workflow — start with the [Developer Guide](developer-guide) and [Fork & Adapt Checklist](fork-and-adapt-checklist) before proceeding here.

## Overview

```
┌──────────────────────────────────────────────────────────────────┐
│  Phase 1: Hardware Preparation                                   │
│  BIOS/UEFI settings, RAID, firmware, NIC identification          │
├──────────────────────────────────────────────────────────────────┤
│  Phase 2: Corporate DNS Registration                             │
│  API, Ingress, and node records in enterprise DNS                │
├──────────────────────────────────────────────────────────────────┤
│  Phase 3: ISO Generation                                         │
│  hack/create-iso.sh (same as KVM workflow)                       │
├──────────────────────────────────────────────────────────────────┤
│  Phase 4: ISO Delivery                                           │
│  Virtual media (iDRAC/iLO), USB, or PXE                         │
├──────────────────────────────────────────────────────────────────┤
│  Phase 5: Boot and Monitor                                       │
│  openshift-install agent wait-for …                              │
├──────────────────────────────────────────────────────────────────┤
│  Phase 6: Post-Install Validation                                │
│  oc get nodes, oc get co, DNS/TLS verification                   │
└──────────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

Before starting, verify:

- [ ] All nodes validated on KVM (see [Developer Guide](developer-guide))
- [ ] Fork and Adapt checklist completed (see [Fork & Adapt Checklist](fork-and-adapt-checklist))
- [ ] `site-config/<cluster-name>/cluster.yml` and `nodes.yml` committed with real hardware values
- [ ] Red Hat pull secret available at the path set in `cluster.yml`
- [ ] SSH public key available
- [ ] OpenShift CLI tools downloaded: `./download-openshift-cli.sh`

Run the bare metal pre-flight validation script:

```bash
./hack/validate-baremetal-env.sh site-config/<cluster-name>
```

---

## Phase 1: Hardware Preparation

### 1.1 BIOS / UEFI Settings

Configure each server before deployment. Required settings:

| Setting | Required Value | Notes |
|---------|---------------|-------|
| Boot mode | UEFI | BIOS legacy is not supported by ABI |
| Secure Boot | Disabled | Enable after install if required |
| Virtualization | Enabled (VT-d, VT-x) | Required if hosting VMs post-install |
| PXE boot | Enabled (optional) | Only needed for PXE delivery method |
| Boot order | Network / Virtual Media first | Change after install completes |
| IPMI/iDRAC/iLO | Enabled, configured with static IP | Required for BMC management |

### 1.2 RAID / Storage Configuration

Configure storage before installation. OpenShift writes to the disk identified by `rootDeviceHints` in `nodes.yml`.

```bash
# Identify disk device names on each node via ipmitool/console
ipmitool -I lanplus -H <bmc-ip> -U <user> -P <pass> sol activate
# Then inside the node:
lsblk
ls /dev/disk/by-path/
```

Common `rootDeviceHints` patterns:

```yaml
# By device name (simplest)
rootDeviceHints:
  deviceName: /dev/nvme0n1

# By WWN (most reliable for SAN/multipath)
rootDeviceHints:
  wwn: "0x600508b1001c0000abcdef1234567890"

# By size (use when device names vary)
rootDeviceHints:
  minSizeGigabytes: 200
```

### 1.3 Network Interface Identification

Physical interface names differ from KVM `virtio` names. Identify the correct names before editing `nodes.yml`.

```bash
# Via BMC console or out-of-band SSH
ip link show
# Output: ens3f0, enp97s0f0, eno1, bond0 — varies by hardware/firmware

# Via lshw (if OS is already present)
sudo lshw -class network -short
```

Common naming patterns:

| Pattern | Example | Driver / Vendor |
|---------|---------|----------------|
| `eno<N>` | `eno1`, `eno2` | Onboard NICs (Dell, HPE) |
| `enp<slot>s<port>` | `enp97s0f0` | PCIe slot-based naming |
| `ens<N>f<port>` | `ens3f0` | Some Intel NICs |
| `eth<N>` | `eth0` | Fallback (predictable naming disabled) |

Update `nodes.yml` with the real interface names:

```yaml
nodes:
  - hostname: prod-master-1
    interfaces:
      - name: eno1          # real interface name, not virtio/ens3
        mac_address: "AA:BB:CC:DD:EE:01"
    networkConfig:
      interfaces:
        - name: eno1
          type: ethernet
          state: up
          mac-address: "AA:BB:CC:DD:EE:01"
          ipv4:
            enabled: true
            address:
              - ip: 10.0.0.21
                prefix-length: 24
            dhcp: false
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: 10.0.0.1
            next-hop-interface: eno1
            table-id: 254
```

### 1.4 BMC / IPMI Configuration

Each node needs a reachable BMC address in `nodes.yml`. Supported address schemes:

```yaml
nodes:
  - hostname: prod-master-1
    bmc:
      # iDRAC 9 via Redfish
      address: redfish-virtualmedia://10.0.1.10/redfish/v1/Systems/System.Embedded.1
      username: root
      password: "{{ lookup('env', 'BMC_PASSWORD') }}"  # use Ansible Vault in production
      disableCertificateVerification: true

  - hostname: prod-master-2
    bmc:
      # HPE iLO via Redfish
      address: redfish-virtualmedia://10.0.1.11/redfish/v1/Systems/1
      username: Administrator
      password: "{{ lookup('env', 'BMC_PASSWORD') }}"
      disableCertificateVerification: true

  - hostname: prod-master-3
    bmc:
      # Generic IPMI
      address: ipmi://10.0.1.12
      username: ADMIN
      password: "{{ lookup('env', 'BMC_PASSWORD') }}"
```

Verify BMC connectivity before generating the ISO:

```bash
# Test IPMI connectivity
ipmitool -I lanplus -H 10.0.1.10 -U root -P "${BMC_PASSWORD}" power status

# Test Redfish connectivity
curl -sk -u "root:${BMC_PASSWORD}" \
  https://10.0.1.10/redfish/v1/Systems/System.Embedded.1 | python3 -m json.tool
```

---

## Phase 2: Corporate DNS Registration

OpenShift **requires** these DNS records to exist before any node boots. Register them in your corporate DNS (see [Corporate DNS Integration](corporate-dns-integration) for BIND, Infoblox, and AD DNS specifics).

### Required Records

| Record | Type | Value | Purpose |
|--------|------|-------|---------|
| `api.<cluster>.<domain>` | A | API VIP | Kubernetes API server |
| `api-int.<cluster>.<domain>` | A | API VIP | Internal API (same VIP) |
| `*.apps.<cluster>.<domain>` | A | App VIP | Wildcard for application routes |
| `<hostname>.<cluster>.<domain>` | A | Node IP | Per-node records (optional but recommended) |

Using `cluster_name: ocp4` and `base_domain: example.com` with VIPs `10.0.0.100` / `10.0.0.101`:

```
api.ocp4.example.com       A  10.0.0.100
api-int.ocp4.example.com   A  10.0.0.100
*.apps.ocp4.example.com    A  10.0.0.101
```

### Verify DNS Before Proceeding

`hack/verify-dns-resolution.sh` tests against `localhost` (dnsmasq) and is not suitable for corporate DNS environments. Test directly against your DNS server instead:

```bash
# Replace 10.0.0.53 with your corporate DNS server IP
DNS_SERVER="10.0.0.53"
CLUSTER="ocp4.corp.example.com"

dig +short @${DNS_SERVER} api.${CLUSTER}
dig +short @${DNS_SERVER} api-int.${CLUSTER}
dig +short @${DNS_SERVER} console-openshift-console.apps.${CLUSTER}
dig +short @${DNS_SERVER} test.apps.${CLUSTER}
```

All four must return the correct VIP before continuing to Phase 3.

---

## Phase 3: ISO Generation

ISO generation is identical to the KVM workflow. The generated ISO is hardware-agnostic.

```bash
# Set SITE_CONFIG_DIR to use your production configs
export SITE_CONFIG_DIR=site-config

# Generate the ISO
./hack/create-iso.sh <cluster-name>
```

The ISO is written to `~/generated_assets/<cluster-name>/agent.x86_64.iso`.

Validate the generated manifests against deployment standards:

```bash
./hack/validate-deployment-standards.sh \
  ~/generated_assets/<cluster-name> <ocp-version>
```

---

## Phase 3.5: ACM / BareMetalHost Integration (Optional)

If you are using Red Hat Advanced Cluster Management (ACM) or want to manage nodes via the Metal3 BareMetalHost API post-install, generate the BareMetalHost manifests from your `nodes.yml`:

```bash
./hack/generate_bmc_acm_hosts.py \
  site-config/<cluster-name>/nodes.yml \
  ~/generated_assets/<cluster-name>/bmc-hosts.yaml

# Review the generated resources
cat ~/generated_assets/<cluster-name>/bmc-hosts.yaml

# Apply to a running ACM hub cluster
oc apply -f ~/generated_assets/<cluster-name>/bmc-hosts.yaml
```

This script reads the `bmc:` blocks in `nodes.yml` and produces `Secret` and `BareMetalHost` Kubernetes resources for the `openshift` namespace. It requires that `nodes.yml` already has real `bmc.address`, `bmc.username`, and `bmc.password` values filled in.

---

## Phase 4: ISO Delivery

Unlike KVM (where `deploy-on-kvm.sh` automates ISO mounting), physical servers require one of the following delivery methods. The Redfish API calls below are scriptable — run them in a loop over your node BMC addresses.

### Method A: Virtual Media via iDRAC (Dell)

iDRAC 9+ supports mounting an ISO from a remote HTTP/CIFS/NFS share.

```bash
# 1. Serve the ISO over HTTP (from the deployment host)
python3 -m http.server 8080 --directory ~/generated_assets/<cluster-name> &

# 2. Mount ISO via Redfish virtual media
ISO_URL="http://<deployment-host-ip>:8080/agent.x86_64.iso"
BMC_IP="10.0.1.10"

curl -sk -u "root:${BMC_PASSWORD}" -X POST \
  "https://${BMC_IP}/redfish/v1/Managers/iDRAC.Embedded.1/VirtualMedia/CD/Actions/VirtualMedia.InsertMedia" \
  -H "Content-Type: application/json" \
  -d "{\"Image\": \"${ISO_URL}\", \"Inserted\": true, \"WriteProtected\": true}"

# 3. Set boot device to virtual CD and power cycle
curl -sk -u "root:${BMC_PASSWORD}" -X PATCH \
  "https://${BMC_IP}/redfish/v1/Systems/System.Embedded.1" \
  -H "Content-Type: application/json" \
  -d '{"Boot": {"BootSourceOverrideTarget": "Cd", "BootSourceOverrideEnabled": "Once"}}'

curl -sk -u "root:${BMC_PASSWORD}" -X POST \
  "https://${BMC_IP}/redfish/v1/Systems/System.Embedded.1/Actions/ComputerSystem.Reset" \
  -H "Content-Type: application/json" \
  -d '{"ResetType": "ForceRestart"}'
```

Repeat for each node in the cluster.

### Method B: Virtual Media via iLO (HPE)

```bash
ISO_URL="http://<deployment-host-ip>:8080/agent.x86_64.iso"
BMC_IP="10.0.1.11"

# Mount ISO
curl -sk -u "Administrator:${BMC_PASSWORD}" -X POST \
  "https://${BMC_IP}/redfish/v1/Managers/1/VirtualMedia/2/Actions/VirtualMedia.InsertMedia" \
  -H "Content-Type: application/json" \
  -d "{\"Image\": \"${ISO_URL}\"}"

# Boot from virtual CD once
curl -sk -u "Administrator:${BMC_PASSWORD}" -X PATCH \
  "https://${BMC_IP}/redfish/v1/Systems/1" \
  -H "Content-Type: application/json" \
  -d '{"Boot": {"BootSourceOverrideTarget": "Cd", "BootSourceOverrideEnabled": "Once"}}'

# Reset
curl -sk -u "Administrator:${BMC_PASSWORD}" -X POST \
  "https://${BMC_IP}/redfish/v1/Systems/1/Actions/ComputerSystem.Reset" \
  -H "Content-Type: application/json" \
  -d '{"ResetType": "GracefulRestart"}'
```

### Method C: IPMI Chassis Boot

For hardware that does not support Redfish virtual media:

```bash
# Set boot device to PXE or virtual CD via IPMI
ipmitool -I lanplus -H 10.0.1.10 -U root -P "${BMC_PASSWORD}" \
  chassis bootdev cdrom options=efiboot

ipmitool -I lanplus -H 10.0.1.10 -U root -P "${BMC_PASSWORD}" \
  chassis power reset
```

### Method D: USB Boot

For environments without working BMC virtual media:

```bash
# Write ISO to USB drive (replace /dev/sdX with the actual USB device)
sudo dd if=~/generated_assets/<cluster-name>/agent.x86_64.iso \
        of=/dev/sdX bs=4M status=progress oflag=sync

# Physically insert USB into each node and boot
# After installation completes, remove USB and set boot order back to disk
```

### Method E: PXE Boot (Advanced)

PXE delivery requires extracting the kernel and initrd from the ISO and configuring a PXE server. This is most useful for s390x (which cannot boot ISO) or large-scale deployments.

```bash
# Extract PXE assets from the ISO
./bin/openshift-install agent create pxe-files \
  --dir ~/generated_assets/<cluster-name>

# Copy to TFTP/HTTP server
# Files generated: agent.x86_64-vmlinuz, agent.x86_64-initrd.img, agent.x86_64-rootfs.img
```

Refer to [Red Hat's PXE boot documentation](https://docs.openshift.com/container-platform/latest/installing/installing_with_agent_based_installer/preparing-to-install-with-agent-based-installer.html) for DHCP/TFTP server configuration.

---

## Phase 5: Boot and Monitor

Once all nodes are booted from the ISO, monitor installation progress from the deployment host.

```bash
# Monitor bootstrap completion (control plane ready)
./bin/openshift-install agent wait-for bootstrap-complete \
  --dir ~/generated_assets/<cluster-name>/ \
  --log-level=info

# Monitor full installation (all nodes, operators ready)
./bin/openshift-install agent wait-for install-complete \
  --dir ~/generated_assets/<cluster-name>/ \
  --log-level=info
```

Expected timeline:

| Stage | Approximate Time |
|-------|-----------------|
| Nodes boot from ISO | 2–5 min |
| Agent discovery and registration | 5–10 min |
| Bootstrap control plane | 20–30 min |
| Full cluster installation | 45–90 min |
| Cluster Operators stable | 15–30 min after install |

### Real-Time Node Status

```bash
# Watch node discovery in real time
watch -n 10 "./bin/openshift-install agent wait-for bootstrap-complete \
  --dir ~/generated_assets/<cluster-name>/ 2>&1 | tail -5"

# Check which nodes have checked in via Assisted Installer REST API (if accessible)
# The rendezvous node exposes the API during bootstrap
curl -s http://<rendezvous-ip>:8090/api/assisted-install/v2/infra-envs
```

### If a Node Does Not Boot

```bash
# Check power state via IPMI
ipmitool -I lanplus -H <bmc-ip> -U <user> -P "${BMC_PASSWORD}" power status

# Check SOL console for boot errors
ipmitool -I lanplus -H <bmc-ip> -U <user> -P "${BMC_PASSWORD}" sol activate

# Force virtual media remount and retry
# (repeat Phase 4 commands for the specific node)
```

---

## Phase 6: Post-Install Validation

### 6.1 Cluster Access

```bash
# Export kubeconfig
export KUBECONFIG=~/generated_assets/<cluster-name>/auth/kubeconfig

# Verify nodes are Ready
oc get nodes

# Check all Cluster Operators are Available
oc get co

# Check for any degraded operators
oc get co | grep -v "True.*False.*False"
```

Expected `oc get nodes` output for HA (3 control + 3 worker):

```
NAME            STATUS   ROLES                  AGE   VERSION
prod-master-1   Ready    control-plane,master   45m   v1.30.x
prod-master-2   Ready    control-plane,master   45m   v1.30.x
prod-master-3   Ready    control-plane,master   45m   v1.30.x
prod-worker-1   Ready    worker                 30m   v1.30.x
prod-worker-2   Ready    worker                 30m   v1.30.x
prod-worker-3   Ready    worker                 30m   v1.30.x
```

### 6.2 Web Console Access

```bash
# Get console URL
oc whoami --show-console

# Get admin credentials
cat ~/generated_assets/<cluster-name>/auth/kubeadmin-password
```

Open the console URL in a browser and log in with `kubeadmin` / `<password>`.

### 6.3 DNS and TLS Verification

```bash
# Verify DNS resolution from deployment host (use your corporate DNS server)
DNS_SERVER="10.0.0.53"
CLUSTER="ocp4.corp.example.com"
dig +short @${DNS_SERVER} api.${CLUSTER}
dig +short @${DNS_SERVER} test.apps.${CLUSTER}

# Verify TLS certificates (default self-signed)
openssl s_client -connect api.<cluster>.<domain>:6443 -showcerts < /dev/null 2>/dev/null \
  | openssl x509 -noout -dates -subject
```

### 6.4 External Access Setup (Optional)

If the cluster is not directly reachable from the end-user network:

```bash
# Configure HAProxy forwarder
./hack/configure-haproxy-forwarder.sh site-config/<cluster-name>/cluster.yml

# Configure Route53 DNS (if AWS-hosted)
./hack/configure-route53-dns.sh site-config/<cluster-name>/cluster.yml

# Configure Let's Encrypt TLS
./hack/configure-letsencrypt-certs.sh site-config/<cluster-name>/cluster.yml
```

See [HAProxy Forwarder Guide](haproxy-forwarder-guide) for detailed setup.

---

## Bare Metal vs KVM: Key Operational Differences

| Concern | KVM (Development) | Bare Metal (Production) |
|---------|------------------|------------------------|
| ISO delivery | `deploy-on-kvm.sh` (automated) | Virtual media / USB / PXE (manual or scripted) |
| Node reboot | `watch-and-reboot-kvm-vms.sh` | BMC auto-power-on after disk write |
| DNS | dnsmasq / libvirt | Corporate DNS (BIND / Infoblox / AD) |
| BMC | sushy Redfish emulator | Real iDRAC / iLO / IPMI |
| NICs | `virtio` / `ens3` | `eno1` / `enp97s0f0` (hardware-dependent) |
| Storage | `qcow2` virtual disks | NVMe / SAS / SATA (use `rootDeviceHints`) |
| VIP management | Simulated | keepalived on `platform_type: baremetal` |
| Cleanup | `destroy-on-kvm.sh` | Power off + reinstall (manual) |

**Node reboot on bare metal**: Physical servers with `platform_type: baremetal` use the OpenShift Machine API and keepalived to manage VIPs. After the agent writes the OS to disk, nodes power off and automatically power back on via BMC — you do **not** need `watch-and-reboot-kvm-vms.sh` on bare metal.

---

## Troubleshooting Bare Metal Deployments

See [Troubleshooting Guide](troubleshooting.md#bare-metal-issues) for bare metal-specific diagnostics.

Common issues:

| Symptom | Likely Cause | Resolution |
|---------|-------------|------------|
| Node never appears in agent discovery | ISO not booting | Check BMC console, verify UEFI boot order |
| Installation hangs at bootstrap | DNS not resolving | Verify all DNS records exist and resolve |
| VIP not reachable after install | L2 reachability issue | Verify VIPs are on same L2 as nodes |
| NIC not configured | Wrong interface name | Check `ip link` on node via BMC console |
| Certificate errors on API | Self-signed cert | Expected — configure custom CA post-install |

---

## Related Documentation

- [Fork & Adapt Checklist](fork-and-adapt-checklist) — Migration checklist from KVM to bare metal
- [Corporate DNS Integration](corporate-dns-integration) — Enterprise DNS registration guide
- [BMC Management Guide](bmc-management) — Real hardware BMC configuration
- [Developer Guide](developer-guide) — KVM development environment setup
- [Configuration Guide](configuration-guide) — All `cluster.yml` and `nodes.yml` parameters
- [HAProxy Forwarder Guide](haproxy-forwarder-guide) — External cluster access
- [Red Hat ABI Documentation](https://docs.openshift.com/container-platform/latest/installing/installing_with_agent_based_installer/preparing-to-install-with-agent-based-installer.html)
