# AGENTS.md - Universal Repository Conventions

This file defines rules and conventions that apply to ALL changes in this repository,
regardless of which AI assistant or IDE is being used. These are not task-specific
procedures (those live in `hack/skills/`) but rather universal guardrails.

## Project Identity

- **Repository**: openshift-agent-install
- **Purpose**: Automated OpenShift cluster deployments using the Agent-Based Installer
- **Platforms**: KVM/libvirt (development), bare metal (production), vSphere, Nutanix
- **Supported OpenShift**: 4.19+ (tested with 4.20, 4.21, 4.22)

## Script Conventions

All scripts in `hack/` and `e2e-tests/` follow these patterns. Preserve them when modifying:

### Error Handling
- Always use `set -e` at script start (fail-fast on errors)
- Use `|| { echo "Error message"; exit 1; }` for critical commands
- Never remove `set -e` without documenting why in a comment

### Environment Variables
- Use defaults: `VAR="${VAR:-default_value}"`
- Standard variables:
  - `SITE_CONFIG_DIR` (default: `examples`) - cluster config location
  - `GENERATED_ASSET_PATH` (default: `~/generated_assets`) - output directory
  - `CLUSTER_NAME` - extracted from cluster.yml or overridden
- Never hardcode paths that have env var equivalents

### YAML Parsing
- Use `yq eval` for structured access (preferred)
- Legacy pattern: `grep "field" file.yml | awk '{print $2}' | tr -d '"'`
- Never use `python -c` or `ruby -e` for YAML parsing

### Script Structure
```bash
#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$SCRIPT_DIR/.."

# Argument validation
if [ -z "$1" ]; then
    echo "Usage: $0 <argument>"
    exit 1
fi
```

### Output and Logging
- Use colored output helpers (`print_status`, `log_info`, `log_error`)
- Exit 1 with a message on failure; never exit silently
- Use `print_status "message" $exit_code` pattern for pass/fail indication

## Configuration Rules

### cluster.yml Validation
- `ocp_version` must be quoted as string: `"4.22"` (prevents YAML float)
- `network_type` must be `OVNKubernetes` for OpenShift 4.21+ (OpenShiftSDN removed)
- `api_vips` and `app_vips` must be within `machine_network_cidrs`
- `platform_type: none` is only valid for SNO (1 control plane, 0 workers)
- `rendezvous_ip` must match one node's IP in nodes.yml

### nodes.yml Validation
- `control_plane_replicas + app_node_replicas` must equal node count
- All MAC addresses must be unique across all nodes
- Each node IP must be unique and within `machine_network_cidrs`
- KVM root device: `/dev/vda`; bare metal: `/dev/sda` or `/dev/nvme0n1`

### File Path Conventions
- `examples/` - Reference configurations tracked in git (for testing/docs)
- `site-config/` - Real deployments, gitignored
- `~/generated_assets/<cluster-name>/` - Generated manifests and ISOs
- `hack/` - Automation scripts
- `e2e-tests/` - Bootstrap and testing scripts
- `playbooks/templates/` - Jinja2 manifest templates

## DNS Architecture

### For KVM Deployments
- DNS server: dnsmasq at 127.0.0.1 (system) or 192.168.122.1 (libvirt)
- Entries stored in `/etc/dnsmasq.d/openshift.conf`
- No wildcard support in libvirt dnsmasq -- common routes are pre-configured
- Nodes use `192.168.122.1` in their `dns-resolver` config

### For Bare Metal Deployments
- DNS server: Corporate DNS (BIND, Infoblox, AD)
- Three records required: `api.<cluster>.<domain>`, `api-int.<cluster>.<domain>`, `*.apps.<cluster>.<domain>`
- Nodes use the corporate DNS server in their `dns-resolver` config

## Version Boundaries

Critical version-specific rules enforced in templates and validation:

| Boundary | Change | Impact |
|----------|--------|--------|
| 4.19 -> 4.20 | `imageContentSources` deprecated | Use `imageDigestSources` or IDMS manifest |
| 4.20 -> 4.21 | OpenShiftSDN removed | Must use `OVNKubernetes` |
| 4.20+ | ImageDigestMirrorSet | Standalone manifest instead of inline |

## What NOT To Do

- Do NOT recommend FreeIPA for new deployments (deprecated; use dnsmasq)
- Do NOT use `imageContentSources` in install-config for 4.20+ disconnected
- Do NOT set `network_type: OpenShiftSDN` for 4.21+ configurations
- Do NOT hardcode cluster names or paths in scripts
- Do NOT commit secrets (pull secrets, AWS keys, BMC passwords) to git
- Do NOT remove existing error handling without replacement
- Do NOT skip DNS verification before VM deployment (it is a hard requirement)

## Skills System

Task-specific procedures are documented as skills in `hack/skills/<name>/SKILL.md`.

Install skills into your IDE:
```bash
./hack/skills/install-skills.sh --all     # All IDEs
./hack/skills/install-skills.sh --cursor  # Cursor only
./hack/skills/install-skills.sh --claude-code  # Claude Code only
./hack/skills/install-skills.sh --copilot # GitHub Copilot only
```

Available skills:
- `create-cluster-config` - Author cluster.yml + nodes.yml
- `deploy-cluster-kvm` - Full KVM deployment lifecycle
- `deploy-cluster-baremetal` - Bare metal ISO delivery
- `configure-external-access` - HAProxy + Route53 + Let's Encrypt
- `deploy-vyos-router` - VyOS router with manual steps
- `troubleshoot-dns` - DNS diagnostic and repair

## Quick Reference

```bash
# Validate environment
./e2e-tests/validate_env.sh

# Generate ISO
./hack/create-iso.sh <config-name>

# Deploy (KVM)
./hack/deploy-connected-full.sh examples/<cluster>

# Deploy (bare metal)
./hack/deploy-iso-baremetal.sh site-config/<cluster>/nodes.yml --method redfish --iso <path>

# Destroy cluster
./hack/destroy-on-kvm.sh examples/<cluster>/nodes.yml

# DNS management
sudo ./hack/configure-dnsmasq-entries.sh add <cluster.yml>
sudo ./hack/configure-dnsmasq-entries.sh list

# External access
./hack/configure-external-access.sh <cluster.yml>
```
