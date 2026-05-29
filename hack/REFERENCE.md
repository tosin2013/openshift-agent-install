# Script Reference

**Purpose**: Complete reference for all automation scripts in the `hack/` directory.

**Organization**: Scripts are grouped by function (ISO generation, deployment, DNS management, testing, etc.) with usage examples, parameters, and troubleshooting tips.

**Quick Reference**:
- 🔧 [ISO Generation & Configuration](#iso-generation--configuration)
- 🚀 [Deployment Scripts](#deployment-scripts)
- 🗑️ [Cleanup & Destroy](#cleanup--destroy)
- 🌐 [DNS Management](#dns-management)
- 🔌 [External Access & Networking](#external-access--networking)
- ✅ [Validation & Testing](#validation--testing)
- 🛠️ [Utility Scripts](#utility-scripts)

---

## ISO Generation & Configuration

### create-iso.sh

**Purpose**: Generate Agent-Based Installer ISO from cluster configuration

**Usage**:
```bash
./hack/create-iso.sh <cluster-config-name>
```

**Parameters**:
- `cluster-config-name`: Directory name in `examples/` or `site-config/` containing `cluster.yml` and `nodes.yml`

**Environment Variables**:
- `SITE_CONFIG_DIR`: Location of cluster configs (default: `examples`)
- `GENERATED_ASSET_PATH`: Output directory for ISOs and manifests (default: `~/generated_assets`)

**Examples**:
```bash
# Generate ISO for SNO deployment with 4.20
./hack/create-iso.sh sno-4.20-standard

# Generate ISO for HA deployment
./hack/create-iso.sh ha-4.21-disconnected

# Use custom config directory
SITE_CONFIG_DIR=site-config ./hack/create-iso.sh my-production-cluster

# Custom output location
GENERATED_ASSET_PATH=/mnt/isos ./hack/create-iso.sh sno-bond0-signal-vlan
```

**How It Works**:
1. Extracts `ocp_version` from `cluster.yml`
2. Downloads correct OpenShift CLI tools (if not present)
3. Validates version match between cluster config and installed binaries
4. Runs Ansible playbook to template manifests
5. Generates ISO using `openshift-install agent create image`
6. Outputs post-installation instructions

**Troubleshooting**:
- **"No site config folder specified"**: Missing cluster config argument
  ```bash
  # Fix: Provide config directory name
  ./hack/create-iso.sh sno-4.20-standard
  ```
- **"Pull Secret Not Found"**: Download from console.redhat.com
  ```bash
  # Fix: Download pull secret to ~/pull-secret.json
  # Or update pull_secret_path in cluster.yml
  ```
- **Version mismatch warning**: `ocp_version` doesn't match installed binaries
  ```bash
  # Fix: Remove binaries and regenerate
  rm -rf ./bin && ./hack/create-iso.sh <cluster-config>
  ```

**Related**:
- [Configuration Guide](/docs/configuration-guide.md)
- [Installation Guide](/docs/installation-guide.md)
- ADR-005: ISO Creation and Asset Management

---

### generate-version-manifests.sh

**Purpose**: Generate OpenShift manifests for multiple versions in parallel

**Usage**:
```bash
./hack/generate-version-manifests.sh <cluster-config-name> <ocp-version>
```

**Parameters**:
- `cluster-config-name`: Config directory name
- `ocp-version`: Target version (e.g., "4.19", "4.20", "4.21")

**Environment Variables**:
- `SITE_CONFIG_DIR`: Config location (default: `examples`)
- `GENERATED_ASSET_PATH`: Output directory

**Examples**:
```bash
# Generate manifests for 4.21
./hack/generate-version-manifests.sh sno-4.20-standard 4.21

# Generate for multiple versions (run in parallel)
for v in 4.19 4.20 4.21; do
  ./hack/generate-version-manifests.sh ha-4.21-disconnected $v &
done
wait
```

**Related**:
- [Version Compatibility Matrix](/docs/version-compatibility-matrix.md)
- ADR-018: OpenShift Version Compatibility Validation

---

### compare-version-manifests.sh

**Purpose**: Compare manifests across OpenShift versions to identify breaking changes

**Usage**:
```bash
./hack/compare-version-manifests.sh <cluster-name> <version1> <version2>
```

**Examples**:
```bash
# Compare 4.20 vs 4.21 manifests
./hack/compare-version-manifests.sh sno-4-20 4.20 4.21

# Review differences before upgrade
./hack/compare-version-manifests.sh ha-4-21 4.20 4.21 | grep -E "^[\+\-]"
```

---

## Deployment Scripts

### deploy-on-kvm.sh

**Purpose**: Deploy OpenShift VMs to KVM/libvirt with Redfish BMC emulation

**Usage**:
```bash
./hack/deploy-on-kvm.sh <nodes-yml-path> [--redfish]
```

**Parameters**:
- `nodes-yml-path`: Path to nodes.yml file (e.g., `examples/sno-bond0-signal-vlan/nodes.yml`)
- `--redfish`: (Optional) Enable Redfish BMC emulation via sushy-tools

**Environment Variables**:
- `CLUSTER_NAME`: Override cluster name (default: extracted from cluster.yml)
- `GENERATED_ASSET_PATH`: Location of ISOs (default: `~/generated_assets`)
- `LIBVIRT_NETWORK`: Primary network (default: `network=1924,model=e1000e`)
- `LIBVIRT_NETWORK_TWO`: Secondary network (default: same as primary)

**Examples**:
```bash
# Deploy SNO with Redfish
./hack/deploy-on-kvm.sh examples/sno-bond0-signal-vlan/nodes.yml --redfish

# Deploy HA cluster
./hack/deploy-on-kvm.sh examples/cnv-bond0-tagged/nodes.yml --redfish

# Use custom cluster name
CLUSTER_NAME=my-sno ./hack/deploy-on-kvm.sh examples/sno-4.20-standard/nodes.yml
```

**How It Works**:
1. Validates ISO exists in `${GENERATED_ASSET_PATH}/${CLUSTER_NAME}/`
2. Configures DNS forwarders in libvirt network
3. Adds cluster DNS entries (api.*, *.apps.*) to libvirt dnsmasq
4. Configures host to use libvirt DNS
5. Creates VMs with specifications from nodes.yml
6. Registers VMs with Redfish API (if --redfish)
7. Starts VMs and boots from agent ISO

**Prerequisites**:
- ISO generated via `create-iso.sh`
- VyOS router deployed (for VLAN networks)
- Libvirt/KVM configured

**Troubleshooting**:
- **"Please generate the agent.iso first"**: Run `create-iso.sh` first
- **"DNS entries already exist"**: Benign - DNS already configured from previous run
- **Redfish registration fails**: Check sushy-emulator container
  ```bash
  podman ps | grep sushy-emulator
  systemctl --user status sushy-emulator
  ```

**Related**:
- [Developer Guide](/docs/developer-guide.md)
- [Deployment Patterns](/docs/deployment-patterns.md)
- ADR-007: Virtual Infrastructure Testing

---

### deploy-ha-full.sh

**Purpose**: Full HA cluster deployment workflow (ISO generation + KVM deployment)

**Usage**:
```bash
./hack/deploy-ha-full.sh <cluster-config-name>
```

**Examples**:
```bash
# Deploy HA cluster (all-in-one)
./hack/deploy-ha-full.sh cnv-bond0-tagged

# With custom config directory
SITE_CONFIG_DIR=site-config ./hack/deploy-ha-full.sh my-ha-cluster
```

**How It Works**:
1. Runs `create-iso.sh` to generate ISO
2. Runs `deploy-on-kvm.sh` to create VMs
3. Monitors installation progress
4. Outputs cluster credentials and access info

---

### deploy-connected-full.sh

**Purpose**: Full connected deployment for SNO or HA clusters

**Usage**:
```bash
./hack/deploy-connected-full.sh <cluster-config-name>
```

**Examples**:
```bash
# Deploy SNO with all steps
./hack/deploy-connected-full.sh sno-4.20-standard

# Deploy HA cluster
./hack/deploy-connected-full.sh ha-4.21-disconnected
```

---

## Cleanup & Destroy

### destroy-on-kvm.sh

**Purpose**: Destroy OpenShift VMs and cleanup DNS entries

**Usage**:
```bash
./hack/destroy-on-kvm.sh <nodes-yml-path>
```

**Parameters**:
- `nodes-yml-path`: Same nodes.yml used for deployment

**Examples**:
```bash
# Destroy SNO deployment
./hack/destroy-on-kvm.sh examples/sno-bond0-signal-vlan/nodes.yml

# Destroy HA cluster
./hack/destroy-on-kvm.sh examples/cnv-bond0-tagged/nodes.yml
```

**What It Deletes**:
- VM domains (virsh undefine)
- VM disk images (*.qcow2)
- ODF storage disks (*-odf.qcow2)
- DNS entries from libvirt network
- Agent ISO (agent.x86_64.iso)

**Caution**: Irreversible operation. Backup any data before destroying.

---

## DNS Management

### setup-dnsmasq.sh

**Purpose**: Install and configure dnsmasq DNS server for OpenShift deployments

**Usage**:
```bash
sudo ./hack/setup-dnsmasq.sh
```

**What It Does**:
1. Installs dnsmasq package
2. Configures dnsmasq for OpenShift cluster DNS
3. Opens firewall ports (53/tcp, 53/udp)
4. Starts and enables dnsmasq service

**Prerequisites**: Root/sudo access

**Examples**:
```bash
# Install dnsmasq (first-time setup)
sudo ./hack/setup-dnsmasq.sh

# Verify dnsmasq is running
sudo systemctl status dnsmasq
```

**Troubleshooting**:
- **Port 53 already in use**: Another DNS server (systemd-resolved) may be running
  ```bash
  # Check what's using port 53
  sudo ss -lnp | grep :53
  
  # Stop conflicting service
  sudo systemctl stop systemd-resolved
  sudo systemctl disable systemd-resolved
  ```

**Related**:
- [DNS Setup Guide](/docs/dns-setup.md)
- ADR-019: Automated DNS Configuration with dnsmasq

---

### configure-dnsmasq-entries.sh

**Purpose**: Manage DNS entries in libvirt dnsmasq for OpenShift clusters

**Usage**:
```bash
sudo ./hack/configure-dnsmasq-entries.sh <action> <cluster-yml-path>
```

**Parameters**:
- `action`: `add`, `remove`, or `list`
- `cluster-yml-path`: Path to cluster.yml

**Examples**:
```bash
# Add DNS entries for cluster
sudo ./hack/configure-dnsmasq-entries.sh add examples/sno-4.20-standard/cluster.yml

# Remove DNS entries
sudo ./hack/configure-dnsmasq-entries.sh remove examples/sno-4.20-standard/cluster.yml

# List current DNS entries
sudo ./hack/configure-dnsmasq-entries.sh list
```

**DNS Entries Created**:
- `api.<cluster-name>.<base-domain>` → API VIP
- `*.apps.<cluster-name>.<base-domain>` → App VIP (common routes)
- Individual route DNS entries (console, oauth, etc.)

**Troubleshooting**:
- **"error: there is already at least one DNS HOST record"**: Entry exists (safe to ignore)
- **DNS not resolving**: Check libvirt network
  ```bash
  sudo virsh net-dumpxml default | grep -A 5 "<dns"
  dig @192.168.122.1 api.<cluster>.<domain>
  ```

---

### verify-dns-resolution.sh

**Purpose**: Test DNS resolution for cluster endpoints

**Usage**:
```bash
./hack/verify-dns-resolution.sh <cluster-yml-path>
```

**Examples**:
```bash
# Verify DNS for cluster
./hack/verify-dns-resolution.sh examples/sno-4.20-standard/cluster.yml

# Test specific DNS server
dig @192.168.122.1 api.sno-4-20.example.com
```

**Checks**:
- API endpoint resolution
- Wildcard apps domain resolution
- DNS server accessibility
- Forward and reverse lookups

---

## External Access & Networking

### configure-external-access.sh

**Purpose**: One-command setup for external access (HAProxy + Route53 + Let's Encrypt)

**Usage**:
```bash
./hack/configure-external-access.sh <cluster-yml-path>
```

**Prerequisites**:
- Environment variables OR .env file:
  - `EXTERNAL_IP`: Public IP of host
  - `AWS_ACCESS_KEY_ID`: AWS credentials
  - `AWS_SECRET_ACCESS_KEY`: AWS secret
  - `EMAIL`: Email for Let's Encrypt
  - `KUBECONFIG`: Path to cluster kubeconfig

**Examples**:
```bash
# Using .env file (recommended)
cp .env.example .env
vim .env  # Add credentials
./hack/configure-external-access.sh examples/sno-bond0-signal-vlan/cluster.yml

# Using environment variables
export EXTERNAL_IP="203.0.113.10"
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."
export EMAIL="admin@example.com"
export KUBECONFIG=~/generated_assets/sno1/auth/kubeconfig
./hack/configure-external-access.sh examples/sno-bond0-signal-vlan/cluster.yml
```

**What It Configures**:
1. HAProxy forwarder (traffic routing)
2. Route53 DNS records (api.*, *.apps.*)
3. Let's Encrypt certificates (trusted TLS)

**Related**:
- [HAProxy Forwarder Guide](/docs/haproxy-forwarder-guide.md)
- Individual scripts: `configure-haproxy-forwarder.sh`, `configure-route53-dns.sh`, `configure-letsencrypt-certs.sh`

---

### configure-haproxy-forwarder.sh

**Purpose**: Deploy HAProxy to forward traffic from public IP to cluster VIPs

**Usage**:
```bash
export EXTERNAL_IP="<your-public-ip>"
./hack/configure-haproxy-forwarder.sh <cluster-yml-path>
```

**Examples**:
```bash
# Configure HAProxy for SNO
export EXTERNAL_IP="203.0.113.10"
./hack/configure-haproxy-forwarder.sh examples/sno-4.20-standard/cluster.yml
```

---

### configure-route53-dns.sh

**Purpose**: Manage Route53 DNS records for external cluster access

**Usage**:
```bash
./hack/configure-route53-dns.sh <action> <cluster-yml-path>
```

**Parameters**:
- `action`: `add` or `remove`

**Prerequisites**:
- AWS credentials in environment
- Route53 hosted zone for base domain

**Examples**:
```bash
# Add Route53 DNS records
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."
export EXTERNAL_IP="203.0.113.10"
./hack/configure-route53-dns.sh add examples/sno-bond0-signal-vlan/cluster.yml

# Remove DNS records
./hack/configure-route53-dns.sh remove examples/sno-bond0-signal-vlan/cluster.yml
```

---

### configure-letsencrypt-certs.sh

**Purpose**: Obtain and install Let's Encrypt certificates for cluster

**Usage**:
```bash
export EMAIL="<your-email>"
export KUBECONFIG=<path-to-kubeconfig>
./hack/configure-letsencrypt-certs.sh
```

**Prerequisites**:
- Cluster fully installed
- DNS records pointing to cluster

**Examples**:
```bash
# Get Let's Encrypt certs
export EMAIL="admin@example.com"
export KUBECONFIG=~/generated_assets/sno1/auth/kubeconfig
./hack/configure-letsencrypt-certs.sh
```

---

### vyos-router.sh

**Purpose**: Deploy VyOS router VM with VLAN support for KVM networking

**Usage**:
```bash
ACTION=<create|destroy> ./hack/vyos-router.sh
```

**Parameters**:
- `ACTION`: `create` or `destroy` (environment variable)

**Examples**:
```bash
# Create VyOS router
ACTION=create ./hack/vyos-router.sh

# Destroy VyOS router
ACTION=destroy ./hack/vyos-router.sh
```

**Manual Configuration Required**:
VyOS deployment requires manual configuration via Cockpit console. See [VyOS Manual Configuration Guide](/docs/vyos-manual-configuration.md).

**What It Creates**:
- VyOS VM with 2 NICs (external + internal)
- 5 VLAN libvirt networks (1924-1928)
- Static routes on hypervisor to VLAN networks

**Related**:
- [Networking Architecture](/docs/networking-architecture.md)
- CLAUDE.md: Critical VyOS deployment warnings

---

### configure-lvm.sh

**Purpose**: Configure LVM storage for OpenShift Data Foundation (ODF)

**Usage**:
```bash
./hack/configure-lvm.sh
```

**What It Does**:
- Creates LVM volume groups for ODF
- Configures storage classes
- Sets up CSI driver

---

## Validation & Testing

### validate-kvm-examples.sh

**Purpose**: Validate all KVM example configurations for DNS, VLAN, and network compliance

**Usage**:
```bash
./hack/validate-kvm-examples.sh
```

**What It Checks**:
- DNS servers = 192.168.122.1 (libvirt dnsmasq)
- Machine network = 192.168.50.0/24 (VLAN 1924)
- API/App VIPs in correct network range
- VLAN ID = 1924
- Gateway = 192.168.50.1 (VyOS)
- OCP version presence

**Examples**:
```bash
# Validate all examples
./hack/validate-kvm-examples.sh

# Check specific patterns
./hack/validate-kvm-examples.sh | grep "❌ FAILED"
./hack/validate-kvm-examples.sh | grep "OCP Version"
```

**Output**:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📁 sno-bond0-signal-vlan
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✅ OCP Version: 4.20
  ✅ DNS: 192.168.122.1
  ✅ Network: 192.168.50.0/24
  ✅ API VIP: 192.168.50.21
  ✅ App VIP: 192.168.50.21
  ✅ PASSED
```

**Related**:
- [Reference Configurations](/docs/reference-configurations.md)

---

### validate-deployment-standards.sh

**Purpose**: Validate cluster deployment against version-specific standards

**Usage**:
```bash
./hack/validate-deployment-standards.sh <generated-assets-dir> <ocp-version>
```

**Parameters**:
- `generated-assets-dir`: Path to generated assets (e.g., `~/generated_assets/sno-4-20`)
- `ocp-version`: Target version (4.19, 4.20, 4.21)

**Examples**:
```bash
# Validate 4.20 deployment
./hack/validate-deployment-standards.sh ~/generated_assets/sno-4-20 4.20

# Validate 4.21 with strict checks
./hack/validate-deployment-standards.sh ~/generated_assets/ha-4-21 4.21
```

**Checks**:
- Network type (OVNKubernetes required for 4.21+)
- ImageDigestMirrorSet vs ImageContentSourcePolicy (4.20+ boundary)
- Platform type compliance
- Deployment pattern (SNO, 3-node, HA) validation

**Related**:
- [Deployment Standards: 4.19](/docs/deployment-standards-4.19.md)
- [Deployment Standards: 4.20](/docs/deployment-standards-4.20.md)
- [Deployment Standards: 4.21](/docs/deployment-standards-4.21.md)
- ADR-018: OpenShift Version Compatibility Validation

---

### pre-release-validation.sh

**Purpose**: Comprehensive pre-release validation across versions and platforms

**Usage**:
```bash
./hack/pre-release-validation.sh
```

**What It Tests**:
- Manifest generation for all examples
- Version compatibility (4.19, 4.20, 4.21)
- Platform compliance (baremetal, vsphere, none, nutanix)
- Network type enforcement
- Deployment standards validation

**Examples**:
```bash
# Run full validation suite
./hack/pre-release-validation.sh

# Save validation report
./hack/pre-release-validation.sh > validation-report.txt 2>&1
```

**Related**:
- GitHub Issue #31: Pre-Release Validation
- [Version Compatibility Matrix](/docs/version-compatibility-matrix.md)

---

### watch-and-reboot-kvm-vms.sh

**Purpose**: Monitor and auto-reboot KVM VMs if needed

**Usage**:
```bash
./hack/watch-and-reboot-kvm-vms.sh
```

**Use Case**: Debugging VM boot issues during development

---

### test-libvirt-ssh.sh

**Purpose**: Test libvirt SSH connectivity for remote KVM hosts

**Usage**:
```bash
./hack/test-libvirt-ssh.sh
```

---

## Utility Scripts

### fix-kvm-dns.sh

**Purpose**: Batch update DNS servers in all KVM example configurations

**Usage**:
```bash
./hack/fix-kvm-dns.sh
```

**What It Does**:
- Updates `dns_servers` in all `examples/*/cluster.yml` to 192.168.122.1
- Creates .bak backups before modification
- Validates changes with `validate-kvm-examples.sh`

**Examples**:
```bash
# Fix DNS in all examples
./hack/fix-kvm-dns.sh

# Verify changes
git diff examples/*/cluster.yml | grep dns_servers
```

---

### update-adr-navigation.sh

**Purpose**: Add Jekyll navigation frontmatter to all ADR files

**Usage**:
```bash
./hack/update-adr-navigation.sh
```

**What It Does**:
- Adds `parent: ADRs` and `nav_order: <number>` to all ADR markdown files
- Extracts ADR number and title automatically
- Updates existing frontmatter if present

**Examples**:
```bash
# Update all ADRs
./hack/update-adr-navigation.sh

# Check results
git diff docs/adr/*.md
```

---

### configure-sushy-unix.sh

**Purpose**: Configure sushy-tools for Redfish BMC emulation

**Usage**:
```bash
./hack/configure-sushy-unix.sh
```

**What It Does**:
- Configures sushy-emulator for libvirt
- Sets up systemd service
- Enables Redfish API on port 8000

**Related**:
- [BMC Management Guide](/docs/bmc-management.md)
- ADR-008: BMC Management and Automation

---

### configure-gui.sh

**Purpose**: Configure GUI tools for virtual machine management

**Usage**:
```bash
./hack/configure-gui.sh
```

**What It Installs**:
- virt-manager (if not on RHEL 10)
- cockpit-machines
- VNC/SPICE viewers

---

## Legacy/FreeIPA Scripts (Deprecated)

The following scripts are **deprecated** in favor of dnsmasq-based DNS automation:

- `deploy-freeipa.sh` - FreeIPA deployment (use `setup-dnsmasq.sh` instead)
- `configure_dns_entries.sh` - FreeIPA DNS management (use `configure-dnsmasq-entries.sh`)
- `example.freeipa_vars.sh` - FreeIPA configuration template

**Migration**: See [DNS Automation Guide](/DNS_AUTOMATION.md) and ADR-019.

---

## Common Patterns

### Standard Deployment Workflow

```bash
# 1. Setup DNS
sudo ./hack/setup-dnsmasq.sh

# 2. Deploy VyOS router (manual config required)
ACTION=create ./hack/vyos-router.sh
# Follow prompts for manual VyOS configuration

# 3. Generate ISO
./hack/create-iso.sh sno-bond0-signal-vlan

# 4. Deploy to KVM
./hack/deploy-on-kvm.sh examples/sno-bond0-signal-vlan/nodes.yml --redfish

# 5. Monitor installation
./bin/openshift-install agent wait-for install-complete --dir ~/generated_assets/sno1/
```

### Version-Specific Manifest Testing

```bash
# Generate manifests for all supported versions
for v in 4.19 4.20 4.21; do
  ./hack/generate-version-manifests.sh sno-4.20-standard $v
done

# Validate each version
for v in 4.19 4.20 4.21; do
  ./hack/validate-deployment-standards.sh ~/generated_assets/sno-4-20-$v $v
done

# Compare versions
./hack/compare-version-manifests.sh sno-4-20 4.20 4.21
```

### Multi-Cluster Management

```bash
# Deploy multiple clusters
for cluster in sno1 sno2 sno3; do
  CLUSTER_NAME=$cluster ./hack/create-iso.sh sno-bond0-signal-vlan
  CLUSTER_NAME=$cluster ./hack/deploy-on-kvm.sh examples/sno-bond0-signal-vlan/nodes.yml --redfish
done

# Cleanup all clusters
for cluster in sno1 sno2 sno3; do
  ./hack/destroy-on-kvm.sh examples/sno-bond0-signal-vlan/nodes.yml
done
```

---

## Environment Variables Reference

| Variable | Default | Used By | Purpose |
|----------|---------|---------|---------|
| `SITE_CONFIG_DIR` | `examples` | create-iso.sh, deploy scripts | Location of cluster configs |
| `GENERATED_ASSET_PATH` | `~/generated_assets` | create-iso.sh, deploy-on-kvm.sh | Output directory for ISOs/manifests |
| `CLUSTER_NAME` | auto-detected | deploy-on-kvm.sh, destroy-on-kvm.sh | Override cluster name |
| `LIBVIRT_NETWORK` | `network=1924,model=e1000e` | deploy-on-kvm.sh | Primary VM network |
| `LIBVIRT_NETWORK_TWO` | Same as primary | deploy-on-kvm.sh | Secondary VM network |
| `EXTERNAL_IP` | (required) | configure-external-access.sh | Public IP for external access |
| `AWS_ACCESS_KEY_ID` | (required) | configure-route53-dns.sh | AWS credentials |
| `AWS_SECRET_ACCESS_KEY` | (required) | configure-route53-dns.sh | AWS secret |
| `EMAIL` | (required) | configure-letsencrypt-certs.sh | Let's Encrypt email |
| `KUBECONFIG` | (required) | configure-letsencrypt-certs.sh | Path to cluster kubeconfig |
| `ACTION` | (required) | vyos-router.sh | `create` or `destroy` |

---

## Troubleshooting Guide

### Common Issues

**ISO generation fails with version mismatch**:
```bash
# Remove binaries and regenerate
rm -rf ./bin
./hack/create-iso.sh <cluster-config>
```

**DNS not resolving**:
```bash
# Verify DNS configuration
sudo ./hack/verify-dns-resolution.sh examples/<cluster>/cluster.yml
dig @192.168.122.1 api.<cluster>.<domain>

# Reconfigure DNS
sudo ./hack/setup-dnsmasq.sh
sudo ./hack/configure-dnsmasq-entries.sh add examples/<cluster>/cluster.yml
```

**VyOS router not accessible**:
```bash
# Check VM status
sudo virsh list | grep vyos

# Access via Cockpit console
# https://<hypervisor-ip>:9090 → Virtual Machines → vyos-router
```

**Deployment fails - VMs not booting**:
```bash
# Check ISO exists
ls -lh ~/generated_assets/<cluster>/agent.x86_64.iso

# Check VM console
sudo virsh console <vm-name>

# Verify Redfish registration
curl http://localhost:8000/redfish/v1/Systems/
```

---

## Additional Resources

- **Configuration Guide**: [/docs/configuration-guide.md](/docs/configuration-guide.md)
- **Deployment Patterns**: [/docs/deployment-patterns.md](/docs/deployment-patterns.md)
- **Developer Guide**: [/docs/developer-guide.md](/docs/developer-guide.md)
- **Troubleshooting**: [/docs/troubleshooting.md](/docs/troubleshooting.md)
- **ADRs**: [/docs/adr/](/docs/adr/)
- **llm.txt**: Comprehensive AI-friendly reference (3,481 lines)

---

**Last Updated**: 2026-05-29  
**Maintained By**: OpenShift Agent-Install Contributors
