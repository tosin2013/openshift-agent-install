---
name: bootstrap-environment
description: Install packages, configure libvirt/KVM, set up dnsmasq, and validate a fresh RHEL host is ready for OpenShift ABI deployments
compatibility: "RHEL 9.x or 10.x host. OpenShift 4.15-4.22 and 5.x. Requires: libvirt, ansible-core, yq, openshift-install CLI."
triggers:
  - bootstrap environment
  - set up host
  - fresh install setup
  - install prerequisites
  - prepare KVM host
  - environment setup
  - first time setup
  - bootstrap_env
  - validate_env fails
  - setup new machine
---

# Bootstrap Environment

## When to Use This Skill

Activate when a user wants to:
- Set up a fresh RHEL 9.x host for the first time
- Install all required packages and configure KVM/libvirt
- Recover from a failed or partial environment setup
- Validate that a machine meets all prerequisites before attempting any cluster deployment
- Run `e2e-tests/bootstrap_env.sh` or troubleshoot `validate_env.sh` failures

## Prerequisites

- RHEL 9.x (or compatible) as the host operating system
- sudo or root access
- Internet access, or a configured package mirror/subscription
- Minimum resources: 32 GB RAM (SNO), 96 GB RAM (HA), 150 GB free disk
- Cockpit accessible at `https://<host-ip>:9090` (for VyOS router steps, later)

## Procedure

### Quick Diagnostics (run first)

Run these before proceeding to understand the current state:

```bash
# OS and resources
cat /etc/redhat-release
free -h
df -h / /var/lib/libvirt 2>/dev/null || df -h /

# Block devices — identify unallocated disks for libvirt VM storage
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE

# What's already configured?
./e2e-tests/validate_env.sh 2>&1 | head -60

# libvirt state
systemctl is-active libvirtd 2>/dev/null || systemctl is-active virtqemud 2>/dev/null || echo "libvirt: not running"
virsh --version 2>/dev/null && echo "virsh: OK" || echo "virsh: not installed"

# OCP CLI tools
ls -la ./bin/oc ./bin/openshift-install 2>/dev/null || echo "OCP CLI: not downloaded yet"

# Cockpit credentials (required before VyOS configuration)
cat ~/cockpit-credentials.txt 2>/dev/null || echo "Cockpit credentials: not yet generated (run bootstrap first, or create cockpit-admin user manually)"

# Detect cloud environment (affects HAProxy binding and DNS)
PRIVATE_IP=$(ip -4 addr show | grep "inet " | grep -v "127.0.0" | awk '{print $2}' | cut -d/ -f1 | head -1)
echo "Host private IP: ${PRIVATE_IP}"
echo "If IBM Cloud: floating public IP differs — note it for HAProxy and Route53 config"
echo "IBM Cloud guide: https://tosin2013.github.io/openshift-agent-install/ibm-cloud-deployment.html"
```

Interpret the output: skip steps that already pass and proceed directly to the first failing check.

> **Cloud instances (IBM Cloud, AWS):** The host's `/etc/resolv.conf` defaults to the cloud provider's DNS (e.g., `161.26.0.10`). The `openshift-install` process uses this DNS to reach the cluster API during install monitoring — if the cluster DNS is only in local dnsmasq, `wait-for bootstrap-complete` will fail with "no such host". Fix before starting install monitoring:
> ```bash
> PRIMARY_CONN=$(nmcli -t -f NAME conn show --active | head -1)
> sudo nmcli conn mod "$PRIMARY_CONN" ipv4.dns "127.0.0.1 161.26.0.10"
> sudo nmcli conn up "$PRIMARY_CONN"
> # Verify cluster DNS now resolves
> dig api.<cluster-name>.<base-domain> +short
> ```

### Step 1: Pre-flight — install wget (RHEL 10 only)

On RHEL 10, `wget` is not installed by default and the bootstrap script requires it:

```bash
# Check first — skip if already installed
rpm -q wget || sudo dnf install -y wget
```

### Step 2: Run the Bootstrap Script

```bash
sudo ./e2e-tests/bootstrap_env.sh
```

This script installs and configures everything in the correct order:
1. **System packages**: nmstate, ansible-core, bind-utils, libguestfs, cloud-init,
   virt-install, qemu-img, selinux-policy-targeted, python3-pip
2. **OpenShift CLI tools**: oc, kubectl, openshift-install
3. **libvirtd / KVM**: enables and starts virtualization
4. **Cockpit credentials**: generates `~/cockpit-credentials.txt` BEFORE VyOS
5. **LVM storage**: formats the largest unformatted disk as `/var/lib/libvirt/images`
6. **dnsmasq**: installs DNS server
7. **VyOS router**: deploys VM (requires manual Cockpit console steps — see below)

