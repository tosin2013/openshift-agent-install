# Claude Instructions for OpenShift Agent-Based Installer

## Project Overview

This repository provides automated deployment tooling for OpenShift clusters using the Agent-Based Installer. It supports SNO, 3-node, and HA cluster deployments on bare metal, vSphere, and platform=none configurations.

**Primary Use Case**: Automate OpenShift cluster deployments with declarative YAML configuration and streamlined DNS management.

## Key Resources

### Primary Reference Documents

**llm.txt** - Read this file for comprehensive deployment information:
- Complete deployment workflow (7 phases)
- All 24+ scripts documented with usage, arguments, examples
- Configuration reference (cluster.yml, nodes.yml)
- Troubleshooting guide
- Quick start commands

**Location**: `/home/vpcuser/openshift-agent-install/llm.txt`

**Usage**: When answering deployment questions, consult llm.txt first for:
- Script usage and examples
- Configuration parameters
- Deployment phases and workflow
- Common troubleshooting steps

### Other Important Files

- `README.md` - Overview and quick start
- `DNS_AUTOMATION.md` - DNS automation implementation details
- `docs/` - Detailed guides and ADRs
- `examples/` - Reference cluster configurations

## Repository Structure

```
openshift-agent-install/
├── llm.txt                    # COMPREHENSIVE DEPLOYMENT GUIDE - READ FIRST
├── CLAUDE.md                  # This file
├── README.md                  # Project overview
├── DNS_AUTOMATION.md          # DNS automation guide
├── e2e-tests/                 # Bootstrap and testing scripts
│   ├── bootstrap_env.sh       # Complete environment setup
│   ├── validate_env.sh        # Environment validation
│   └── run_e2e.sh             # E2E test workflow
├── hack/                      # Core deployment scripts
│   ├── create-iso.sh          # Generate Agent-Based Installer ISO
│   ├── deploy-on-kvm.sh       # Deploy to KVM/libvirt
│   ├── destroy-on-kvm.sh      # Cleanup/destroy cluster
│   ├── setup-dnsmasq.sh       # Install dnsmasq DNS server
│   └── configure-dnsmasq-entries.sh  # Manage DNS entries
├── playbooks/                 # Ansible automation
│   └── create-manifests.yml   # Template ABI manifests
├── examples/                  # Cluster configuration examples
│   ├── sno-4.20-standard/     # SNO deployment
│   ├── ha-4.21-disconnected/  # HA air-gap deployment
│   └── serenity-sno.*/        # SNO with registry mirrors
└── execution-environment/     # Ansible EE container definition
```

## Common User Tasks

### 1. Initial Environment Setup
```bash
sudo ./e2e-tests/bootstrap_env.sh
./e2e-tests/validate_env.sh
```

### 2. DNS Configuration
```bash
sudo ./hack/setup-dnsmasq.sh
sudo ./hack/configure-dnsmasq-entries.sh add examples/sno-4.20-standard/cluster.yml
```

### 3. Create Cluster ISO
```bash
./hack/create-iso.sh sno-4.20-standard
```

### 4. Deploy to KVM
```bash
./hack/deploy-on-kvm.sh examples/sno-4.20-standard/nodes.yml --redfish
```

### 5. Monitor Installation
```bash
./bin/openshift-install agent wait-for install-complete --dir ~/generated_assets/sno-4-20/
```

### 6. Cleanup
```bash
./hack/destroy-on-kvm.sh examples/sno-4.20-standard/nodes.yml
```

## Helping Users

### When Users Ask About...

**"How do I deploy OpenShift?"**
→ Reference llm.txt "Quick Start" section and "Deployment Steps (Ordered Workflow)"

**"What scripts are available?"**
→ Reference llm.txt "Scripts Reference" section (24 scripts, alphabetically sorted)

**"How do I configure DNS?"**
→ Reference llm.txt sections on setup-dnsmasq.sh and configure-dnsmasq-entries.sh
→ Also reference DNS_AUTOMATION.md for implementation details

**"What parameters can I set in cluster.yml?"**
→ Reference llm.txt "Configuration Reference" → "cluster.yml Parameters"

**"I'm getting an error..."**
→ Reference llm.txt "Troubleshooting" section

**"What are the example configurations?"**
→ Reference llm.txt "Additional Resources" → "Example Configurations"
→ Or examine files in examples/ directory directly

### Script Documentation Pattern

When asked about a specific script, provide:
1. **Location**: Full path
2. **Description**: What it does
3. **Usage**: Command syntax with arguments
4. **Example**: Concrete usage example
5. **Phase**: Where it fits in deployment workflow

All this information is available in llm.txt "Scripts Reference" section.

### Configuration Help Pattern

When helping with cluster.yml or nodes.yml:
1. **Read the example** from examples/ directory
2. **Reference parameters** from llm.txt "Configuration Reference"
3. **Provide concrete examples** for the user's use case
4. **Validate YAML syntax** if creating new configurations

## Key Concepts

### Deployment Patterns

1. **SNO (Single Node OpenShift)**
   - control_plane_replicas: 1
   - app_node_replicas: 0
   - platform_type: none
   - VIPs match node IP

