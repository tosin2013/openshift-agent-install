# OpenShift Agent Based Installer Helper

This repository provides automated tooling for OpenShift Agent-Based Installer deployments. Supports bare metal, vSphere, and platform=none deployments in SNO/3-Node/HA configurations.

## 🎯 Development Workflow

```
Development (KVM) → Fork & Adapt → Production (Bare Metal)
```

This repository is designed for:
1. **Development and testing** on KVM/libvirt (local infrastructure)
2. **Forking and customization** for your organization
3. **Production deployment** to bare metal infrastructure in your environment

📖 **New to this repo?** Start with the [Developer Guide](docs/developer-guide.md)

## ⚠️ CRITICAL: Hard Requirements for OpenShift Deployment

**Before ANY OpenShift cluster deployment, you MUST validate your environment:**

```bash
# Run comprehensive environment validation
./e2e-tests/validate_env.sh
```

This validates:
1. ✅ **VyOS Router** - All 5 VLAN networks (1924-1928) are active
2. ✅ **DNS Infrastructure** - dnsmasq running and configured
3. ✅ **System Packages** - nmstate, ansible, OpenShift CLI tools
4. ✅ **Container Tools** - podman installed
5. ✅ **SELinux** - proper configuration

**If validation fails, DO NOT proceed with deployment.** Fix the reported issues first.

### Setting Up Prerequisites

**1. VyOS Router (MANDATORY for KVM development)**

⚠️ **MANUAL CONFIGURATION REQUIRED** - VyOS deployment requires human interaction via Cockpit web console.

```bash
# Deploy VyOS router with VLAN networks (will pause for manual configuration)
ACTION=create ./hack/vyos-router.sh
```

**What to expect:**
- Script shows manual configuration instructions
- Pauses with "Press ENTER to continue..."
- Creates VyOS VM after you acknowledge
- Waits up to 30 minutes for you to complete manual configuration via Cockpit

**Manual steps required:**
1. Access Cockpit: `https://<your-host>:9090` (credentials: `cat ~/cockpit-credentials.txt`)
2. Open VyOS console: Virtual Machines → vyos-router → Console
3. Follow step-by-step guide: [docs/vyos-manual-configuration.md](docs/vyos-manual-configuration.md)

**Verify networks are active** (after manual configuration complete):
```bash
sudo virsh net-list
```

**2. DNS Configuration (MANDATORY)**

```bash
# Install dnsmasq
sudo ./hack/setup-dnsmasq.sh

# Configure DNS entries for your cluster
sudo ./hack/configure-dnsmasq-entries.sh add examples/<your-cluster>/cluster.yml

# Verify DNS resolution works
./hack/verify-dns-resolution.sh examples/<your-cluster>/cluster.yml
```

---

### ⚠️ Without these prerequisites validated, VM deployment will fail or hang indefinitely.

---

## Prerequisites

### Core Requirements

- **RHEL 9.x system** (host for KVM development or bare metal deployment)
- **OpenShift CLI Tools** - run `./download-openshift-cli.sh` then `sudo cp ./bin/* /usr/local/bin/`
- **NMState CLI** - `dnf install nmstate`
- **Ansible Core** - `dnf install ansible-core` (or Ansible Automation Platform)
- **Ansible Collections** - `ansible-galaxy install -r execution-environment/collections/requirements.yml`
- **Red Hat Pull Secret** - https://console.redhat.com/openshift/downloads#tool-pull-secret saved to `~/pull-secret.json`

### KVM Development Environment Setup

For KVM-based development and testing, you **must** have:

