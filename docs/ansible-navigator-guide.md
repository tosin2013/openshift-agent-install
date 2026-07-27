# Ansible Navigator Guide

This guide explains how to use `ansible-navigator` with the pre-built Execution Environment (EE) image to run OpenShift Agent-Based Installer playbooks without installing dependencies on your host.

## When to Use This Approach

| Scenario | Recommended Approach |
|----------|---------------------|
| Quick dev/test on a fully bootstrapped host | Direct `ansible-playbook` via `create-iso.sh` |
| Airgapped / disconnected environments | EE image (pre-load container with all deps) |
| CI/CD pipelines (AAP, AWX, Jenkins) | EE image as standard runtime |
| Multiple team members need consistent results | EE image (eliminates host variations) |
| Running from a laptop without installing deps | `ansible-navigator` + EE image |
| Ansible Automation Platform (AAP) integration | EE image (native AAP format) |

## Prerequisites

- `podman` or `docker` installed on your host
- Network access to `quay.io` (or pre-pulled image for airgapped use)

## Installation

```bash
# Install ansible-navigator
pip3 install ansible-navigator

# Verify installation
ansible-navigator --version
```

## Pull the Execution Environment Image

```bash
# Latest build (updated weekly and on every push to main)
podman pull quay.io/takinosh/openshift-agent-install-ee:latest

# Or a pinned release version
podman pull quay.io/takinosh/openshift-agent-install-ee:v4.22.0
```

**What's included in the image**:
- Python 3.11
- ansible-core 2.19.x
- community.general and community.crypto collections
- `oc`, `kubectl`, and `helm` CLI tools
- `nmstate` (CLI for network config validation)
- `jmespath` (for Ansible json_query filter)

## Running Playbooks

### Generate Cluster Manifests

```bash
ansible-navigator run playbooks/create-manifests.yml \
  --eei quay.io/takinosh/openshift-agent-install-ee:latest \
  --mode stdout \
  -e @examples/sno-4.20-standard/cluster.yml \
  -e @examples/sno-4.20-standard/nodes.yml
```

### With Pull Secret Mounted

```bash
ansible-navigator run playbooks/create-manifests.yml \
  --eei quay.io/takinosh/openshift-agent-install-ee:latest \
  --mode stdout \
  --eev ~/pull-secret.json:/tmp/pull-secret.json:z \
  -e @site-config/my-cluster/cluster.yml \
  -e @site-config/my-cluster/nodes.yml
```

### Interactive TUI Mode

Drop the `--mode stdout` flag to use the interactive text UI:

```bash
ansible-navigator run playbooks/create-manifests.yml \
  --eei quay.io/takinosh/openshift-agent-install-ee:latest \
  -e @examples/sno-4.20-standard/cluster.yml \
  -e @examples/sno-4.20-standard/nodes.yml
```

## Project Configuration File

Create `ansible-navigator.yml` in the repository root to avoid passing flags every time:

```yaml
ansible-navigator:
  execution-environment:
    image: quay.io/takinosh/openshift-agent-install-ee:latest
    pull:
      policy: missing
    volume-mounts:
      - src: ~/pull-secret.json
        dest: /tmp/pull-secret.json
        options: z

  mode: stdout

  playbook-artifact:
    enable: true
    save-as: ~/generated_assets/navigator-artifacts/{playbook_name}-{ts_utc}.json
```

With this file in place, commands simplify to:

```bash
ansible-navigator run playbooks/create-manifests.yml \
  -e @examples/sno-4.20-standard/cluster.yml \
  -e @examples/sno-4.20-standard/nodes.yml
```

## Airgapped / Disconnected Usage

For environments without internet access, pre-load the EE image:

```bash
# On a connected machine: save image to tarball
podman save quay.io/takinosh/openshift-agent-install-ee:latest \
  -o openshift-agent-install-ee-latest.tar

# Transfer the tarball to the airgapped host (USB, SCP, etc.)

# On the airgapped host: load image
podman load -i openshift-agent-install-ee-latest.tar

# Run as normal
ansible-navigator run playbooks/create-manifests.yml \
  --eei quay.io/takinosh/openshift-agent-install-ee:latest \
  --mode stdout \
  -e @site-config/my-cluster/cluster.yml \
  -e @site-config/my-cluster/nodes.yml
```

## Building the EE Locally

If you need to customize the EE (add collections, Python packages, or tools):

```bash
# Install ansible-builder 3.1.1
pip3 install ansible-builder==3.1.1

# Build from the definition
cd execution-environment/
ansible-builder build --tag openshift-agent-install-ee:custom -v3

# Use your custom image
ansible-navigator run playbooks/create-manifests.yml \
  --eei openshift-agent-install-ee:custom \
  --mode stdout \
  -e @examples/sno-4.20-standard/cluster.yml \
  -e @examples/sno-4.20-standard/nodes.yml
```

## Comparison: Direct vs Navigator

| Feature | Direct (`ansible-playbook`) | Navigator + EE |
|---------|----------------------------|----------------|
| Host dependencies | Must install ansible-core, collections, nmstate, etc. | Only needs `podman` + `ansible-navigator` |
| Python version | Host Python (may conflict) | Isolated Python 3.11 in container |
| Reproducibility | Depends on host state | Identical environment every run |
| Offline support | Must pre-install all deps | Single container image |
| AAP/AWX compatible | No | Yes (EE is the native format) |
| Startup time | Immediate | ~1-2s container startup |
| Host access | Full (libvirt, /dev, etc.) | Limited to mounted volumes |

**Note**: The `hack/` scripts (e.g., `create-iso.sh`, `deploy-on-kvm.sh`) call `ansible-playbook` directly and require host-level access to libvirt, file system, and network. Use the navigator approach for the manifest generation playbook (`create-manifests.yml`), not for scripts that manage VMs or network infrastructure.
