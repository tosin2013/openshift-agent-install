---
layout: default
title: "ADR-0010-manifest-generation-and-templating: ---"
description: "Architecture Decision Record for Manifest Generation and Template Management"
---

# 10. Manifest Generation and Template Management

## Date
2025-03-09

## Status
Accepted

## Decision Makers
- Development Team
- Platform Engineers

## Stakeholders
- Platform Engineers
- Operators
- Development Team
- Integration Teams

## Context
The project requires a robust and flexible approach to generating OpenShift installation manifests and managing configuration templates. This includes handling various platform types (bare metal, vSphere, none), supporting disconnected installations, and managing complex network configurations.

## Considered Options
1. Manual manifest creation and management
2. Pure YAML with includes
3. Helm charts
4. Custom Go templates
5. Ansible templating system

## Decision
We have implemented a comprehensive manifest generation and templating system using Ansible:

1. **Centralized Manifest Generation**
   - Single playbook (`create-manifests.yml`) for all manifest generation
   - Templated configuration files
   - Support for site-specific configurations

2. **Template Organization**
   - Modular template structure
   - Platform-specific configurations
   - Network configuration templates
   - Security and authentication templates

3. **Configuration Management**
   - Site-specific configuration support
   - Environment-based customization
   - Secure credential handling
   - Multi-platform compatibility

4. **Template Categories**
   - Base Configuration (`install-config.yml.j2`)
   - Agent Configuration (`agent-config.yml.j2`)
   - Cluster Deployment (`clusterdeployment.yml.j2`)
   - Image Management (`clusterimageset.yml.j2`, `imagedigestmirrorset.yml.j2`)
   - Security (`pull-secret.yml.j2`)
   - Update Services (`updateservice.yml.j2`)

## Rationale
- Ansible provides robust templating capabilities
- Jinja2 templating allows for complex logic
- Modular design enables reuse and maintenance
- Consistent manifest generation across environments
- Built-in security features for sensitive data

## Consequences

### Positive
1. Consistent manifest generation
2. Reduced manual errors
3. Platform-specific customization
4. Secure credential handling
5. Support for disconnected environments
6. Easy template maintenance

### Negative
1. Requires Ansible knowledge
2. Template complexity can increase
3. Need to manage template versioning
4. Additional abstraction layer

## Implementation Details

### Manifest Generation Process
- Site configuration loading
- SSH key pair management
- Template processing
- Platform-specific customization
- ZTP manifest support
- Disconnected installation support

### Template Structure
```
playbooks/templates/
├── agent-config.yml.j2
├── agentclusterinstall.yml.j2
├── clusterdeployment.yml.j2
├── clusterimageset.yml.j2
├── imagedigestmirrorset.yml.j2
├── install-config.yml.j2
├── pull-secret.yml.j2
└── updateservice.yml.j2
```

### Configuration Categories
1. **Base Installation**
   - Cluster metadata
   - Network configuration
   - Platform settings

2. **Agent Configuration**
   - Node specifications
   - Network settings
   - Resource requirements

3. **Deployment Settings**
   - Cluster deployment parameters
   - Image configuration
   - Security settings

4. **Platform-Specific**
   - Bare metal configurations
   - vSphere settings
   - Network architecture

## Links

### Test Cases
- Manifest generation tests
- Template validation tests
- Configuration verification tests

### Related ADRs
- ADR-0003: Ansible Automation Approach
- ADR-0004: Disconnected Installation Support
- ADR-0005: ISO Creation and Asset Management

### Code References
- `playbooks/create-manifests.yml`
- `playbooks/templates/*`
- `site-config/` directory structure

### External References
- OpenShift Installation Documentation
- Ansible Best Practices
- Jinja2 Template Documentation

## Related
- [Installation Guide](../installation-guide)
- [Configuration Guide](../configuration-guide)
- [Network Configuration](../network-configuration)
- [Example Configurations](../../examples/)
