# Multipath Root Device Configuration Example

This example demonstrates how to configure OpenShift nodes with multipath SAN storage using combined `rootDeviceHints` parameters. Multipath I/O provides redundant paths to storage devices (Fibre Channel SAN, iSCSI), improving availability and performance.

## Overview

**Multipath I/O** is essential for enterprise storage environments where:
- High availability is required (redundant paths to storage)
- Performance optimization is needed (load balancing across paths)
- SAN storage (FC or iSCSI) is used for root devices

## Prerequisites

- RHEL-based system for running the installer
- OpenShift CLI tools (`openshift-install`, `oc`)
- NMState CLI (`dnf install nmstate`)
- Ansible Core (`dnf install ansible-core`)
- Red Hat OpenShift Pull Secret
- SAN storage configured with multipath devices
- Access to identify WWN (World Wide Name) values for storage devices

## Finding Device Information

Before configuring `rootDeviceHints`, you need to identify your storage devices. On a RHEL system with access to the storage:

### Find WWN Values

```bash
# List all disk devices with WWN identifiers
ls -la /dev/disk/by-id/ | grep wwn

# Example output:
# lrwxrwxrwx 1 root root  9 Dec 10 10:00 wwn-0x60060160ba1d3f00a0d2e0d0a0d2e0d0 -> ../../sda

# Using lsblk to see device information
lsblk -o NAME,SIZE,TYPE,WWN,MODEL,VENDOR

# Using multipath to see multipath devices
multipath -ll
```

### Find Vendor and Model

```bash
# Using udevadm to get device information
udevadm info /dev/sda | grep -E "ID_VENDOR|ID_MODEL|ID_SERIAL"

# Using hwinfo (if available)
hwinfo --disk --short
```

### Find SCSI Address (hctl)

```bash
# List SCSI devices with their addresses
lsscsi

# Example output:
# [0:0:0:0]    disk    DGC     RAID 5           0324  /dev/sda
# Format: [Host:Channel:Target:Lun]
```

## Configuration Files

### cluster.yml

Standard cluster configuration for baremetal deployment. See the file for details.

### nodes.yml

Node definitions with multipath `rootDeviceHints`. This example demonstrates different combinations of hints:

#### Example 1: WWN with Vendor and Size

```yaml
rootDeviceHints:
  wwn: "0x60060160ba1d3f00a0d2e0d0a0d2e0d0"
  vendor: "DGC"
  minSizeGigabytes: 120
```

#### Example 2: Device Path with WWN

```yaml
rootDeviceHints:
  deviceName: "/dev/disk/by-id/wwn-0x60060160ba1d3f00a0d2e0d0a0d2e0d1"
  vendor: "DGC"
  minSizeGigabytes: 120
  rotational: false
```

#### Example 3: WWN with Serial Number

```yaml
rootDeviceHints:
  wwn: "0x60060160ba1d3f00a0d2e0d0a0d2e0d2"
  serialNumber: "60060160BA1D3F00A0D2E0D0A0D2E0D2"
  minSizeGigabytes: 120
```

#### Example 4: SCSI Address (hctl)

```yaml
rootDeviceHints:
  hctl: "0:0:0:0"
  vendor: "DGC"
  minSizeGigabytes: 120
```

## Available rootDeviceHints Parameters

| Parameter | Type | Description | Example |
|-----------|------|-------------|----------|
| `deviceName` | string | Device path | `/dev/sda`, `/dev/disk/by-id/wwn-0x...` |
| `wwn` | string | World Wide Name identifier | `"0x60060160ba1d3f00a0d2e0d0a0d2e0d0"` |
| `vendor` | string | Disk vendor/manufacturer | `"DGC"`, `"EMC"`, `"HPE"` |
| `model` | string | Disk model name | `"RAID 5"`, `"VNX"` |
| `serialNumber` | string | Disk serial number | `"60060160BA1D3F00A0D2E0D0A0D2E0D2"` |
| `minSizeGigabytes` | integer | Minimum disk size in GB | `120`, `500` |
| `hctl` | string | SCSI address (Host:Channel:Target:Lun) | `"0:0:0:0"` |
| `rotational` | boolean | `true` for HDD, `false` for SSD/NVMe | `false` |

**Note:** You can combine multiple hints. A device must match ALL specified hints to be selected.

## Enabling Multipath Kernel Arguments

After installation, you need to enable multipath kernel arguments. Two options:

### Option 1: MachineConfig (Post-Installation)

Apply the provided `machineconfig-multipath.yaml`:

