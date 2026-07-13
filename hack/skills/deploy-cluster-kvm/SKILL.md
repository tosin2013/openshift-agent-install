---
name: Deploy Cluster on KVM
description: Full lifecycle KVM deployment from DNS setup through VM creation to installation monitoring (7 phases)
triggers:
  - deploy cluster
  - deploy on KVM
  - create VMs
  - run deployment
  - deploy OpenShift
  - install cluster
  - deploy SNO
  - deploy HA cluster
---

# Deploy Cluster on KVM

## When to Use This Skill

Activate when a user wants to:
- Deploy an OpenShift cluster on a local KVM/libvirt host
- Run the full deployment pipeline (DNS, ISO, VMs, monitoring)
- Use `deploy-connected-full.sh` or `deploy-ha-full.sh`
- Deploy VMs and monitor the installation

## Prerequisites

- Environment bootstrapped: `./e2e-tests/validate_env.sh` passes
- Cluster configuration ready: `cluster.yml` + `nodes.yml` in examples/ or site-config/
- Pull secret at `~/pull-secret.json`
- Sufficient resources: SNO=8 vCPU/32GB RAM/130GB disk; HA=40 vCPU/96GB RAM/600GB disk
- DNS infrastructure: dnsmasq running (`sudo ./hack/setup-dnsmasq.sh`)
- VyOS router active if using VLAN networking (`virsh net-list` shows 1924-1928)
- sudo access for libvirt/DNS operations

## Procedure

### Option A: One-Shot Deployment (Recommended)

For connected clusters with full automation:

```bash
# SNO or simple connected deployment
./hack/deploy-connected-full.sh examples/sno-4.20-standard

# HA deployment with HAProxy external access
export EXTERNAL_IP="<your-host-public-ip>"
./hack/deploy-ha-full.sh examples/ha-4.22-standard

# Connected deployment with VyOS router
./hack/deploy-connected-full.sh examples/cnv-bond0-tagged --with-router
```

