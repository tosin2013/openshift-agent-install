---
layout: default
title: "ADR-0004-disconnected-installation-support: ---"
description: "Architecture Decision Record for Disconnected Installation Support"
---

# ADR-004: Disconnected Installation Support

## Date
2025-03-09

## Status
Accepted

## Decision Makers
- OpenShift Platform Team
- Security Team

## Context
Many enterprise environments require the ability to install OpenShift in air-gapped or disconnected networks. This requires:
- Local registry mirroring
- Certificate management
- Proxy configuration
- Update service configuration

## Considered Options

### 1. Basic Disconnected Support
- Pros:
  - Simple implementation
  - Basic mirroring only
- Cons:
  - Limited functionality
  - Manual certificate management
  - No update service support

### 2. Comprehensive Disconnected Support (Selected)
- Pros:
  - Full registry mirroring
  - Automated certificate management
  - Proxy configuration support
  - Update service integration
- Cons:
  - More complex setup
  - Additional configuration required
  - Certificate management overhead

## Decision
Implement comprehensive disconnected installation support with:

1. **Registry Mirroring Configuration**
   ```yaml
   disconnected_registries:
     - target: disconn-harbor.d70.kemo.labs/quay-ptc/openshift-release-dev/ocp-release
       source: quay.io/openshift-release-dev/ocp-release
     - target: disconn-harbor.d70.kemo.labs/quay-ptc/openshift-release-dev/ocp-v4.0-art-dev
       source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
   ```

2. **Certificate Management**
   - Additional trust bundle support
   - ConfigMap-based certificate distribution
   - Update service registry certificates

3. **Proxy Configuration**
   ```yaml
   proxy:
     http_proxy: http://192.168.42.31:3128
     https_proxy: http://192.168.42.31:3128
     no_proxy:
       - .svc.cluster.local
       - .kemo.network
   ```

## Implementation

### Post-Deployment Configuration

1. **Trust Bundle Configuration**
   ```yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: additional-trust-bundle
     namespace: openshift-config
   data:
     ca-bundle.crt: |
       -----BEGIN CERTIFICATE-----
       [certificate data]
       -----END CERTIFICATE-----
   ```

2. **Proxy Configuration**
   ```yaml
   apiVersion: config.openshift.io/v1
   kind: Proxy
   metadata:
     name: cluster
   spec:
     trustedCA:
       name: 'additional-trust-bundle'
   ```

3. **Image Registry Configuration**
   ```yaml
   spec:
     additionalTrustedCA:
       name: additional-trust-bundle
   ```

### Integration Points

1. **Registry Mirroring**
   - ImageTagMirrorSet support
   - ImageDigestMirrorSet configuration
   - Local registry setup

2. **Update Service**
   - Local update service configuration
   - Certificate management
   - Repository mirroring

## Consequences

### Positive
1. Support for air-gapped environments
2. Secure certificate management
3. Flexible proxy configuration
4. Automated update service integration

### Negative
1. Additional setup complexity
2. Certificate management overhead
3. More configuration to maintain

## Validation

### Configuration Validation
1. Certificate validation
2. Registry connectivity tests
3. Proxy configuration verification
4. Update service validation

## Related
- [Installation Guide](../installation-guide)
- [ADR-001: Agent-based Installation](0001-agent-based-installation-approach)
- [ADR-003: Ansible Automation](0003-ansible-automation-approach)
- External: [OCP4 Disconnected Helper](https://github.com/kenmoini/ocp4-disconnected-helper)

## Notes
Key considerations for implementation:
1. Security implications
2. Certificate lifecycle management
3. Registry synchronization
4. Network requirements
5. Update service maintenance

Automated through Ansible playbooks:
```
playbooks/templates/
├── imagedigestmirrorset.yml.j2
└── updateservice.yml.j2
