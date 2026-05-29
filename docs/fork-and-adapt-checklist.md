---
layout: default
title: Fork & Adapt Checklist
description: Step-by-step migration checklist from KVM development to bare metal production
parent: How-to Guides
nav_order: 2
---

# Fork & Adapt Checklist

This checklist bridges the gap between **KVM development** and **bare metal production**. Work through each section in order. Every item that requires a change maps to a specific file and field so nothing is ambiguous.

For background on the full workflow, see the [Developer Guide](developer-guide). For the production deployment steps after this checklist is complete, see the [Bare Metal Production Guide](bare-metal-production-guide).

---

## Step 1: Fork the Repository

- [ ] Fork `https://github.com/tosin2013/openshift-agent-install` to your organization on GitHub
- [ ] Clone your fork locally:

  ```bash
  git clone https://github.com/<your-org>/openshift-agent-install.git
  cd openshift-agent-install
  ```

- [ ] Add upstream remote so you can sync future fixes:

  ```bash
  git remote add upstream https://github.com/tosin2013/openshift-agent-install.git
  git fetch upstream
  ```

- [ ] Create an organization branch for your customizations:

  ```bash
  git checkout -b <your-org>-production
  ```

---

## Step 2: Set Up Your site-config Directory

The `site-config/` directory (gitignored) holds production configurations that should **not** be committed to the public fork. Use a private repo or Ansible Vault for secrets.

- [ ] Create the directory structure:

  ```bash
  mkdir -p site-config/<cluster-name>
  ```

- [ ] Copy the closest reference example:

  ```bash
  # For HA bare metal cluster
  cp examples/baremetal-example/cluster.yml site-config/<cluster-name>/cluster.yml
  cp examples/baremetal-example/nodes.yml   site-config/<cluster-name>/nodes.yml

  # For SNO bare metal
  cp examples/sno-4.20-standard/cluster.yml site-config/<cluster-name>/cluster.yml
  cp examples/sno-4.20-standard/nodes.yml   site-config/<cluster-name>/nodes.yml
  ```

- [ ] Export the config directory for all subsequent commands:

  ```bash
  export SITE_CONFIG_DIR=site-config
  ```

---

## Step 3: Update cluster.yml

Open `site-config/<cluster-name>/cluster.yml` and update each field:

### Identity

- [ ] `cluster_name` — your production cluster name (e.g., `prod-ocp4`)
- [ ] `base_domain` — your corporate domain (e.g., `corp.example.com`)
- [ ] `ocp_version` — target OpenShift version (e.g., `4.20`)
- [ ] `pull_secret_path` — path to Red Hat pull secret on the deployment host

### Platform

- [ ] `platform_type: baremetal` — required for HA with keepalived VIP management
  - Use `platform_type: none` only for SNO deployments
- [ ] Remove or comment out any KVM/vSphere-specific platform settings

### Network

- [ ] `machine_network_cidrs` — your production server subnet (e.g., `10.0.0.0/24`)
- [ ] `api_vips` — a free IP on the machine network for the API endpoint
- [ ] `app_vips` — a free IP on the machine network for application routes
- [ ] `cluster_network_cidr` — pod CIDR (must not overlap with machine network)
- [ ] `service_network_cidrs` — service CIDR (must not overlap)
- [ ] `rendezvous_ip` — IP of the node that bootstraps the cluster (usually `node_one`)

### DNS

- [ ] `dns_servers` — corporate DNS server IPs (not `192.168.122.1` libvirt DNS)
- [ ] `dns_search_domains` — your corporate search domains

### NTP

- [ ] `ntp_servers` — corporate NTP servers (not `0.rhel.pool.ntp.org` if restricted)

Minimal production `cluster.yml` example:

```yaml
pull_secret_path: ~/ocp-pull-secret.json
base_domain: corp.example.com
cluster_name: prod-ocp4
ocp_version: "4.20"
platform_type: baremetal

api_vips:
  - 10.0.0.100
app_vips:
  - 10.0.0.101

ntp_servers:
  - ntp.corp.example.com

dns_servers:
  - 10.0.0.53
dns_search_domains:
  - corp.example.com

cluster_network_cidr: 10.128.0.0/14
cluster_network_host_prefix: 23
service_network_cidrs:
  - 172.30.0.0/16
machine_network_cidrs:
  - 10.0.0.0/24
network_type: OVNKubernetes
rendezvous_ip: 10.0.0.21
```

---

## Step 4: Hardware Inventory

Collect the following from your physical servers before editing `nodes.yml`.

Create a hardware inventory sheet (template):

