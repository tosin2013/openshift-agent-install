---
layout: default
title: "ADR-0015: Multipath Root Device Configuration"
description: "Architecture Decision Record for Multipath Root Device Configuration with rootDeviceHints"
---

# ADR-0015: Multipath Root Device Configuration

## Date
2025-01-15

## Status
Accepted

## Decision Makers
- OpenShift Platform Team
- Storage Architecture Team
- Infrastructure Team

## Context

Enterprise OpenShift deployments often require SAN (Storage Area Network) storage for root devices, which typically uses multipath I/O to provide:
- **High Availability**: Redundant paths to storage prevent single points of failure
- **Performance**: Load balancing across multiple paths improves I/O throughput
- **Reliability**: Automatic failover between paths ensures continuous operation

The OpenShift Agent-Based Installer uses `rootDeviceHints` to identify the installation target device. For multipath SAN storage, precise device identification is critical because:
1. Multiple paths to the same device appear as separate devices
2. Device names (`/dev/sda`, `/dev/sdb`) are not stable across reboots
3. WWN (World Wide Name) is the stable identifier for SAN devices

The current template implementation only supported `deviceName`, limiting the ability to precisely identify multipath devices using WWN, vendor, model, and other stable identifiers.

## Considered Options

### 1. Support Only deviceName (Current State)
- Pros:
  - Simple implementation
  - Works for basic scenarios
- Cons:
  - Cannot reliably identify multipath devices
  - Device names change across reboots
  - No way to filter by vendor/model/size
  - Not suitable for enterprise SAN storage

### 2. Support All rootDeviceHints Parameters (Selected)
- Pros:
  - Enables precise device identification via WWN
  - Supports vendor/model filtering for mixed storage
  - Allows size requirements (minSizeGigabytes)
  - Supports SCSI addressing (hctl)
  - Enables SSD vs HDD selection (rotational)
  - Matches OpenShift documentation capabilities
- Cons:
  - More complex template logic
  - Additional documentation required
  - Users need to understand device identification

### 3. Support Only WWN
- Pros:
  - Covers primary multipath use case
  - Simpler than full support
- Cons:
  - Doesn't leverage full OpenShift capabilities
  - Cannot combine hints for precision
  - Limited flexibility for future needs

## Decision

We will support **all rootDeviceHints parameters** in the template to enable comprehensive device identification, with special emphasis on multipath SAN storage scenarios.

### Supported Parameters

| Parameter | Type | Use Case |
|-----------|------|----------|
| `deviceName` | string | Device path (e.g., `/dev/disk/by-id/wwn-*`) |
| `wwn` | string | **Primary for SAN multipath** - stable identifier |
| `vendor` | string | Filter by storage vendor (DGC, EMC, HPE) |
| `model` | string | Filter by storage model |
| `serialNumber` | string | Unique device serial number |
| `minSizeGigabytes` | integer | Ensure minimum storage size |
| `hctl` | string | SCSI address (Host:Channel:Target:Lun) |
| `rotational` | boolean | Prefer SSD (`false`) or HDD (`true`) |

### Implementation

1. **Template Enhancement**: Update `playbooks/templates/agent-config.yml.j2` to conditionally include all rootDeviceHints parameters
2. **Example Configuration**: Create `examples/multipath-root-device/` with comprehensive examples
3. **Documentation**: Provide detailed README with device identification methods
4. **MachineConfig**: Include example for enabling multipath kernel arguments

## Rationale

1. **Enterprise Requirements**: SAN storage is common in enterprise environments requiring multipath support
2. **Stability**: WWN provides stable device identification across reboots and path changes
3. **Flexibility**: Combined hints allow precise device selection in complex environments
4. **Standards Compliance**: Matches OpenShift and BareMetalHost API capabilities
5. **Future-Proof**: Supports various storage scenarios beyond multipath

## Implementation Details

### Template Structure

The template now conditionally includes each rootDeviceHints parameter:

```jinja2
{% if node.rootDeviceHints is defined %}
    rootDeviceHints:
{% if node.rootDeviceHints.deviceName is defined %}
      deviceName: {{ node.rootDeviceHints.deviceName }}
{% endif %}
{% if node.rootDeviceHints.wwn is defined %}
      wwn: "{{ node.rootDeviceHints.wwn }}"
{% endif %}
{# ... additional parameters ... #}
{% endif %}
```

### Example Configurations

