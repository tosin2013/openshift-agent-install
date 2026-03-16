---
layout: default
title: "ADR-0014: Disconnected Deployment Methods"
description: "Architecture Decision Record for Disconnected Deployment Methods"
---

# ADR-014: Disconnected Deployment Methods

## Date
2025-11-29

## Status
Accepted

## Decision Makers
- OpenShift Platform Team
- Automation Team

## Context

Disconnected OpenShift deployments require all container images to be available without internet access. This repository now supports two methods for disconnected deployments:

1. **Appliance Method** - Self-contained disk image with embedded OCP payload
2. **Agent + Mirror Registry Method** - Agent-based installer pulling from local registry

Each method has different trade-offs and is suited for different environments.

## Considered Options

### 1. Appliance Method Only
- Pros:
  - Simplest for true air-gap
  - No registry infrastructure needed
- Cons:
  - Large disk images (100+ GB)
  - Upgrade requires new ISO

### 2. Agent + Mirror Registry Only
- Pros:
  - Standard OCP upgrade path
  - Shared registry for multiple clusters
- Cons:
  - Requires registry infrastructure
  - More complex setup

### 3. Both Methods (Selected)
- Pros:
  - Flexibility for different environments
  - Choose based on constraints
- Cons:
  - More documentation and maintenance

## Decision

Support both disconnected deployment methods with complete install and upgrade workflows.

### Method 1: Appliance (Self-Contained Air-Gap)

**Best for:** Edge sites, remote locations, true air-gap with no infrastructure

**Install Workflow:**
```bash
# Build appliance and config-image
ansible-playbook playbooks/build-appliance.yml \
  -e @examples/appliance-sno-4.19/cluster.yml \
  -e @examples/appliance-sno-4.19/nodes.yml \
  -e @examples/appliance-sno-4.19/appliance-vars.yml

# Deploy (production)
# 1. Boot from appliance.iso
# 2. Mount agentconfig.noarch.iso
# 3. Cluster installs automatically

# Deploy (lab testing)
./hack/deploy-on-kvm.sh examples/appliance-sno-4.19/nodes.yml
```

**Upgrade Workflow (4.19 → 4.20):**
```bash
# Build upgrade ISO
ansible-playbook playbooks/build-appliance.yml \
  -e build_type=upgrade-iso \
  -e ocp_version=4.20 \
  -e @examples/appliance-upgrade-4.20/appliance-vars.yml

# On each node: attach upgrade-4.20.iso
# Then apply MachineConfig
oc apply -f upgrade-machine-config-4.20.yaml
# Nodes reboot and upgrade
```

### Method 2: Agent + Mirror Registry

**Best for:** Data centers, multiple clusters, existing registry infrastructure

**Prerequisites:**
- Mirror registry deployed (Quay, Harbor, or JFrog)
- OCP images mirrored using oc-mirror or ocp4-disconnected-helper

**Install Workflow:**
```bash
# Create agent ISO with disconnected config
./hack/create-iso.sh sno-disconnected

# Deploy (production)
# 1. Boot from agent.x86_64.iso
# 2. Cluster pulls images from mirror registry

# Deploy (lab testing)
./hack/deploy-on-kvm.sh examples/sno-disconnected/nodes.yml
```

**Upgrade Workflow (4.19 → 4.20):**
```bash
# Mirror new version to registry (using ocp4-disconnected-helper)
# Then standard OCP upgrade
oc adm upgrade --to=4.20.x
```

## Implementation

### New Files

```
playbooks/
└── build-appliance.yml          # Appliance build playbook

examples/
├── appliance-sno-4.19/          # Appliance SNO install
│   ├── cluster.yml
│   ├── nodes.yml
│   └── appliance-vars.yml
├── appliance-3node-4.19/        # Appliance 3-node compact
│   ├── cluster.yml
│   ├── nodes.yml
│   └── appliance-vars.yml
├── appliance-upgrade-4.20/      # Upgrade example
│   └── appliance-vars.yml
└── sno-disconnected/            # Agent + registry
    ├── cluster.yml              # includes disconnected_registries
    └── nodes.yml
```

### Appliance Variables (appliance-vars.yml)

```yaml
# Build type: appliance, live-iso, upgrade-iso
build_type: "appliance"

# OCP version
ocp_version: "4.19"
ocp_channel: "stable"

# Disk size (minimum 150GB)
disk_size_gb: 200

# Target device for deployment ISO
target_device: "/dev/sda"

# Assets directory
assets_dir: "/opt/appliance-assets"

# Optional: include operators
include_operators: false
operators: []
```

### Disconnected Registry Configuration (cluster.yml)

```yaml
# For Agent + Mirror Registry method
disconnected_registries:
  - target: mirror-registry.example.com:8443/openshift-release-dev/ocp-release
    source: quay.io/openshift-release-dev/ocp-release
  - target: mirror-registry.example.com:8443/openshift-release-dev/ocp-v4.0-art-dev
    source: quay.io/openshift-release-dev/ocp-v4.0-art-dev

additional_trust_bundle: |
  -----BEGIN CERTIFICATE-----
  ... mirror registry CA certificate ...
  -----END CERTIFICATE-----
```

## Comparison

| Aspect | Appliance | Agent + Mirror Registry |
|--------|-----------|------------------------|
| Infrastructure | None | Registry server required |
| Image size | Large (100+ GB disk) | Small ISO (~1GB) |
| Build time | 30-60 minutes | Minutes |
| Upgrade method | Attach ISO + MachineConfig | `oc adm upgrade` |
| Multiple clusters | Build per cluster | Shared registry |
| Operators | Embedded in image | Pull from registry |
| Best for | Edge, remote, true air-gap | Data centers |

## Consequences

### Positive
1. Flexibility to choose deployment method
2. Complete install and upgrade workflows
3. Reuse of existing hack scripts for KVM testing
4. Integration with ocp4-disconnected-helper for registry method

### Negative
1. Two methods to document and maintain
2. Different upgrade procedures
3. Appliance method requires significant disk space

## Validation

### Appliance Method
1. Build appliance.iso successfully
2. Generate agentconfig.noarch.iso
3. Deploy on KVM and verify cluster health
4. Build upgrade ISO and verify upgrade

### Agent + Mirror Registry Method
1. Verify registry connectivity
2. Create agent ISO with disconnected config
3. Deploy on KVM and verify cluster health
4. Mirror new version and verify upgrade

## Related
- [ADR-004: Disconnected Installation Support](0004-disconnected-installation-support)
- [ADR-005: ISO Creation and Asset Management](0005-iso-creation-and-asset-management)
- [ocp4-disconnected-helper](https://github.com/tosin2013/ocp4-disconnected-helper)
- [OpenShift Appliance](https://github.com/openshift/appliance)

## Notes

Key considerations:
1. Appliance method requires OCP 4.14+ for upgrade ISO support
2. PinnedImageSets (OCP 4.19+) will improve appliance upgrades
3. Both methods support SNO, 3-node compact, and HA configurations
4. Lab testing uses existing deploy-on-kvm.sh script