| Hostname | Role | MAC (primary NIC) | NIC name | IP | BMC IP | Disk |
|----------|------|-------------------|----------|----|--------|------|
| prod-master-1 | master | AA:BB:CC:DD:EE:01 | eno1 | 10.0.0.21 | 10.0.1.10 | /dev/nvme0n1 |
| prod-master-2 | master | AA:BB:CC:DD:EE:02 | eno1 | 10.0.0.22 | 10.0.1.11 | /dev/nvme0n1 |
| prod-master-3 | master | AA:BB:CC:DD:EE:03 | eno1 | 10.0.0.23 | 10.0.1.12 | /dev/nvme0n1 |
| prod-worker-1 | worker | AA:BB:CC:DD:EE:04 | eno1 | 10.0.0.24 | 10.0.1.13 | /dev/nvme0n1 |

How to collect MAC addresses:

```bash
# Via ipmitool (no OS required)
ipmitool -I lanplus -H <bmc-ip> -U <user> -P <pass> lan print 1 | grep "MAC Address"

# Via dmidecode (requires running OS)
sudo dmidecode -t 38

# Via ip link (requires running OS)
ip link show | grep ether
```

How to identify NIC names (requires booting into a live OS or checking BMC console):

```bash
ip link show
# or
ls /sys/class/net/
```

---

## Step 5: Update nodes.yml

Open `site-config/<cluster-name>/nodes.yml` and replace every KVM placeholder:

### Per-Node Checklist

For **each node**:

- [ ] `hostname` — production hostname (must match DNS records or be resolvable)
- [ ] `role` — `master` or `worker`
- [ ] `bmc.address` — real BMC address with correct scheme:
  - `redfish-virtualmedia://10.0.1.10/redfish/v1/Systems/System.Embedded.1` (iDRAC 9+)
  - `redfish-virtualmedia://10.0.1.11/redfish/v1/Systems/1` (HPE iLO)
  - `ipmi://10.0.1.12` (generic IPMI)
- [ ] `bmc.username` / `bmc.password` — real BMC credentials (use Ansible Vault)
- [ ] `interfaces[].name` — real interface name (`eno1`, `enp97s0f0`, etc.)
- [ ] `interfaces[].mac_address` — real MAC address
- [ ] `networkConfig.interfaces[].mac-address` — same real MAC
- [ ] `networkConfig.interfaces[].ipv4.address[].ip` — real static IP
- [ ] `networkConfig.routes.config[].next-hop-address` — real gateway IP
- [ ] `rootDeviceHints.deviceName` — real disk device (or use `wwn` for SAN)

Example production node entry:

