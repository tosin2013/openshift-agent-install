# BMC Management Guide

This guide provides detailed information about Baseboard Management Controller (BMC) configuration and management in OpenShift Agent-based installations. For a comprehensive introduction to BMC technology, see the [DMTF BMC Management Specifications](https://www.dmtf.org/standards/pmci).

## Table of Contents

- [Overview](#overview)
- [BMC Configuration](#bmc-configuration)
- [Redfish Integration](#redfish-integration)
- [Testing Environment](#testing-environment)
- [Automation Tools](#automation-tools)
- [Troubleshooting](#troubleshooting)

## Overview

Baseboard Management Controller (BMC) management is crucial for remote server management and automation in OpenShift deployments. This guide covers both production BMC configurations and development/testing environments using BMC emulation. For foundational understanding, see [Intel's BMC Technical Overview](https://www.intel.com/content/www/us/en/servers/ipmi/ipmi-technical-resources.html).

## BMC Configuration

For detailed BMC configuration best practices, see [Red Hat's BMC Configuration Guide](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/managing_systems_using_the_rhel_8_web_console/configuring-server-management-using-the-rhel-web-console_system-management-using-the-rhel-8-web-console).

### Supported BMC Types

For detailed specifications of each BMC type, refer to:
- [Redfish Specification](https://www.dmtf.org/standards/redfish)
- [IPMI Specification](https://www.intel.com/content/www/us/en/products/docs/servers/ipmi/ipmi-second-gen-interface-spec-v2-rev1-1.html)
- [Dell iDRAC Documentation](https://www.dell.com/support/kbdoc/en-us/000178115/idrac-support-matrix)
- [HPE iLO Documentation](https://support.hpe.com/hpesc/public/docDisplay?docId=a00018324en_us)
- [Lenovo XCC Documentation](https://sysmgt.lenovofiles.com/help/topic/com.lenovo.systems.management.xcc.doc/dw1lm_c_chapter1_introduction.html)

### Basic BMC Setup

```yaml
nodes:
  - hostname: master-0
    role: master
    bmc:
      address: 192.168.1.100
      username: admin
      password: password
      disableCertificateVerification: true
```

## Redfish Integration

For comprehensive Redfish implementation guidelines, see the [DMTF Redfish Implementation Guide](https://www.dmtf.org/sites/default/files/standards/documents/DSP2046_2023.1.pdf).

### Configuration

1. **Enable Redfish API**:
```bash
# Configure sushy-emulator
sudo mkdir -p /etc/sushy
sudo tee /etc/sushy/sushy-emulator.conf << EOF
SUSHY_EMULATOR_LISTEN_IP = '192.168.122.10'
SUSHY_EMULATOR_LISTEN_PORT = 8000
SUSHY_EMULATOR_SSL_CERT = None
SUSHY_EMULATOR_SSL_KEY = None
SUSHY_EMULATOR_OS_CLOUD = None
SUSHY_EMULATOR_LIBVIRT_URI = 'qemu+unix:///system'
SUSHY_EMULATOR_IGNORE_BOOT_DEVICE = True
EOF
```

2. **Configure Network Interface**:
```bash
sudo ip link add sushy-bmc link virbr0 type macvlan mode bridge
sudo ip addr add 192.168.122.10/24 dev sushy-bmc
sudo ip link set sushy-bmc up
```

3. **Setup Firewall Rules**:
```bash
sudo firewall-cmd --zone=libvirt --add-port=8000/tcp --permanent
sudo firewall-cmd --permanent --zone=trusted --add-interface=sushy-bmc
sudo firewall-cmd --reload
```

### Container Deployment

```bash
# Deploy sushy-emulator container
sudo podman create --name sushy-emulator \
    --network=host \
    --privileged \
    -v "/etc/sushy":/etc/sushy:Z \
    -v "/var/run/libvirt":/var/run/libvirt:Z \
    quay.io/metal3-io/sushy-tools \
    sushy-emulator -i 192.168.122.10 -p 8000
```

### Systemd Service

```bash
# Generate and enable systemd service
sudo podman generate systemd --restart-policy=always --new -n sushy-emulator > \
    /etc/systemd/system/sushy-emulator.service
sudo systemctl daemon-reload
sudo systemctl enable --now sushy-emulator
```

## Testing Environment

For detailed information about virtual BMC testing environments, see [Metal3-io's Documentation](https://metal3.io/documentation.html).

### Virtual BMC Setup

1. **Prerequisites**:
```bash
sudo dnf install -y libvirt libvirt-daemon-driver-qemu
sudo systemctl enable --now libvirtd
```

2. **Configure Testing Environment**:
```bash
# Run the configuration script
./hack/configure-sushy-unix.sh
```

### Validation

```bash
# Test Redfish API
curl -s http://192.168.122.10:8000/redfish/v1/Systems | python3 -m json.tool

# Check service status
systemctl status sushy-emulator

# View container logs
sudo podman logs sushy-emulator
```

## Automation Tools

### BMC Host Generation

```bash
# Generate BMC hosts configuration
./hack/generate_bmc_acm_hosts.py
```

### Automation Scripts

1. **Configure BMC Interface**:
```bash
./hack/configure-sushy-unix.sh
```

2. **Deploy Test Environment**:
```bash
./hack/deploy-on-kvm.sh examples/bond0-signal-vlan/nodes.yml --redfish
```

## Security Considerations

For comprehensive BMC security guidelines, refer to:
- [NIST Security Guidelines for BMC](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-193.pdf)
- [DMTF Security Protocol and Data Model](https://www.dmtf.org/sites/default/files/standards/documents/DSP0274_1.0.0.pdf)
- [OpenBMC Security Guide](https://github.com/openbmc/docs/blob/master/security/SECURITY.md)

## Production Recommendations

For production deployment best practices, see:
- [Red Hat's Enterprise Hardware Management Guide](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/managing_systems_using_the_rhel_8_web_console/managing-systems-using-the-rhel-8-web-console_system-management-using-the-rhel-8-web-console)
- [DMTF Platform Management Components White Paper](https://www.dmtf.org/sites/default/files/standards/documents/DSP2018_1.0.0.pdf)
- [Intel Data Center BMC Management Guide](https://www.intel.com/content/www/us/en/products/docs/servers/enterprise-servers/server-management-white-paper.html)

## Troubleshooting

For detailed troubleshooting procedures, refer to:
- [Red Hat's BMC Troubleshooting Guide](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/managing_systems_using_the_rhel_8_web_console/troubleshooting-problems-with-managing-systems-using-the-rhel-8-web-console_system-management-using-the-rhel-8-web-console)
- [OpenBMC Debugging Guide](https://github.com/openbmc/docs/blob/master/development/dev-environment.md)
- [Metal3-io Troubleshooting Guide](https://metal3.io/documentation/troubleshooting.html)

## Related Documentation

### Internal References
- [BMC Management and Infrastructure Automation ADR](adr/0008-bmc-management-and-automation.md)
- [Virtual Infrastructure Testing ADR](adr/0007-virtual-infrastructure-testing.md)
- [Installation Guide](installation-guide.md)
- [Example Configurations](examples/)

### OpenShift Documentation
- [OpenShift Bare Metal Installation](https://docs.openshift.com/container-platform/latest/installing/installing_bare_metal/installing-bare-metal.html)
- [OpenShift BMC Configuration](https://docs.openshift.com/container-platform/latest/installing/installing_bare_metal_ipi/ipi-install-prerequisites.html#ipi-install-bmc-addressing_ipi-install-prerequisites)
- [OpenShift Metal³ Integration](https://docs.openshift.com/container-platform/latest/architecture/control-plane.html#machine-api-overview-metal3_control-plane)

### Hardware Vendor BMC Documentation
- [Dell iDRAC User Guide](https://www.dell.com/support/manuals/en-us/idrac9-lifecycle-controller-v6.x/idrac9_6.xx_ug_new/)
- [HPE iLO Documentation](https://support.hpe.com/hpesc/public/docDisplay?docId=a00018324en_us)
- [Lenovo XClarity Controller Documentation](https://sysmgt.lenovofiles.com/help/topic/com.lenovo.systems.management.xcc.doc/dw1lm_c_chapter1_introduction.html)
- [Supermicro IPMI Utilities](https://www.supermicro.com/manuals/other/IPMI_Users_Guide.pdf)

### Industry Standards and Specifications
- [DMTF Redfish Standard](https://www.dmtf.org/standards/redfish)
- [IPMI v2.0 Specification](https://www.intel.com/content/www/us/en/products/docs/servers/ipmi/ipmi-second-gen-interface-spec-v2-rev1-1.html)
- [DMTF Common Information Model](https://www.dmtf.org/standards/cim)

### Implementation Tools and Libraries
- [Sushy BMC Emulator](https://docs.openstack.org/sushy/latest/)
- [OpenBMC Project Documentation](https://github.com/openbmc/docs)
- [Metal³ BMC Operator](https://github.com/metal3-io/baremetal-operator)
- [Redfish Python Library](https://github.com/DMTF/python-redfish-library)

### Security Guidelines
- [NIST SP 800-193 Platform Firmware Resiliency](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-193.pdf)
- [DMTF Security Protocol and Data Model](https://www.dmtf.org/sites/default/files/standards/documents/DSP0274_1.0.0.pdf)

## Support Matrix

| Feature | Virtual BMC | Physical BMC |
|---------|------------|--------------|
| Redfish API | ✓ | ✓ |
| IPMI | ✓ | ✓ |
| Power Management | ✓ | ✓ |
| Virtual Media | ✓ | ✓ |
| Sensor Monitoring | ✓ | ✓ |
| Certificate Management | ✓ | ✓ |

---
*Note: Keep your BMC firmware and management tools updated to ensure security and compatibility.*