2. **3-Node Compact Cluster**
   - control_plane_replicas: 3
   - app_node_replicas: 0
   - platform_type: baremetal or none

3. **HA Cluster**
   - control_plane_replicas: 3
   - app_node_replicas: 2+ (workers)
   - platform_type: baremetal or vsphere

### DNS Architecture

- **Current**: Lightweight dnsmasq (preferred)
  - setup-dnsmasq.sh installs dnsmasq
  - configure-dnsmasq-entries.sh manages DNS entries
  - Automatic DNS configuration in deploy-on-kvm.sh

- **Legacy**: FreeIPA (deprecated)
  - deploy-freeipa.sh
  - configure_dns_entries.sh
  - freeipa_vars.sh

Always recommend dnsmasq approach for new deployments.

### Environment Variables

Key variables (see llm.txt for complete list):

- `SITE_CONFIG_DIR` - Where cluster configs live (default: "examples")
- `GENERATED_ASSET_PATH` - Where ISOs/manifests go (default: "~/generated_assets")
- `CLUSTER_NAME` - Cluster identifier (auto-detected or override)

## Code Analysis Guidelines

### When Reading Scripts

1. **Check shebang and set options**: Look for `set -e`, `set -x`, etc.
2. **Identify dependencies**: What packages/tools are required?
3. **Find environment variables**: What can be configured?
4. **Locate main logic**: What's the primary function?
5. **Check error handling**: How are failures handled?

### When Suggesting Modifications

1. **Maintain existing patterns**: Match the coding style
2. **Preserve error handling**: Keep `set -e` and error checks
3. **Document changes**: Add comments for complex logic
4. **Consider determinism**: Ensure reproducible behavior
5. **Test suggestions**: Verify syntax and logic before suggesting

### When Debugging Issues

1. **Check llm.txt troubleshooting**: Most common issues are documented
2. **Examine logs**: Point users to relevant log locations
3. **Verify prerequisites**: Use validate_env.sh output
4. **Check file permissions**: Many scripts need sudo/root
5. **Validate YAML**: cluster.yml and nodes.yml syntax errors are common

## File Editing Patterns

### Cluster Configuration

When helping users create/modify cluster.yml:
- Use examples/ as templates
- Validate required fields: cluster_name, base_domain, api_vips, app_vips
- Check network CIDR overlaps
- Verify platform_type matches deployment pattern

### Node Configuration

When helping users create/modify nodes.yml:
- Ensure MAC addresses are unique
- Validate NMState syntax (use nmstatectl gc for validation)
- Check interface names match actual hardware
- Verify root device hints

### Network Configuration

Three common patterns (see llm.txt for full examples):
1. **VLAN**: Tagged VLAN on single interface
2. **Bond**: Link aggregation (LACP, active-backup, etc.)
3. **Bond + VLAN**: Tagged VLAN on bonded interface

## Important Notes

### Do NOT

- ❌ Suggest modifying core deployment scripts without clear justification
- ❌ Recommend deprecated FreeIPA approach for new deployments
- ❌ Ignore error handling in suggested code
- ❌ Provide untested complex script modifications
- ❌ Override security-critical settings without explanation

### DO

- ✅ Reference llm.txt for accurate information
- ✅ Provide concrete examples from examples/ directory
- ✅ Explain the deployment workflow phases
- ✅ Point to troubleshooting section for common errors
- ✅ Validate YAML syntax when helping with configs
- ✅ Recommend environment validation (validate_env.sh)
- ✅ Explain the dnsmasq DNS approach for new setups

## Version Information

- **Supported OpenShift**: 4.15+ (tested with 4.20.x, 4.21.x)
- **Supported RHEL**: 9.x (recommended), 8.x (supported)
- **Repository**: https://github.com/tosin2013/openshift-agent-install

## Quick Command Reference

```bash
# Read comprehensive guide
less llm.txt

# Validate environment
./e2e-tests/validate_env.sh

# List available examples
ls -la examples/

# Check script usage (all scripts support -h or have usage functions)
./hack/create-iso.sh --help  # (will show usage when run without args)

# View DNS entries
sudo ./hack/configure-dnsmasq-entries.sh list

# Check cluster status
export KUBECONFIG=~/generated_assets/${CLUSTER_NAME}/auth/kubeconfig
oc get nodes
oc get co
```

## When in Doubt

1. **Read llm.txt first** - It contains comprehensive, deterministic documentation
2. **Check examples/** - Reference configurations for common patterns
3. **Run validate_env.sh** - Verify prerequisites before deployment
4. **Review DNS_AUTOMATION.md** - Understand DNS implementation
5. **Examine error logs** - Most errors have clear log outputs

## Memory Context

When working with this repository, Claude should:
- Load llm.txt into context for deployment questions
- Reference example configurations for cluster setup help
- Check script documentation in llm.txt before explaining scripts
- Use troubleshooting section for error diagnosis
- Maintain awareness of deployment phases and workflow

This ensures accurate, consistent, and helpful responses based on the actual repository content.