```bash
# For control plane nodes
oc create -f machineconfig-multipath.yaml

# Verify the MachineConfig was applied
oc get machineconfig 99-master-kargs-mpath
oc get machineconfig 99-worker-kargs-mpath
```

### Option 2: During Installation (Advanced)

If you need multipath enabled from the first boot, you would need to modify the installation process. This typically requires:
- Customizing the RHCOS installation
- Adding kernel arguments to the boot configuration

**Note:** The agent-based installer doesn't directly support kernel arguments in `agent-config.yaml`. Use MachineConfig for post-installation configuration.

## Verification

After applying the MachineConfig and rebooting nodes:

```bash
# Debug into a node
oc debug node/master-0

# In the debug shell
chroot /host

# Check kernel arguments
cat /proc/cmdline | grep multipath
# Should show: rd.multipath=default root=/dev/disk/by-label/dm-mpath-root

# Check multipath status
multipath -ll

# Verify root device is multipath
df -h / | grep mapper
```

## Troubleshooting

### Device Not Found

If the installer cannot find a matching device:

1. **Verify WWN format**: Ensure WWN is in correct format (with or without `0x` prefix)
2. **Check device availability**: Ensure the device is visible during installation
3. **Simplify hints**: Try using only `wwn` first, then add additional hints
4. **Check logs**: Review installation logs for device discovery errors

### Multipath Not Working

If multipath is not functioning after installation:

1. **Verify MachineConfig**: Check that MachineConfig was applied and nodes rebooted
2. **Check multipath service**: `systemctl status multipathd`
3. **Verify paths**: `multipath -ll` should show multiple paths
4. **Check kernel arguments**: Verify `rd.multipath=default` is in `/proc/cmdline`

### Boot Failures

If nodes fail to boot with multipath:

1. **Ensure multiple paths**: Multipath requires at least 2 active paths
2. **Check root device label**: Verify `dm-mpath-root` label exists
3. **Review boot logs**: Check journal logs for multipath errors

## Reference Links

### Official Documentation

- [OpenShift Root Device Hints Documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/installing_an_on-premise_cluster_with_the_agent-based_installer/preparing-to-install-with-agent-based-installer#root-device-hints_preparing-to-install-with-agent-based-installer)
  - Complete reference for all rootDeviceHints parameters
  - Examples and use cases

- [Enabling Multipathing Post-Installation](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/post-installation_configuration/post-install-machine-configuration-tasks#rhcos-enabling-multipath-day-2_post-install-machine-configuration-tasks)
  - MachineConfig examples
  - Verification steps

- [BareMetalHost rootDeviceHints API Reference](https://github.com/metal3-io/baremetal-operator/blob/main/apis/metal3.io/v1alpha1/baremetalhost_types.go)
  - Source code reference for rootDeviceHints structure
  - All available parameters

### Related Documentation

- [OpenShift Agent-Based Installer Guide](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/installing_an_on-premise_cluster_with_the_agent-based_installer/installing_an_on-premise_cluster_with_the_agent-based_installer)
- [Machine Configuration Guide](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/post-installation_configuration/post-install-machine-configuration-tasks)
- [RHCOS Storage Configuration](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/installing/installing-on-bare-metal/installing-on-bare-metal)

## Usage

1. **Customize the configuration**:
   - Update `cluster.yml` with your cluster details
   - Update `nodes.yml` with your node information and WWN values
   - Modify network configuration as needed

2. **Generate the ISO**:
   ```bash
   ./hack/create-iso.sh multipath-root-device
   ```

3. **Boot nodes from the ISO** and monitor installation

4. **Apply MachineConfig** (after installation):
   ```bash
   oc create -f examples/multipath-root-device/machineconfig-multipath.yaml
   ```

5. **Reboot nodes** to apply kernel arguments:
   ```bash
   oc get nodes
   oc debug node/<node-name> -- chroot /host reboot
   ```

## Notes

- **WWN is primary identifier**: For SAN storage, WWN is the most reliable identifier
- **Combine hints for precision**: Use multiple hints to precisely identify the target device
- **Test in non-production first**: Multipath configuration changes require node reboots
- **Backup before changes**: Always backup cluster configuration before making changes
- **Monitor after changes**: Watch node status after applying MachineConfig changes

## Example Use Cases

1. **Fibre Channel SAN**: Use WWN to identify FC-attached storage
2. **iSCSI SAN**: Use WWN or deviceName with by-id paths
3. **Mixed storage**: Use vendor/model to distinguish between storage types
4. **Size requirements**: Use minSizeGigabytes to ensure sufficient storage
5. **Performance tiering**: Use rotational=false to prefer SSD/NVMe devices

