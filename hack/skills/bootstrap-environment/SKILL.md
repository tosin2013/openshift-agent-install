---
name: Bootstrap Environment
description: Install packages, configure libvirt/KVM, set up dnsmasq, and validate a fresh RHEL host is ready for OpenShift ABI deployments
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

### Step 1: Run the Bootstrap Script

```bash
sudo ./e2e-tests/bootstrap_env.sh
```

This script installs and configures everything needed:
- **System packages**: nmstate, ansible-core, bind-utils, libguestfs, cloud-init,
  virt-install, qemu-img, selinux-policy-targeted, python3-pip
- **Optional packages**: virt-manager (GUI, non-fatal if unavailable)
- **Ansible collections**: installs from `playbooks/collections/requirements.yml`
- **libvirtd**: enables and starts the service
- **yq**: validates it is installed (required for YAML parsing)

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
