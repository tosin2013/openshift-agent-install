# OpenShift Agent Based Installer Helper

Automated deployment tooling for OpenShift clusters using the Agent-Based Installer.
Supports **bare metal, vSphere, Nutanix AHV, and platform=none** in SNO, 3-Node compact,
and HA configurations.

Primary workflow: **Development (KVM) → Fork & Adapt → Production (Bare Metal)**

📚 **Full documentation**: https://tosin2013.github.io/openshift-agent-install/

---

## Two Paths: KVM Development and Bare Metal Production

This repository supports two distinct deployment contexts. Choose based on your goal:

| | KVM Development | Bare Metal Production |
|---|---|---|
| **Purpose** | Learn, test, and validate configs safely | Deploy real production clusters |
| **Networking** | VyOS router + libvirt VLANs | Physical switch VLANs |
| **DNS** | dnsmasq (`192.168.122.1`) | Corporate DNS (BIND / Infoblox / AD) |
| **BMC** | sushy Redfish emulator (virtual) | Real iDRAC / iLO / IPMI |
| **ISO delivery** | `./hack/deploy-on-kvm.sh` | `./hack/deploy-iso-baremetal.sh` |
| **Environment check** | `./e2e-tests/validate_env.sh` | `./hack/validate-baremetal-env.sh` |
| **Config directory** | `examples/` | `site-config/` |
| **Start here** | [Developer Guide] | [Bare Metal Tutorial] |

**Choose your starting point:**