1. **VyOS Router** (mandatory prerequisite)
   ```bash
   # Deploy VyOS router with VLAN networks
   ACTION=create ./hack/vyos-router.sh
   ```
   - Provides VLAN networking (192.168.49.0/24 through 192.168.58.0/24)
   - Required for all example configurations
   - Manual configuration via Cockpit console required
   - See: [Developer Guide - VyOS Router Setup](docs/developer-guide.md#hard-requirement-vyos-router)

2. **Cockpit Web Interface** (for VyOS console access)
   ```bash
   sudo dnf install -y cockpit cockpit-machines
   sudo systemctl enable --now cockpit.socket
   sudo firewall-cmd --add-service=cockpit --permanent
   sudo firewall-cmd --reload
   ```
   - Access at: `https://<your-host>:9090`
   - Required for VyOS router configuration
   - Provides VM management and console access

3. **Libvirt/KVM**
   ```bash
   sudo dnf install -y qemu-kvm libvirt virt-install virt-manager
   sudo systemctl enable --now libvirtd
   ```

**📘 Complete KVM setup guide**: [Developer Guide](docs/developer-guide.md)

### Alternative: Pre-built Execution Environment

For offline/portable execution or use with Ansible Automation Platform, use the pre-built containerized Ansible Execution Environment:

```bash
# Pull latest version
podman pull quay.io/takinosh/openshift-agent-install-ee:latest

# Or pull a specific release version
podman pull quay.io/takinosh/openshift-agent-install-ee:v4.21.0

# Run playbook in container
podman run --rm -it \
  -v $(pwd):/runner \
  -v ~/pull-secret.json:/runner/pull-secret.json:ro \
  quay.io/takinosh/openshift-agent-install-ee:latest \
  ansible-playbook -e @examples/sno-4.20-standard/cluster.yml \
                   -e @examples/sno-4.20-standard/nodes.yml \
                   playbooks/create-manifests.yml
```

**EE Image Versions:**
- `latest` - Always points to the most recent release
- `vX.Y.Z` - Pinned semantic version tags (e.g., v4.21.0, v4.22.0)
- Automatically built on release tag pushes

## Supported OpenShift Versions

This tooling supports OpenShift 4.15 and newer. The `download-openshift-cli.sh` script automatically downloads the latest stable version of the OpenShift CLI tools.

Tested and validated with:
- OpenShift 4.20.x
- OpenShift 4.21.x

Examples are provided for different deployment patterns:
- `examples/serenity-sno.v60.lab.kemo.network/` - SNO with disconnected registry
- `examples/sno-4.20-standard/` - Standard SNO 4.20 deployment
- `examples/ha-4.21-disconnected/` - HA 4.21 disconnected deployment

## Version Validation and Compatibility Testing

This repository includes automated tools to validate manifest generation across multiple OpenShift versions and detect version-specific API changes.

### Quick Start

```bash
# Generate manifests for multiple OpenShift versions
./hack/generate-version-manifests.sh sno-disconnected "4.19 4.20 4.21"

# Validate manifests against deployment standards
./hack/validate-deployment-standards.sh \
  ~/generated_assets/version-compare/sno-disconnected-4.20 4.20

# Compare critical version boundaries
./hack/compare-version-manifests.sh 4.19 4.20 sno-disconnected
./hack/compare-version-manifests.sh 4.20 4.21 sno-disconnected
```

### Critical Version Boundaries

**4.19 → 4.20**: ImageDigestMirrorSet migration
- Disconnected deployments must migrate from `imageDigestSources` in install-config.yaml to standalone `ImageDigestMirrorSet` manifest

**4.20 → 4.21**: OpenShiftSDN removal
- All deployments must use `networkType: OVNKubernetes` (OpenShiftSDN removed completely)

### GitHub Actions Integration

The version validation workflow automatically runs on PRs that modify templates or examples:

```bash
# Manually trigger validation with GitHub issue creation
gh workflow run version-validation.yml \
  -f create_issues=true \
  -f examples="sno-disconnected ha-4.21-disconnected sno-4.20-standard"
```

### LLM-Powered Validation

Version validation uses **Granite-3-2-8b-instruct** LLM to provide intelligent analysis of:
- API compliance per OpenShift version
- Deployment pattern standards (SNO, 3-Node, HA)
- Connectivity requirements (connected, disconnected, proxy)
- Platform-specific configuration validation

Example validation output:
```
[PASS] Image Registry Configuration
[FAIL] Network Configuration - networkType: OpenShiftSDN deprecated for 4.21
[PASS] Platform Configuration
[PASS] Deployment Topology
```

### Documentation

- **[Version Compatibility Matrix](docs/version-compatibility-matrix.md)** - API changes, migration paths, feature support
- **[Version Validation Feature](docs/version-validation-feature.md)** - Complete feature documentation
- **[Quick Start Guide](docs/version-validation-quick-start.md)** - Step-by-step usage instructions
- **[Cheat Sheet](VERSION_VALIDATION_CHEATSHEET.md)** - Quick reference commands

## DNS Setup

This project uses **dnsmasq** as a lightweight DNS server for OpenShift cluster deployments. For each cluster, only 3 DNS records are needed:
- `api.<cluster_name>.<domain>` → API VIP
- `api-int.<cluster_name>.<domain>` → API VIP
- `*.apps.<cluster_name>.<domain>` → App VIP

### Quick DNS Setup

```bash
# Install and configure dnsmasq
sudo ./hack/setup-dnsmasq.sh

# Add DNS entries for your cluster
sudo ./hack/configure-dnsmasq-entries.sh add examples/sno-4.20-standard/cluster.yml

# Test DNS resolution
dig @localhost api.sno-4-20.example.com
```

For detailed DNS configuration, troubleshooting, and migration from FreeIPA, see [DNS Setup Guide](docs/dns-setup.md).

## E2E Testing and Bootstrap

For end-to-end testing in a KVM environment with automated infrastructure setup:

```bash
# Bootstrap complete environment (installs packages, DNS, VyOS router, etc.)
sudo ./e2e-tests/bootstrap_env.sh

# Run E2E tests
./e2e-tests/run_e2e.sh
```

The bootstrap script automatically sets up dnsmasq for DNS resolution, replacing the previous FreeIPA-based approach.

## Usage - Declarative

In the `examples` directory you'll find sample cluster configuration variables.  By defining the cluster in its own folder with the `cluster.yml` and `nodes.yml` files, you can easily template and generate the ABI ISO in one shot with:

```bash
# Optionally, change the path to the site configs from the default ./examples
export SITE_CONFIG_DIR="./site-configs"

# Create an ISO from the defined cluster.yml and nodes.yml file
./hack/create-iso.sh $FOLDER_NAME

# Available examples:
# - serenity-sno.v60.lab.kemo.network  (SNO with disconnected registry)
# - sno-4.20-standard                   (Standard SNO 4.20 connected deployment)
# - ha-4.21-disconnected                (HA 4.21 disconnected deployment)
```

This script will take those defined files, generate the templates with Ansible, create the ISO, and present next step instructions.

Alternatively, you can perform those steps manually with the instructions below.

---

## Usage - Manual

### 1. Templating Agent Based Installer Manifests

You can quickly and easily template the ABI manifests with the provided `create-manifests.yml` Ansible Playbook.

```bash=
# Make sure you're in the `playbooks` directory
cd playbooks/

# Execute the automation with your custom cluster configuration set in a YAML file
ansible-playbook -e "@your-cluster-vars.yml" create-manifests.yml
```

### 2. Creating the Agent Installer ISO

After running the automation to generate the manifests, you can create the ISO with the following:

```bash=
# Create the ISO
openshift-install agent create image --dir ./generated_manifests/<cluster_name>

# Watch the Bootstrap process
openshift-install agent wait-for bootstrap-complete --dir ./generated_manifests/<cluster_name>

# Watch the installation process
openshift-install agent wait-for install-complete --dir ./generated_manifests/<cluster_name>
```

You'll need to provide it some variables such as the following:

#### General Configuration Variables

```yaml=
# pull_secret path is the path to the pull-secret for the cluster
pull_secret_path: ~/ocp-install-pull-secret.json

# ssh_public_key_path is the path to the SSH public key to use for the cluster
# if this is not set then a new key pair will be generated
# ssh_public_key_path: ~/.ssh/id_rsa.pub

# Cluster metadata
base_domain: d70.kemo.labs
cluster_name: suki-sno

# platform_type is the type of platform to use for the cluster (baremetal, vsphere, none)
# must be none for SNO
platform_type: none

# VIPs - set as a list in case this is a dual-stack cluster
api_vips:
  - 192.168.70.46

app_vips:
  - 192.168.70.46

# Optional NTP Servers
ntp_servers:
  - deep-thought.kemo.labs

# Optional DNS Server definitions
dns_servers:
  - 192.168.42.9
  - 192.168.42.10
dns_search_domains:
  - kemo.labs
  - kemo.network

# cluster_network_cidr is the overall CIDR space for the Pods in the cluster
cluster_network_cidr: 10.128.0.0/14
# cluster_network_host_prefix is the number of bits in the cluster_network_cidr that are for each node
cluster_network_host_prefix: 23

# service_network_cidrs is the CIDR space for the Services in the cluster (ClusterIP/NodePort/LoadBalancer)
service_network_cidrs:
  - 172.30.0.0/16

# machine_network_cidr is the CIDR space for the Machines in the cluster
machine_network_cidrs:
  - 192.168.70.0/23

# network_type is the network provider for the cluster
# OpenShift 4.21+: OVNKubernetes (REQUIRED - OpenShiftSDN removed)
# OpenShift 4.15-4.20: OVNKubernetes (recommended) or OpenShiftSDN (deprecated)
network_type: OVNKubernetes

# rendezvous_ip is the IP address of the node that will be used for the bootstrap node
rendezvous_ip: 192.168.70.46

# Optional Disconnected Registry Mirror configuration
disconnected_registries:
  # Must have a direct reference to the openshift-release-dev/ocp-release and openshift-release-dev/ocp-v4.0-art-dev paths
  - target: disconn-harbor.d70.kemo.labs/quay-ptc/openshift-release-dev/ocp-release
    source: quay.io/openshift-release-dev/ocp-release
  - target: disconn-harbor.d70.kemo.labs/quay-ptc/openshift-release-dev/ocp-v4.0-art-dev
    source: quay.io/openshift-release-dev/ocp-v4.0-art-dev

  - target: disconn-harbor.d70.kemo.labs/quay-ptc
    source: quay.io
  - target: disconn-harbor.d70.kemo.labs/registry-redhat-io-ptc
    source: registry.redhat.io
  - target: disconn-harbor.d70.kemo.labs/registry-connect-redhat-com-ptc
    source: registry.connect.redhat.com

# Optional Outbound Proxy Configuration
# proxy:
#   http_proxy: http://192.168.42.31:3128
#   https_proxy: http://192.168.42.31:3128
#   no_proxy:
#     - .svc.cluster.local
#     - 192.168.0.0/16
#     - .kemo.network
#     - .kemo.labs

# Optional Additional CA Root Trust Bundle
additional_trust_bundle_policy: Always
additional_trust_bundle: |
  -----BEGIN CERTIFICATE-----
  MIIG3TCCBMWgAwIBAgIUJSmf6Ooxg8uIwfFlHQYFQl5KMSYwDQYJKoZIhvcNAQEL
  BQAwgcMxIzAhBgkqhkiG9w0BCQEWFG5hLXNlLXJ0b0ByZWRoYXQuY29tMQswCQYD
  VQQGEwJVUzEXMBUGA1UECAwOTm9ydGggQ2Fyb2xpbmExEDAOBgNVBAcMB1JhbGVp
  Z2gxFDASBgNVBAoMC05vdCBSZWQgSGF0MRswGQYDVQQLDBJTRSBSVE8gTm90IElu
  Zm9TZWMxMTAvBgNVBAMMKFNvdXRoZWFzdCBSVE8gUm9vdCBDZXJ0aWZpY2F0ZSBB
  dXRob3JpdHkwHhcNMjIwMzA3MDAwNTA5WhcNNDIwOTE4MDAwNTA5WjCBwzEjMCEG
  CSqGSIb3DQEJARYUbmEtc2UtcnRvQHJlZGhhdC5jb20xCzAJBgNVBAYTAlVTMRcw
  FQYDVQQIDA5Ob3J0aCBDYXJvbGluYTEQMA4GA1UEBwwHUmFsZWlnaDEUMBIGA1UE
  CgwLTm90IFJlZCBIYXQxGzAZBgNVBAsMElNFIFJUTyBOb3QgSW5mb1NlYzExMC8G
  A1UEAwwoU291dGhlYXN0IFJUTyBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eTCC
  AiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBANGozAIcO/PB4uIwI31kuiGW
  j+Nm+ZJruiOaG0P/Z99F/i7e9aOrQD8BHmlGOp9R0sdabrmidvowLE69g5z4+Q0E
  4+Uvt4GX/DYOBVR/xuV3E8LFJN1zXXbFtXJlSBz3PLWNaySAcg55a/Pwz68EWFA1
  H2RL5I/sPDpFiz0POnZ+MJ15BCQ2P5YCN7lsHSkmbRonz349WAhvE5OM6qIrBw/J
  Y6AJtAuEVnyiKoilqEvg0Gz6mSnog2yJY1CktMmP7S6/DPuJpTrw74027mp+g1Pm
  hRf8jVNsLNM7VPMo8AIodTCIc+Gv3EJ1bjMc/nF1F3K5jBQZrfe21QpgMKyeY/RV
  FvoHaCy2Miw2RFE9HOo0rwnOohiXlZM6ZSL5AUfDH2tSlJJNr08fE4op48UMIahz
  2My117CKFE2gRe5bhEEJAO9gOqsq1oOT4Oi3TP+lysjAVAIcnNFhQ1uRmJ93Y8HU
  qOCOgH+PV7N+kNtOwy8y32+Czh6njL09IbR8TNH2fOXYVt7JDZjnfU+FdzagNWc5
  C+aQCdpKIMig5OuU81Ac8k6+Aj0CBawOcBI63oxV/GWkUJPgQytmyo/2zswD9FcD
  yIVL1nvJOwVWNEyOLtDWmEzSda6CVLFFQnAw35qgS94Hc7IS3nQW6XFEGj7xzTmd
  b2xoEKhgx+dPw5h7AYPHAgMBAAGjgcYwgcMwHQYDVR0OBBYEFDzw4uwWVqsqJDNM
  2Rz+ztC/ZgUNMB8GA1UdIwQYMBaAFDzw4uwWVqsqJDNM2Rz+ztC/ZgUNMA8GA1Ud
  EwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgGGMGAGA1UdHwRZMFcwVaBToFGGT2h0
  dHBzOi8vcmVkLWhhdC1zZS1ydG8uZ2l0aHViLmlvOjQ0My9jcmxzL3NlLXJ0by1y
  b290LWNlcnRpZmljYXRlLWF1dGhvcml0eS5jcmwwDQYJKoZIhvcNAQELBQADggIB
  AFu7g/6ghP0PaLsjjAPW+QWqv9tMk8w0MKbKgVeUOX5xz1I7Svc1ndi2dMcYwK8W
  pgF4bVR8T17NE3V0/xy6BGktN9BtErI9guk3zb3GBIx/1b3Mgce7134nGvhi4ik7
  ziNB2WYwOgwxEpSA1eS68WNMT6pWZvosEZu9AKMUQ8ULsfxiKwVT+Pj171JxIvDV
  blhilnOrBap7sP1XwS9OPcQhm0AMtFEj/zhadO1h2ynwKjd/VE2/nskfLvm1dXK5
  DtdHsCdtT/hJ0XQjLkwOkl87WHZsy4u6kxQzxKH+LDWfSOCOksYD86fBdfQC66gL
  7yJpX9BznEaGCKgFam3m42eH9msCIV/JTTLUbsrwzaEhxBLtpUeo6j1xF2khF8Ri
  45Sir0yotZE0i72S4TLllkgQx9AaOiRAWvtYkcP1TBJnzL5viac3pkTnPjLiQ9BO
  V8+9Y1O6wU0KTbLdMaz+Wfpti1lcnphQDsMJoGTe6wl3QpAK2jz32aFMoTkoyDK5
  MwQqiTMkyOkPCiY4Rq1RRnYGIU7Ob125IjaFqyLvG9KWuiFsH7yn2nVH5kwy7O75
  7yx0UiBuGVfG66I09YM1jR9nq7mKv30Sq1Fa/X76XyxDBGk0rLRCw02Ziq0rS8WG
  S5kIfhw8FM52x6RHCwRicArO8HSTCf4ueEkFL7yj5xSI
  -----END CERTIFICATE-----
```

#### SNO Deployment

```yaml=
# Node Counts the installer will expect
control_plane_replicas: 1
app_node_replicas: 0

# nodes defines the nodes to use for the cluster
nodes:
  - hostname: sno
    rootDeviceHints:
      deviceName: /dev/nvme0n1
    interfaces:
      - name: enp97s0f0
        mac_address: D0:50:99:DD:58:95
    networkConfig:
      interfaces:
        - name: enp97s0f0.70
          type: vlan
          state: up
          vlan:
            id: 70
            base-iface: enp97s0f0
          ipv4:
            enabled: true
            address:
              - ip: 192.168.70.46
                prefix-length: 23
            dhcp: false
        - name: enp97s0f0
          type: ethernet
          state: up
          mac-address: D0:50:99:DD:58:95
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: 192.168.70.1
            next-hop-interface: enp97s0f0.70
            table-id: 254
```

#### 3 Node Cluster Deployment

```yaml=
# Node Counts the installer will expect
control_plane_replicas: 3
app_node_replicas: 0

# nodes defines the nodes to use for the cluster
nodes:
  - hostname: node1
    role: master
    rootDeviceHints:
      deviceName: /dev/nvme0n1
    interfaces:
      - name: enp97s0f0
        mac_address: D0:50:99:DD:58:95
    networkConfig:
      interfaces:
        - name: enp97s0f0
          type: ethernet
          state: up
          mac-address: D0:50:99:DD:58:95
          ipv4:
            enabled: true
            address:
              - ip: 192.168.70.46
                prefix-length: 23
            dhcp: false
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: 192.168.70.1
            next-hop-interface: enp97s0f0
            table-id: 254

  - hostname: node2
    role: master
    rootDeviceHints:
      deviceName: /dev/nvme0n1
    interfaces:
      - name: enp97s0f0
        mac_address: D0:50:99:DD:58:96
    networkConfig:
      interfaces:
        - name: enp97s0f0
          type: ethernet
          state: up
          mac-address: D0:50:99:DD:58:96
          ipv4:
            enabled: true
            address:
              - ip: 192.168.70.47
                prefix-length: 23
            dhcp: false
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: 192.168.70.1
            next-hop-interface: enp97s0f0
            table-id: 254

  - hostname: node3
    role: master
    rootDeviceHints:
      deviceName: /dev/nvme0n1
    interfaces:
      - name: enp97s0f0
        mac_address: D0:50:99:DD:58:97
    networkConfig:
      interfaces:
        - name: enp97s0f0
          type: ethernet
          state: up
          mac-address: D0:50:99:DD:58:97
          ipv4:
            enabled: true
            address:
              - ip: 192.168.70.48
                prefix-length: 23
            dhcp: false
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: 192.168.70.1
            next-hop-interface: enp97s0f0
            table-id: 254
```

#### HA Cluster Deployment

```yaml=
# Node Counts the installer will expect
control_plane_replicas: 3
app_node_replicas: 2

# nodes defines the nodes to use for the cluster
nodes:
  - hostname: cp1
    role: master
    rootDeviceHints:
      deviceName: /dev/nvme0n1
    interfaces:
      - name: enp97s0f0
        mac_address: D0:50:99:DD:58:95
    networkConfig:
      interfaces:
        - name: enp97s0f0
          type: ethernet
          state: up
          mac-address: D0:50:99:DD:58:95
          ipv4:
            enabled: true
            address:
              - ip: 192.168.70.46
                prefix-length: 23
            dhcp: false
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: 192.168.70.1
            next-hop-interface: enp97s0f0
            table-id: 254

  - hostname: cp2
    role: master
    rootDeviceHints:
      deviceName: /dev/nvme0n1
    interfaces:
      - name: enp97s0f0
        mac_address: D0:50:99:DD:58:96
    networkConfig:
      interfaces:
        - name: enp97s0f0
          type: ethernet
          state: up
          mac-address: D0:50:99:DD:58:96
          ipv4:
            enabled: true
            address:
              - ip: 192.168.70.47
                prefix-length: 23
            dhcp: false
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: 192.168.70.1
            next-hop-interface: enp97s0f0
            table-id: 254

  - hostname: cp3
    role: master
    rootDeviceHints:
      deviceName: /dev/nvme0n1
    interfaces:
      - name: enp97s0f0
        mac_address: D0:50:99:DD:58:97
    networkConfig:
      interfaces:
        - name: enp97s0f0
          type: ethernet
          state: up
          mac-address: D0:50:99:DD:58:97
          ipv4:
            enabled: true
            address:
              - ip: 192.168.70.48
                prefix-length: 23
            dhcp: false
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: 192.168.70.1
            next-hop-interface: enp97s0f0
            table-id: 254

  - hostname: app1
    role: worker
    rootDeviceHints:
      deviceName: /dev/nvme0n1
    interfaces:
      - name: enp97s0f0
        mac_address: D0:50:99:DD:58:98
    networkConfig:
      interfaces:
        - name: enp97s0f0
          type: ethernet
          state: up
          mac-address: D0:50:99:DD:58:98
          ipv4:
            enabled: true
            address:
              - ip: 192.168.70.49
                prefix-length: 23
            dhcp: false
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: 192.168.70.1
            next-hop-interface: enp97s0f0
            table-id: 254

  - hostname: app2
    role: worker
    rootDeviceHints:
      deviceName: /dev/nvme0n1
    interfaces:
      - name: enp97s0f0
        mac_address: D0:50:99:DD:58:99
    networkConfig:
      interfaces:
        - name: enp97s0f0
          type: ethernet
          state: up
          mac-address: D0:50:99:DD:58:99
          ipv4:
            enabled: true
            address:
              - ip: 192.168.70.50
                prefix-length: 23
            dhcp: false
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: 192.168.70.1
            next-hop-interface: enp97s0f0
            table-id: 254
```

---

## NMState Configuration Examples

### VLAN

```yaml=
nodes:
  - hostname: sno
    rootDeviceHints:
      deviceName: /dev/nvme0n1
    interfaces:
      - name: enp97s0f0
        mac_address: D0:50:99:DD:58:95
    networkConfig:
      interfaces:
        - name: enp97s0f0.70
          type: vlan
          state: up
          vlan:
            id: 70
            base-iface: enp97s0f0
          ipv4:
            enabled: true
            address:
              - ip: 192.168.70.46
                prefix-length: 23
            dhcp: false
        - name: enp97s0f0
          type: ethernet
          state: up
          mac-address: D0:50:99:DD:58:95
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: 192.168.70.1
            next-hop-interface: enp97s0f0.70
            table-id: 254
```

### Bond

```yaml=
nodes:
  - hostname: sno
    rootDeviceHints:
      deviceName: /dev/nvme0n1
    interfaces:
      - name: enp97s0f0
        mac_address: D0:50:99:DD:58:95
      - name: enp97s0f1
        mac_address: D0:50:99:DD:58:96
    networkConfig:
      interfaces:
        - name: bond0
          type: bond
          state: up
          ipv4:
            address:
              - ip: 192.168.70.46
                prefix-length: 23
            dhcp: false
            enabled: true
          link-aggregation:
            # mode=1 active-backup
            # mode=2 balance-xor
            # mode=4 802.3ad
            # mode=5 balance-tlb
            # mode=6 balance-alb
            mode: 802.3ad
            port:
              - enp97s0f0
              - enp97s0f1

        - name: enp97s0f0
          type: ethernet
          state: up
          mac-address: D0:50:99:DD:58:95
        - name: enp97s0f1
          type: ethernet
          state: up
          mac-address: D0:50:99:DD:58:96
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: 192.168.70.1
            next-hop-interface: bond0
            table-id: 254
```

### Bond + VLAN

```yaml=
nodes:
  - hostname: sno
    rootDeviceHints:
      deviceName: /dev/nvme0n1
    interfaces:
      - name: enp97s0f0
        mac_address: D0:50:99:DD:58:95
      - name: enp97s0f1
        mac_address: D0:50:99:DD:58:96
    networkConfig:
      interfaces:
        - name: bond0.70
          type: vlan
          state: up
          vlan:
            id: 70
            base-iface: bond0
          ipv4:
            enabled: true
            address:
              - ip: 192.168.70.46
                prefix-length: 23
            dhcp: false

        - name: bond0
          type: bond
          state: up
          link-aggregation:
            # mode=1 active-backup
            # mode=2 balance-xor
            # mode=4 802.3ad
            # mode=5 balance-tlb
            # mode=6 balance-alb
            mode: 802.3ad
            port:
              - enp97s0f0
              - enp97s0f1

        - name: enp97s0f0
          type: ethernet
          state: up
          mac-address: D0:50:99:DD:58:95
        - name: enp97s0f1
          type: ethernet
          state: up
          mac-address: D0:50:99:DD:58:96
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: 192.168.70.1
            next-hop-interface: bond0.70
            table-id: 254
```