> **Note**: virt-manager is not available on RHEL 10 — Cockpit handles VM console access instead.

The script detects the real user even when run with sudo (`$SUDO_USER`) and sets
ownership accordingly.

### Step 2: Set Up DNS Infrastructure

```bash
sudo ./hack/setup-dnsmasq.sh
```

Installs and configures dnsmasq for cluster DNS resolution. Required before
any cluster deployment on KVM. For bare metal, corporate DNS handles this instead.

### Step 3: Validate the Environment

```bash
./e2e-tests/validate_env.sh
```

Checks all categories:
1. System packages installed (nmstate, ansible-core, bind-utils, etc.)
2. Ansible collections installed (from requirements.yml)
3. yq available in PATH
4. libvirtd running
5. KVM networks active
6. VyOS router reachable (optional — only if VyOS was deployed)

**All checks must pass before proceeding to cluster deployment.**

### Step 4: Download OpenShift CLI Tools

```bash
# Download for a specific OCP version (recommended)
./download-openshift-cli.sh 4.21

# Then make tools globally available
sudo cp ./bin/oc ./bin/kubectl ./bin/openshift-install /usr/local/bin/
```

Caches the downloaded CLI in `~/.cache/ocp-cli/<version>/` for reuse.

### Step 5: Verify Everything Is Ready

```bash
# Check libvirt
sudo systemctl status libvirtd
virsh --version

# Check CLI tools
./bin/openshift-install version
oc version --client

# Check DNS
sudo systemctl status dnsmasq
dig @localhost google.com
```

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `ACTUAL_USER` | `$SUDO_USER` or `$USER` | Real user (auto-detected when run with sudo) |
| `ACTUAL_USER_HOME` | Home of real user | Home directory for file ownership |
| `SITE_CONFIG_DIR` | `examples` | Where cluster configs live |
| `GENERATED_ASSET_PATH` | `~/generated_assets` | Where ISOs and manifests are written |

## Validation Criteria

The environment is ready when:
1. `./e2e-tests/validate_env.sh` exits 0 with all checks green
2. `virsh list --all` runs without error
3. `sudo systemctl status libvirtd` shows active/running
4. `yq --version` and `ansible --version` succeed
5. `./bin/openshift-install version` matches your target OCP version
6. `sudo systemctl status dnsmasq` shows active (if setup-dnsmasq.sh was run)

## Related Skills

- **Next steps (choose one)**:
  - `deploy-vyos-router` — if you need VLAN networking for lab deployments
  - `create-cluster-config` — to author your first cluster configuration
- **Validation output is a hard prerequisite** for `deploy-cluster-kvm` and `deploy-cluster-baremetal`

## Common Failure Modes

| Phase | Symptom | Cause | Fix |
|-------|---------|-------|-----|
| Packages | DNF install fails | No subscription or internet | Configure RHEL subscription: `subscription-manager register` |
| Packages | "Package not found" for specific pkg | EPEL or optional repos not enabled | `subscription-manager repos --enable codeready-builder-for-rhel-9-x86_64-rpms` |
| Ansible collections | "No collection found" | galaxy.ansible.com unreachable | Pre-stage collection tarballs and install offline |
| libvirtd | "Failed to start libvirtd" | Nested virtualization off | Check `cat /proc/cpuinfo | grep vmx`; enable VT-x in BIOS |
| libvirtd | "Permission denied" to virsh | User not in libvirt group | `sudo usermod -aG libvirt $USER` then log out/in |
| validate_env | "yq not found" | yq not installed or not in PATH | `sudo wget -O /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && sudo chmod +x /usr/local/bin/yq` |
| validate_env | VyOS check fails | VyOS not deployed | Either deploy VyOS (see skill) or only use non-VLAN examples |
| CLI download | "Permission denied" writing to bin/ | bin/ directory not writable | `mkdir -p bin && chmod u+w bin` |
| dnsmasq | Port 53 conflict | systemd-resolved running | `sudo systemctl stop systemd-resolved && sudo systemctl disable systemd-resolved` |

## Key Files

- `e2e-tests/bootstrap_env.sh` - Main bootstrap script (installs all prerequisites)
- `e2e-tests/validate_env.sh` - Environment validation (run after bootstrap)
- `playbooks/collections/requirements.yml` - Ansible Galaxy collection list
- `download-openshift-cli.sh` - Downloads oc, kubectl, openshift-install
- `hack/setup-dnsmasq.sh` - Installs and configures dnsmasq