- 🖥️ **KVM development** (learn and test) → [Developer Guide](https://tosin2013.github.io/openshift-agent-install/developer-guide)
- 🔩 **Physical bare metal** (production) → [Bare Metal Tutorial](https://tosin2013.github.io/openshift-agent-install/bare-metal-tutorial)
- 🔄 **Migrating KVM → production** → [Fork & Adapt Checklist](https://tosin2013.github.io/openshift-agent-install/fork-and-adapt-checklist)

---

## Common Installation Flow

After environment setup, the ISO generation and monitoring steps are **identical for both KVM and bare metal**. Only ISO delivery differs.

```bash
# ── Step 1: Generate the agent ISO (same for both paths) ─────────────────────
./hack/create-iso.sh <cluster-name>
# ISO lands at: ~/generated_assets/<cluster-name>/agent.x86_64.iso

# ── Step 2: Deliver ISO to nodes ─────────────────────────────────────────────

# KVM path:
./hack/deploy-on-kvm.sh examples/<cluster-name>/nodes.yml

# Bare metal — Redfish virtual media (iDRAC 9+ / iLO 5+):
./hack/deploy-iso-baremetal.sh site-config/<cluster-name>/nodes.yml \
    --method redfish \
    --iso ~/generated_assets/<cluster-name>/agent.x86_64.iso

# Bare metal — IPMI chassis boot:
./hack/deploy-iso-baremetal.sh site-config/<cluster-name>/nodes.yml \
    --method ipmi \
    --iso ~/generated_assets/<cluster-name>/agent.x86_64.iso

# ── Step 3: Monitor installation (identical for both paths) ──────────────────
./bin/openshift-install agent wait-for bootstrap-complete \
    --dir ~/generated_assets/<cluster-name>/ --log-level=info

./bin/openshift-install agent wait-for install-complete \
    --dir ~/generated_assets/<cluster-name>/ --log-level=info

# ── Step 4: Access the cluster ───────────────────────────────────────────────
export KUBECONFIG=~/generated_assets/<cluster-name>/auth/kubeconfig
oc get nodes
oc get co
```

---

## Prerequisites

### Core Requirements (both paths)

- **RHEL 9.x** — deployment host for KVM development or bare metal control
- **OpenShift CLI tools** — `./download-openshift-cli.sh` then `sudo cp ./bin/* /usr/local/bin/`
- **NMState CLI** — `sudo dnf install -y nmstate`
- **Ansible Core** — `sudo dnf install -y ansible-core`
- **Ansible Collections** — `ansible-galaxy install -r execution-environment/collections/requirements.yml`
- **Red Hat Pull Secret** — download from [console.redhat.com](https://console.redhat.com/openshift/downloads#tool-pull-secret), save to `~/pull-secret.json`

---

## KVM Development Path

KVM development requires VyOS VLAN networking and dnsmasq DNS. Run environment validation first — if it fails, do not proceed.

```bash
# Validate KVM environment (VyOS, DNS, packages, libvirt)
./e2e-tests/validate_env.sh
```

### Setting up KVM prerequisites

**1. VyOS Router** ⚠️ MANUAL CONFIGURATION REQUIRED

VyOS deployment requires interactive console access via Cockpit. The script pauses and waits for you to complete manual configuration (up to 30 minutes).

```bash
ACTION=create ./hack/vyos-router.sh
```

After the script pauses:
1. Open Cockpit: `https://<your-host>:9090` (credentials: `cat ~/cockpit-credentials.txt`)
2. Navigate to Virtual Machines → vyos-router → Console
3. Follow the step-by-step guide: [VyOS Manual Configuration](https://tosin2013.github.io/openshift-agent-install/vyos-manual-configuration)

Verify networks after manual configuration:
```bash
sudo virsh net-list
```

**2. DNS (dnsmasq)**

```bash
sudo ./hack/setup-dnsmasq.sh
sudo ./hack/configure-dnsmasq-entries.sh add examples/<cluster-name>/cluster.yml
./hack/verify-dns-resolution.sh examples/<cluster-name>/cluster.yml
```

**3. Libvirt/KVM**

```bash
sudo dnf install -y qemu-kvm libvirt virt-install
sudo systemctl enable --now libvirtd
```

📘 **Full KVM setup guide**: [Developer Guide](https://tosin2013.github.io/openshift-agent-install/developer-guide)

---

## Bare Metal Production Path

For physical servers, validate your environment before generating the ISO.

```bash
# Validate bare metal prerequisites
export SITE_CONFIG_DIR=site-config
./hack/validate-baremetal-env.sh <cluster-name>
```

This validates: required tools, cluster config files, corporate DNS records, VIP routing, BMC reachability, NMState networkConfig syntax, SSH key, and pull secret.

### Corporate DNS

Register DNS records in your corporate DNS server (BIND, Infoblox, or Active Directory) before any node boots:

| Record | Value |
|--------|-------|
| `api.<cluster>.<domain>` | API VIP |
| `api-int.<cluster>.<domain>` | API VIP |
| `*.apps.<cluster>.<domain>` | App VIP |

📘 **Full bare metal guide**: [Bare Metal Tutorial](https://tosin2013.github.io/openshift-agent-install/bare-metal-tutorial)
📘 **DNS setup**: [Corporate DNS Integration](https://tosin2013.github.io/openshift-agent-install/corporate-dns-integration)
📘 **BMC configuration**: [BMC Management Guide](https://tosin2013.github.io/openshift-agent-install/bmc-management)

---

## Supported Platforms and Versions

### Platforms

| Platform | `platform_type` | Example configs |
|----------|----------------|-----------------|
| Bare metal | `baremetal` | `examples/baremetal-example/`, `examples/ha-4.21-disconnected/` |
| VMware vSphere | `vsphere` | `examples/vmware-example/`, `examples/vmware-disconnected-example/` |
| Nutanix AHV | `nutanix` | `examples/nutanix-sno/`, `examples/nutanix-ha/` |
| Platform None | `none` | `examples/sno-4.20-standard/`, `examples/sno-bond0-signal-vlan/` |

### OpenShift Versions

Supports OpenShift 4.15+. Tested and validated with:
- OpenShift 4.20.x
- OpenShift 4.21.x

### Critical version boundaries

**4.19 → 4.20**: Disconnected deployments must migrate from `imageDigestSources` in `install-config.yaml` to standalone `ImageDigestMirrorSet` manifests.

**4.20 → 4.21**: `networkType: OpenShiftSDN` removed — all deployments must use `OVNKubernetes`.

See the [Version Compatibility Matrix](https://tosin2013.github.io/openshift-agent-install/version-compatibility-matrix) for full API change history.

---

## Usage — Declarative (Recommended)

Place your `cluster.yml` and `nodes.yml` in a config directory, then generate the ISO in one command:

```bash
# Use examples/ for learning, site-config/ for production
export SITE_CONFIG_DIR=site-config        # or: export SITE_CONFIG_DIR=examples

# Generate ISO
./hack/create-iso.sh <cluster-name>
```

Example configs:
- `examples/sno-4.20-standard/` — SNO connected deployment
- `examples/ha-4.21-disconnected/` — HA air-gapped deployment
- `examples/nutanix-sno/` — SNO on Nutanix AHV
- `examples/baremetal-example/` — Bare metal HA with BMC blocks

For all configuration parameters, see the [Configuration Reference](https://tosin2013.github.io/openshift-agent-install/configuration-guide).

---

## Usage — Manual

For manual Ansible templating and full configuration YAML examples (SNO, HA, VLAN, Bond,
Bond+VLAN, Nutanix, vSphere), see the
[Configuration Reference](https://tosin2013.github.io/openshift-agent-install/configuration-guide)
and [Reference Configurations](https://tosin2013.github.io/openshift-agent-install/reference-configurations).

```bash
# Template manifests with Ansible
cd playbooks/
ansible-playbook -e "@your-cluster-vars.yml" create-manifests.yml

# Create ISO from generated manifests
openshift-install agent create image --dir ./generated_manifests/<cluster_name>

# Monitor
openshift-install agent wait-for bootstrap-complete --dir ./generated_manifests/<cluster_name>
openshift-install agent wait-for install-complete --dir ./generated_manifests/<cluster_name>
```

---

## Version Validation and Compatibility Testing

Automated tools to validate manifests across multiple OpenShift versions and detect version-specific API changes.

```bash
# Generate manifests for multiple versions
./hack/generate-version-manifests.sh sno-disconnected "4.19 4.20 4.21"

# Validate against deployment standards
./hack/validate-deployment-standards.sh \
  ~/generated_assets/version-compare/sno-disconnected-4.20 4.20

# Compare version boundaries
./hack/compare-version-manifests.sh 4.19 4.20 sno-disconnected
./hack/compare-version-manifests.sh 4.20 4.21 sno-disconnected
```

### LLM-Powered Validation

Version validation uses **Granite-3-2-8b-instruct** to analyze API compliance, deployment pattern standards, and platform-specific configuration:

```
[PASS] Image Registry Configuration
[FAIL] Network Configuration - networkType: OpenShiftSDN deprecated for 4.21
[PASS] Platform Configuration
```

### GitHub Actions Integration

```bash
gh workflow run version-validation.yml \
  -f create_issues=true \
  -f examples="sno-disconnected ha-4.21-disconnected sno-4.20-standard"
```

**Documentation:**
- [Version Compatibility Matrix](https://tosin2013.github.io/openshift-agent-install/version-compatibility-matrix)
- [Version Validation Feature](https://tosin2013.github.io/openshift-agent-install/version-validation-feature)
- [Quick Start Guide](https://tosin2013.github.io/openshift-agent-install/version-validation-quick-start)

---

## DNS Setup

Three DNS records are required per cluster:

| Record | Points to |
|--------|-----------|
| `api.<cluster>.<domain>` | API VIP |
| `api-int.<cluster>.<domain>` | API VIP |
| `*.apps.<cluster>.<domain>` | App VIP |

**KVM development** (dnsmasq):
```bash
sudo ./hack/setup-dnsmasq.sh
sudo ./hack/configure-dnsmasq-entries.sh add examples/sno-4.20-standard/cluster.yml
dig @localhost api.sno-4-20.example.com
```

**Bare metal production**: Register in your corporate DNS server. See [Corporate DNS Integration](https://tosin2013.github.io/openshift-agent-install/corporate-dns-integration).

---

## E2E Testing and Bootstrap

```bash
# Bootstrap complete KVM environment (packages, DNS, VyOS, etc.)
sudo ./e2e-tests/bootstrap_env.sh

# Run E2E tests
./e2e-tests/run_e2e.sh
```

---

## Execution Environment (Ansible)

For offline use or Ansible Automation Platform, use the pre-built containerized Execution Environment:

```bash
# Pull latest
podman pull quay.io/takinosh/openshift-agent-install-ee:latest

# Run playbook in container
podman run --rm -it \
  -v $(pwd):/runner \
  -v ~/pull-secret.json:/runner/pull-secret.json:ro \
  quay.io/takinosh/openshift-agent-install-ee:latest \
  ansible-playbook -e @examples/sno-4.20-standard/cluster.yml \
                   -e @examples/sno-4.20-standard/nodes.yml \
                   playbooks/create-manifests.yml
```

Image tags: `latest` (most recent), `vX.Y.Z` (pinned, e.g., `v4.21.0`).

---

## Documentation

| Section | URL |
|---------|-----|
| Full docs site | https://tosin2013.github.io/openshift-agent-install/ |
| Developer Guide (KVM) | [/developer-guide](https://tosin2013.github.io/openshift-agent-install/developer-guide) |
| Bare Metal Tutorial | [/bare-metal-tutorial](https://tosin2013.github.io/openshift-agent-install/bare-metal-tutorial) |
| Fork & Adapt Checklist | [/fork-and-adapt-checklist](https://tosin2013.github.io/openshift-agent-install/fork-and-adapt-checklist) |
| Configuration Reference | [/configuration-guide](https://tosin2013.github.io/openshift-agent-install/configuration-guide) |
| Platform Guides | [/platform-guides](https://tosin2013.github.io/openshift-agent-install/platform-guides) |
| BMC Management | [/bmc-management](https://tosin2013.github.io/openshift-agent-install/bmc-management) |
| Troubleshooting | [/troubleshooting](https://tosin2013.github.io/openshift-agent-install/troubleshooting) |
