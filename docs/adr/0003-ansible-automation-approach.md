---
layout: default
title: "ADR-0003-ansible-automation-approach: ---"
description: "Architecture Decision Record for Ansible-based Automation for Agent Installation"
---

# ADR-003: Ansible-based Automation for Agent Installation

## Date
2025-03-09

## Status
Accepted

## Decision Makers
- OpenShift Platform Team
- Automation Team

## Context
The OpenShift Agent-Based Installer requires several configuration files and steps to create bootable installation media. Manual creation and management of these configurations can be:
- Error-prone
- Time-consuming
- Difficult to standardize
- Hard to maintain across multiple clusters

## Considered Options

### 1. Manual Configuration
- Pros:
  - Direct control over all settings
  - No additional dependencies
- Cons:
  - Error-prone
  - Time-consuming
  - Hard to maintain
  - No standardization

### 2. Shell Scripts Only
- Pros:
  - Simple to understand
  - No additional dependencies
  - Direct system interaction
- Cons:
  - Limited templating capabilities
  - Complex configuration management
  - Platform-dependent

### 3. Ansible Automation (Selected)
- Pros:
  - Powerful templating
  - Declarative configuration
  - Idempotent operations
  - Cross-platform support
  - Extensive module ecosystem
- Cons:
  - Additional dependency (ansible-core)
  - Learning curve for Ansible

## Decision
Implement an Ansible-based automation approach with:

1. **Declarative Configuration**
   ```
   ./hack/create-iso.sh $FOLDER_NAME
   ```
   - Use cluster.yml and nodes.yml for configuration
   - Generate templates with Ansible
   - Create ISO automatically

2. **Manual Option Preservation**
   - Keep manual steps documented
   - Allow step-by-step execution
   - Support custom modifications

3. **Prerequisites Management**
   ```yaml
   # Required tools
   - ansible-core
   - nmstate
   - Ansible Collections from requirements.yml
   ```

## Implementation

### Directory Structure
```
playbooks/
├── create-manifests.yml
├── collections/
│   └── requirements.yml
└── templates/
    ├── agent-config.yml.j2
    ├── install-config.yml.j2
    └── other templates...
```

### Configuration Examples
Located in `examples/` directory:
```
examples/
├── baremetal-example/
├── vmware-example/
└── various configurations...
```

### Usage Patterns

1. **Declarative Approach**
   ```bash
   ./hack/create-iso.sh $FOLDER_NAME
   ```

2. **Manual Approach**
   ```bash
   cd playbooks/
   ansible-playbook -e "@your-cluster-vars.yml" create-manifests.yml
   ```

## Consequences

### Positive
1. Standardized configuration management
2. Reduced human error
3. Faster deployment
4. Maintainable configurations
5. Version-controlled templates

### Negative
1. Additional dependencies
2. Initial setup overhead
3. Ansible knowledge required

## Validation

### Configuration Steps
1. Validate prerequisites:
   ```bash
   dnf install ansible-core nmstate
   ansible-galaxy install -r playbooks/collections/requirements.yml
   ```

2. Verify configurations:
   - Check cluster.yml and nodes.yml
   - Validate template generation
   - Test ISO creation

## Related
- [Installation Guide](../installation-guide)
- [ADR-001: Agent-based Installation](0001-agent-based-installation-approach)
- [ADR-002: Network Configurations](0002-advanced-networking-configurations)

## Notes
The automation approach is particularly suited for:
- Repetitive deployments
- Multiple cluster configurations
- Standardized environments
- CI/CD integration

Templates support various deployment types:
- Single-node OpenShift (SNO)
- Three-node compact clusters
- Full HA deployments