Options:
- `--with-haproxy` - Include HAProxy forwarder
- `--with-router` - Use VyOS router instead of dnsmasq only
- `--skip-dns` - Use existing DNS (don't reconfigure)
- `--skip-monitor` - Deploy VMs only, don't wait for install

### Option B: Step-by-Step Deployment

#### Phase 1: DNS Infrastructure

```bash
# Install dnsmasq (one-time)
sudo ./hack/setup-dnsmasq.sh

# Add DNS entries for this cluster
sudo ./hack/configure-dnsmasq-entries.sh add examples/<cluster>/cluster.yml

# Verify DNS resolves
./hack/verify-dns-resolution.sh examples/<cluster>/cluster.yml
```

DNS verification is a HARD REQUIREMENT. Do not proceed if it fails.

#### Phase 2: Generate ISO

```bash
./hack/create-iso.sh <cluster-config-name>
# Example: ./hack/create-iso.sh sno-4.20-standard
```

Verify the ISO was created:
```bash
ls -la ~/generated_assets/<cluster-name>/agent.x86_64.iso
```

#### Phase 3: Deploy VMs

```bash
./hack/deploy-on-kvm.sh examples/<cluster>/nodes.yml --redfish
```

#### Phase 4: Start VM Reboot Watcher (CRITICAL)

Agent-Based Installer VMs shut down after writing the image to disk. They MUST be restarted automatically:

```bash
./hack/watch-and-reboot-kvm-vms.sh examples/<cluster>/nodes.yml &
```

This runs in the background and auto-restarts any cluster VM that shuts off.

#### Phase 5: Monitor Installation

```bash
# Wait for bootstrap (5-15 min)
./bin/openshift-install agent wait-for bootstrap-complete \
  --dir ~/generated_assets/<cluster-name>/

# Wait for full install (20-45 min)
./bin/openshift-install agent wait-for install-complete \
  --dir ~/generated_assets/<cluster-name>/
```

#### Phase 6: Validate

```bash
export KUBECONFIG=~/generated_assets/<cluster-name>/auth/kubeconfig
oc get nodes       # All should be Ready
oc get co          # All operators Available=True
```

#### Phase 7: Access

```bash
# Console URL
echo "https://console-openshift-console.apps.<cluster-name>.<base-domain>/"

# Admin password
cat ~/generated_assets/<cluster-name>/auth/kubeadmin-password
```

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `SITE_CONFIG_DIR` | `examples` | Where cluster configs live |
| `GENERATED_ASSET_PATH` | `~/generated_assets` | Where ISOs/manifests are written |
| `CLUSTER_NAME` | From cluster.yml | Override cluster name |
| `EXTERNAL_IP` | None | Host's public IP (for HAProxy) |
| `DEPLOY_DNS` | `true` | Whether to set up DNS infra |
| `DEPLOY_HAPROXY` | `false` (connected) / `true` (HA) | Deploy HAProxy |
| `MONITOR_INSTALL` | `true` | Wait for install completion |
| `VALIDATION_TIMEOUT` | `3600` | Install timeout in seconds |

## Validation Criteria

Deployment is successful when:
1. `./hack/verify-dns-resolution.sh` passes before VM deployment
2. All VMs are created and booting (`virsh list --all`)
3. `wait-for bootstrap-complete` exits 0
4. `wait-for install-complete` exits 0
5. `oc get nodes` shows all nodes Ready
6. `oc get co` shows all operators Available=True, none Degraded

## Common Failure Modes

| Phase | Symptom | Cause | Fix |
|-------|---------|-------|-----|
| DNS | `verify-dns-resolution.sh` fails | dnsmasq entries missing | `sudo ./hack/configure-dnsmasq-entries.sh add <cluster.yml>` |
| DNS | Host can't resolve cluster names | NetworkManager not using libvirt DNS | `nmcli conn mod <conn> ipv4.dns 192.168.122.1` |
| ISO | "Failed to template manifests" | Ansible error in create-manifests.yml | Check cluster.yml syntax; verify pull secret path |
| ISO | Version mismatch warning | openshift-install version != ocp_version | `rm -rf ./bin && ./download-openshift-cli.sh <version>` |
| VMs | "Please generate the agent.iso first" | ISO not at expected path | Set `CLUSTER_NAME` env var to match cluster.yml |
| VMs | Permission denied creating VM | User not in libvirt group | `sudo usermod -aG libvirt $USER` then re-login |
| Install | Stuck at "Waiting for bootstrap" | VMs didn't reboot after disk write | Ensure `watch-and-reboot-kvm-vms.sh` is running |
| Install | Bootstrap hangs >45 min | DNS from node can't resolve | Check node's dns-resolver in networkConfig points to 192.168.122.1 |
| Install | Insufficient resources | Not enough RAM/CPU for nodes | Reduce node count or increase host resources |
| Post | `oc get nodes` - connection refused | KUBECONFIG not set or API VIP unreachable | `export KUBECONFIG=...`; check DNS resolves api.<cluster> |

## Cleanup

To destroy a deployed cluster and start over:

```bash
./hack/destroy-on-kvm.sh examples/<cluster>/nodes.yml
```

This removes VMs, disks, and DNS entries.

## Key Files

- `hack/deploy-connected-full.sh` - One-shot connected deployment orchestrator
- `hack/deploy-ha-full.sh` - One-shot HA deployment with HAProxy
- `hack/deploy-on-kvm.sh` - VM creation script
- `hack/create-iso.sh` - ISO generation
- `hack/watch-and-reboot-kvm-vms.sh` - VM auto-restart (REQUIRED)
- `hack/destroy-on-kvm.sh` - Cluster teardown
- `hack/configure-dnsmasq-entries.sh` - DNS entry management
- `hack/verify-dns-resolution.sh` - DNS verification
- `e2e-tests/validate_env.sh` - Environment validation
