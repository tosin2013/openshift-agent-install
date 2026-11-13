---
name: Destroy Cluster
description: Tear down a KVM cluster — removes VMs, disk images, DNS entries, and generated assets to free resources or prepare for redeployment
triggers:
  - destroy cluster
  - tear down cluster
  - delete cluster
  - remove cluster
  - clean up cluster
  - destroy on KVM
  - delete VMs
  - cluster cleanup
  - start over
  - redeploy cluster
---

# Destroy Cluster

## When to Use This Skill

Activate when a user wants to:
- Clean up after a failed or completed installation
- Free up disk space and KVM resources
- Redeploy a cluster with a modified configuration
- Remove DNS entries and generated assets for a cluster
- Run `hack/destroy-on-kvm.sh` or `e2e-tests/delete_e2e.sh`

## Prerequisites

- KVM host with libvirt access and sudo capability
- `yq` installed (used by destroy-on-kvm.sh to parse YAML)
- The cluster's `nodes.yml` file available (for VM and disk name lookup)
- Cluster name known (or derivable from cluster.yml)

## Procedure

### Option A: Destroy KVM Cluster (Recommended)

```bash
./hack/destroy-on-kvm.sh examples/<cluster>/nodes.yml
# Example:
./hack/destroy-on-kvm.sh examples/sno-4.20-standard/nodes.yml
```

This single command:
1. Reads the sibling `cluster.yml` to get cluster name, base domain, API VIP, App VIP
2. Removes DNS entries from libvirt network (api, api-int, and common app routes)
3. Destroys each VM listed in nodes.yml (`virsh destroy` + `virsh undefine`)
4. Deletes qcow2 disk images: `<cluster-name>-<hostname>.qcow2` and `<cluster-name>-<hostname>-odf.qcow2`
5. Removes the agent ISO from `/var/lib/libvirt/images/agent.x86_64.iso`

**For site-config deployments:**
```bash
SITE_CONFIG_DIR=site-config ./hack/destroy-on-kvm.sh site-config/<cluster>/nodes.yml
```

### Option B: E2E Test Environment Cleanup

```bash
./e2e-tests/delete_e2e.sh <example-name>
# Example:
./e2e-tests/delete_e2e.sh sno-4.20-standard
```

Calls the cleanup function from `run_e2e.sh`, then also removes the entire generated
assets directory at `~/generated_assets/<cluster-name>/`.

### Option C: Manual Cleanup (When Scripts Cannot Find Config)

If the nodes.yml or cluster.yml is missing:

```bash
# Step 1: Destroy VMs manually
for vm in master-0 master-1 master-2 worker-0 worker-1; do
    sudo virsh destroy $vm 2>/dev/null || true
    sudo virsh undefine $vm 2>/dev/null || true
done

# Step 2: Remove disk images (adjust CLUSTER_NAME)
export CLUSTER_NAME="my-cluster"
sudo rm -f /var/lib/libvirt/images/${CLUSTER_NAME}-*.qcow2

# Step 3: Remove DNS entries
sudo ./hack/configure-dnsmasq-entries.sh remove <cluster-name> <base-domain>
# Example:
sudo ./hack/configure-dnsmasq-entries.sh remove sno-4-20 example.com

# Step 4: Remove generated assets
rm -rf ~/generated_assets/${CLUSTER_NAME}/

# Step 5: Verify DNS removed
dig @localhost api.sno-4-20.example.com
# Should return NXDOMAIN
```

### Step: Remove dnsmasq Entries Specifically

If DNS entries remain after destroy:

```bash
# List current dnsmasq entries
sudo ./hack/configure-dnsmasq-entries.sh list

# Remove specific cluster
sudo ./hack/configure-dnsmasq-entries.sh remove <cluster-name> <base-domain>

# Restart dnsmasq to apply
sudo systemctl restart dnsmasq
```

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `SITE_CONFIG_DIR` | `examples` | Config directory (set to `site-config` for production) |
| `GENERATED_ASSET_PATH` | `~/generated_assets` | Where to remove generated assets |
| `LIBVIRT_VM_PATH` | `/var/lib/libvirt/images` | Where disk images are stored |
| `CLUSTER_NAME` | From cluster.yml | Used as prefix for disk image filenames |

## Validation Criteria

The cluster is fully destroyed when:
1. `virsh list --all` shows none of the cluster's node hostnames
2. `ls /var/lib/libvirt/images/` shows no `<cluster-name>-*.qcow2` files
3. `dig @localhost api.<cluster>.<domain>` returns NXDOMAIN
4. `ls ~/generated_assets/<cluster-name>/` returns "No such file or directory"
5. `sudo ./hack/configure-dnsmasq-entries.sh list` does not show the cluster

## Related Skills

- **Before this skill**: This is typically run after `deploy-cluster-kvm` or `deploy-cluster-baremetal` to tear down
- **After cleanup to redeploy**: Return to `create-cluster-config` to modify config, or straight to `deploy-cluster-kvm`/`deploy-cluster-baremetal` to redeploy unchanged
- **DNS-only removal**: If you only need to remove DNS entries (keeping VMs), use `troubleshoot-dns` for the `configure-dnsmasq-entries.sh remove` command

## Common Failure Modes

| Phase | Symptom | Cause | Fix |
|-------|---------|-------|-----|
| VMs | "Domain not found" | VM names differ from nodes.yml hostnames | `virsh list --all` to find actual names; destroy manually |
| DNS | Entries remain after destroy | destroy-on-kvm.sh couldn't parse cluster.yml | Manually run `configure-dnsmasq-entries.sh remove` |
| Disks | qcow2 files not removed | CLUSTER_NAME doesn't match disk filename prefix | `ls /var/lib/libvirt/images/` to find actual names; rm manually |
| Generated assets | Assets directory remains | delete_e2e.sh ran but CLUSTER_NAME not set | `export CLUSTER_NAME=<name>; rm -rf ~/generated_assets/$CLUSTER_NAME/` |
| ISO | "Device or resource busy" | VM still mounted the ISO | `sudo virsh destroy <vm>` first, then retry |
| Partial destroy | Some VMs destroyed, some not | Script exited mid-run | Re-run script; it uses `|| true` so safe to repeat |

## Key Files

- `hack/destroy-on-kvm.sh` - Main KVM teardown script (VMs + disks + DNS)
- `e2e-tests/delete_e2e.sh` - E2E environment cleanup (wraps destroy + asset removal)
- `e2e-tests/run_e2e.sh` - Contains the `cleanup_test_env` function called by delete_e2e.sh
- `hack/configure-dnsmasq-entries.sh` - DNS entry management (add/remove/list)