```yaml
nodes:
  - hostname: prod-master-1
    role: master
    bmc:
      address: redfish-virtualmedia://10.0.1.10/redfish/v1/Systems/System.Embedded.1
      username: root
      password: "changeme"          # replace with Ansible Vault reference
      disableCertificateVerification: true
    rootDeviceHints:
      deviceName: /dev/nvme0n1
    interfaces:
      - name: eno1
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

### Validate NMState Syntax

```bash
# Validate networkConfig for each node (requires nmstate)
nmstatectl gc site-config/<cluster-name>/nodes.yml
```

---

## Step 6: Secure BMC Credentials

Never store BMC passwords in plaintext in `nodes.yml` on shared systems.

- [ ] Encrypt with Ansible Vault:

  ```bash
  ansible-vault encrypt_string 'your-bmc-password' --name 'bmc_password'
  # Paste output into nodes.yml password field
  ```

- [ ] Or use an environment variable pattern in `nodes.yml`:

  ```yaml
  bmc:
    password: "{{ lookup('env', 'BMC_PASSWORD') }}"
  ```

  Then export before running scripts:

  ```bash
  export BMC_PASSWORD="$(cat ~/.bmc-password)"
  ```

- [ ] Add your secrets file to `.gitignore`:

  ```bash
  echo "site-config/" >> .gitignore
  echo ".bmc-password" >> .gitignore
  ```

---

## Step 7: Corporate DNS Registration

- [ ] Register DNS records in your corporate DNS server (see [Corporate DNS Integration](corporate-dns-integration))

  Required records for `prod-ocp4.corp.example.com` with VIPs `10.0.0.100` / `10.0.0.101`:

  ```
  api.prod-ocp4.corp.example.com        A  10.0.0.100
  api-int.prod-ocp4.corp.example.com    A  10.0.0.100
  *.apps.prod-ocp4.corp.example.com     A  10.0.0.101
  ```

- [ ] Verify from the deployment host:

  ```bash
  ./hack/verify-dns-resolution.sh site-config/<cluster-name>/cluster.yml
  ```

  All records must resolve before proceeding.

---

## Step 8: KVM Validation Gate

Before deploying to physical hardware, validate the configuration on KVM. This catches YAML errors, manifest generation issues, and networking logic before touching production servers.

- [ ] Temporarily switch to a KVM-compatible version of `nodes.yml` (no real BMC, use KVM MACs and `ens3` interfaces) **or** test with an existing KVM example that is structurally similar.

- [ ] Run ISO generation to validate manifests:

  ```bash
  # Use a KVM-compatible clone of your config
  cp -r site-config/<cluster-name> examples/<cluster-name>-kvm-test
  # Edit examples/<cluster-name>-kvm-test to use KVM values
  ./hack/create-iso.sh <cluster-name>-kvm-test
  ```

- [ ] Validate deployment standards:

  ```bash
  ./hack/validate-deployment-standards.sh \
    ~/generated_assets/<cluster-name>-kvm-test <ocp-version>
  ```

- [ ] If a full KVM deploy is possible, run it:

  ```bash
  ./hack/deploy-connected-full.sh examples/<cluster-name>-kvm-test --with-router
  ```

- [ ] Confirm `oc get nodes` shows all nodes Ready before proceeding to bare metal.

---

## Step 9: Generate Production ISO

Once KVM validation passes, generate the production ISO from your `site-config`:

```bash
export SITE_CONFIG_DIR=site-config
./hack/create-iso.sh <cluster-name>
```

- [ ] ISO generated at `~/generated_assets/<cluster-name>/agent.x86_64.iso`
- [ ] SHA256 checksum recorded:

  ```bash
  sha256sum ~/generated_assets/<cluster-name>/agent.x86_64.iso > \
    ~/generated_assets/<cluster-name>/agent.x86_64.iso.sha256
  ```

---

## Step 10: Deploy to Bare Metal

Proceed to the [Bare Metal Production Guide](bare-metal-production-guide) for:

- Phase 4: ISO Delivery (virtual media / USB / PXE)
- Phase 5: Boot and Monitor
- Phase 6: Post-Install Validation

---

## Step 11: Ongoing Maintenance

### Sync with Upstream

```bash
git fetch upstream
git merge upstream/main
# Resolve conflicts in your site-config (not tracked in git, so no conflicts there)
git push origin <your-org>-production
```

### Document Your Deployment

Create `docs/organization-deployment.md` in your fork:

```markdown
# <YourOrg> OpenShift Deployment

## Cluster Inventory
| Cluster | Domain | VIPs | Nodes |
|---------|--------|------|-------|
| prod-ocp4 | corp.example.com | 10.0.0.100/101 | 3 CP + 3 W |

## Hardware Inventory
| Hostname | Role | BMC IP | MAC | IP |
|----------|------|--------|-----|----|
| prod-master-1 | master | 10.0.1.10 | AA:BB:CC:DD:EE:01 | 10.0.0.21 |

## Deployment Procedure
1. Ensure DNS records exist (see site-config/<cluster>/cluster.yml)
2. Run: export SITE_CONFIG_DIR=site-config && ./hack/create-iso.sh <cluster>
3. Deliver ISO via virtual media (see Bare Metal Production Guide)
4. Monitor: ./bin/openshift-install agent wait-for install-complete --dir ~/generated_assets/<cluster>/

## Credentials Location
- Pull secret: ~/ocp-pull-secret.json
- BMC password: Ansible Vault / ~/.bmc-password (gitignored)
- kubeconfig: ~/generated_assets/<cluster>/auth/kubeconfig
- kubeadmin password: ~/generated_assets/<cluster>/auth/kubeadmin-password
```

---

## Quick KVM → Bare Metal Diff Reference

| Field | KVM Value | Bare Metal Value |
|-------|-----------|-----------------|
| `platform_type` | `none` | `baremetal` |
| `machine_network_cidrs` | `192.168.50.0/24` | Your production subnet |
| `api_vips` | `192.168.50.x` | Production VIP |
| `app_vips` | `192.168.50.x` | Production VIP |
| `dns_servers` | `192.168.122.1` (libvirt) | Corporate DNS |
| `ntp_servers` | `0.rhel.pool.ntp.org` | Corporate NTP |
| `bmc.address` | `redfish://192.168.122.10:8000/...` (sushy) | `redfish-virtualmedia://10.0.1.x/...` (real BMC) |
| `interfaces[].name` | `ens3`, `ens4` | `eno1`, `enp97s0f0`, etc. |
| `interfaces[].mac_address` | Generated / libvirt | Real hardware MAC |
| `networkConfig` IPs | `192.168.50.x` | Real node IPs |
| `rootDeviceHints.deviceName` | `/dev/vda` | `/dev/nvme0n1`, `/dev/sda`, etc. |
