---
layout: default
title: "ADR-0005-iso-creation-and-asset-management: ---"
description: "Architecture Decision Record for ISO Creation and Asset Management"
---

# ADR-005: ISO Creation and Asset Management

## Date
2025-03-09

## Status
Accepted

## Decision Makers
- OpenShift Platform Team
- Automation Team

## Context
The OpenShift Agent-Based Installer requires a bootable ISO image containing all necessary configurations. Managing the creation of these ISOs and related assets requires:
- Consistent asset organization
- Automated ISO generation
- Clear post-installation instructions
- Support for multiple cluster configurations

## Considered Options

### 1. Manual ISO Creation
- Pros:
  - Direct control over process
  - No automation overhead
- Cons:
  - Error-prone
  - Time-consuming
  - Inconsistent results
  - Poor scalability

### 2. Automated ISO Creation with Asset Management (Selected)
- Pros:
  - Consistent results
  - Automated generation
  - Organized asset storage
  - Clear instructions
  - Support for multiple clusters
- Cons:
  - Additional script maintenance
  - Storage space requirements
  - Initial setup complexity

## Decision
Implement an automated ISO creation and asset management system with:

1. **Standardized Directory Structure**
   ```bash
   ${GENERATED_ASSET_PATH}/
   └── ${CLUSTER_NAME}/
       ├── agent.x86_64.iso
       ├── auth/
       │   ├── kubeconfig
       │   └── kubeadmin-password
       └── post-install-instructions.txt
   ```

2. **Configurable Asset Locations**
   ```bash
   SITE_CONFIG_DIR="${SITE_CONFIG_DIR:-examples}"
   GENERATED_ASSET_PATH="${GENERATED_ASSET_PATH:-${HOME}/generated_assets}"
   ```

3. **One-Command ISO Creation**
   ```bash
   ./hack/create-iso.sh $FOLDER_NAME
   ```

## Implementation

### Script Flow
```bash
1. Validate environment and inputs
2. Download OpenShift binaries if needed
3. Extract cluster configuration
4. Template manifests with Ansible
5. Generate ISO
6. Create post-installation instructions
```

### Configuration Structure
```
examples/
├── baremetal-example/
│   ├── cluster.yml
│   └── nodes.yml
└── vmware-example/
    ├── cluster.yml
    └── nodes.yml
```

### Validation Steps
1. Directory existence checks
2. Configuration validation
3. Binary availability verification
4. Asset path management

### Asset Generation
1. **Manifests**
   - Generated via Ansible templating
   - Based on cluster.yml and nodes.yml
   - Stored in cluster-specific directory

2. **ISO Creation**
   - Uses openshift-install agent
   - Includes all configurations
   - Generates bootable image

3. **Instructions**
   - Generated automatically
   - Includes next steps
   - Contains access credentials
   - Saved for reference

## Consequences

### Positive
1. Consistent ISO generation
2. Organized asset management
3. Clear documentation
4. Repeatable process
5. Multiple cluster support

### Negative
1. Storage space requirements
2. Script maintenance overhead
3. Additional dependencies

## Validation

### Pre-flight Checks
```bash
- Binary availability
- Configuration presence
- Directory permissions
```

### Post-generation Validation
```bash
- ISO file existence
- Authentication files
- Instructions generation
```

## Related
- [Installation Guide](../installation-guide)
- [ADR-001: Agent-based Installation](0001-agent-based-installation-approach)
- [ADR-003: Ansible Automation](0003-ansible-automation-approach)

## Notes
Key aspects:
1. Asset organization
2. Error handling
3. User guidance
4. Resource management
5. Security considerations

Generated assets include:
1. Bootable ISO
2. Authentication details
3. Access instructions
4. Configuration backups