**Multipath with WWN:**
```yaml
rootDeviceHints:
  wwn: "0x60060160ba1d3f00a0d2e0d0a0d2e0d0"
  vendor: "DGC"
  minSizeGigabytes: 120
```

**Device Path with WWN:**
```yaml
rootDeviceHints:
  deviceName: "/dev/disk/by-id/wwn-0x60060160ba1d3f00a0d2e0d0a0d2e0d1"
  vendor: "DGC"
  rotational: false
```

**SCSI Address:**
```yaml
rootDeviceHints:
  hctl: "0:0:0:0"
  vendor: "DGC"
  minSizeGigabytes: 120
```

### Multipath Kernel Arguments

Multipath requires kernel arguments that are configured post-installation via MachineConfig:

```yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: "master"
  name: 99-master-kargs-mpath
spec:
  kernelArguments:
    - 'rd.multipath=default'
    - 'root=/dev/disk/by-label/dm-mpath-root'
```

## Consequences

### Positive

1. **Enterprise Storage Support**: Enables reliable deployment on SAN storage
2. **Device Stability**: WWN-based identification prevents boot failures from device name changes
3. **Flexibility**: Multiple hint combinations support various storage scenarios
4. **Documentation**: Comprehensive examples and guides for users
5. **Standards Alignment**: Matches OpenShift official capabilities

### Negative

1. **Complexity**: More parameters to understand and configure
2. **Learning Curve**: Users need to learn device identification methods
3. **Template Maintenance**: More conditional logic in template
4. **Documentation Overhead**: Need to maintain comprehensive documentation

### Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Incorrect WWN format | Documentation with examples and verification steps |
| Device not found during install | Support for multiple hint combinations, fallback options |
| Multipath not enabled | Provide MachineConfig example and verification steps |
| Template errors | Test with various configurations, validate generated manifests |

## Validation

### Test Cases

1. **WWN-only identification**: Verify device selection using only WWN
2. **Combined hints**: Test vendor + WWN + minSizeGigabytes combination
3. **Device path with WWN**: Verify `/dev/disk/by-id/wwn-*` paths work
4. **SCSI address**: Test hctl parameter for SCSI-based identification
5. **Template generation**: Verify all parameters render correctly in agent-config.yaml
6. **Multipath enablement**: Verify MachineConfig applies kernel arguments correctly

### Example Validation

```bash
# Generate manifests
ansible-playbook -e @examples/multipath-root-device/cluster.yml \
  -e @examples/multipath-root-device/nodes.yml \
  playbooks/create-manifests.yml

# Verify generated agent-config.yaml contains all hints
grep -A 10 "rootDeviceHints" generated_manifests/multipath-cluster/agent-config.yaml

# Create ISO and test installation
openshift-install agent create image --dir generated_manifests/multipath-cluster/
```

## Related

- [ADR-0001: Agent-based Installation Approach](0001-agent-based-installation-approach)
- [ADR-0012: Deployment Patterns and Reference Configurations](0012-deployment-patterns-and-configurations)
- [OpenShift Root Device Hints Documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/installing_an_on-premise_cluster_with_the_agent-based_installer/preparing-to-install-with-agent-based-installer#root-device-hints_preparing-to-install-with-agent-based-installer)
- [BareMetalHost rootDeviceHints API](https://github.com/metal3-io/baremetal-operator/blob/main/apis/metal3.io/v1alpha1/baremetalhost_types.go)
- [Enabling Multipathing Post-Installation](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/post-installation_configuration/post-install-machine-configuration-tasks#rhcos-enabling-multipath-day-2_post-install-machine-configuration-tasks)

## Notes

Key considerations:
1. **WWN Format**: WWN can be specified with or without `0x` prefix, but consistency is important
2. **Combined Hints**: All specified hints must match for device selection (AND logic)
3. **Multipath Requirements**: Requires at least 2 active paths for redundancy
4. **Post-Install Configuration**: Multipath kernel arguments must be added via MachineConfig after installation
5. **Device Discovery**: Users must identify WWN values before configuration (documented in README)
6. **Backward Compatibility**: Existing configurations using only `deviceName` continue to work

## Future Enhancements

Potential improvements:
1. Validation script to verify WWN format and device availability
2. Helper script to discover and list available devices with their identifiers
3. Integration with device discovery tools
4. Support for additional BareMetalHost parameters as they become available

