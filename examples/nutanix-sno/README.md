# Nutanix SNO Deployment Example

This example demonstrates deploying a Single Node OpenShift (SNO) cluster on Nutanix AHV using the Agent-Based Installer.

## Overview

- **Topology**: SNO (1 control plane, 0 workers)
- **Platform**: Nutanix AHV
- **Network**: OVNKubernetes
- **OpenShift Version**: 4.21+

## Prerequisites

### Nutanix Environment

1. **Prism Central**: Access to Nutanix Prism Central with API credentials
2. **Prism Element**: At least one Prism Element cluster registered
3. **Networking**: VLAN/network configured with:
   - DHCP or static IP allocation
   - Internet access (for connected deployments)
   - DNS resolution for `api.<cluster>.<domain>` and `*.apps.<cluster>.<domain>`

### Nutanix Requirements

- **Storage**: Minimum 120 GB per node
- **CPU**: Minimum 8 vCPUs per node
- **Memory**: Minimum 32 GB RAM per node (64 GB recommended)
- **Network**: VLAN with internet access

### Gather Nutanix Information

Before deployment, collect the following from your Nutanix environment:

```bash
# Prism Central details
PRISM_CENTRAL_HOST="prism-central.example.com"
PRISM_CENTRAL_USERNAME="admin"
PRISM_CENTRAL_PASSWORD="changeme"

# Prism Element details
PRISM_ELEMENT_HOST="prism-element.example.com"
PRISM_ELEMENT_UUID="00000000-0000-0000-0000-000000000000"

# Network subnet UUID
SUBNET_UUID="subnet-uuid-1234-5678-90ab-cdef"
```

To find these values:
1. Log in to Prism Central UI
2. Navigate to **Infrastructure** > **Clusters** to find Prism Element UUID
3. Navigate to **Network & Security** > **Subnets** to find Subnet UUID

## Configuration

### Step 1: Update cluster.yml

Edit `cluster.yml` and replace the following:

```yaml
# Cluster name and domain
base_domain: example.com          # Your DNS domain
cluster_name: nutanix-sno         # Your cluster name

# Nutanix Prism Central
nutanix_prism_central_host: prism-central.example.com
nutanix_prism_central_username: admin
nutanix_prism_central_password: "changeme"

# Nutanix Prism Element
nutanix_prism_element_host: prism-element.example.com
nutanix_prism_element_uuid: "00000000-0000-0000-0000-000000000000"

# Nutanix subnet
nutanix_subnet_uuids:
  - "subnet-uuid-1234-5678-90ab-cdef"

# VIPs (same as node IP for SNO)
api_vips:
  - 192.168.1.100
app_vips:
  - 192.168.1.100

# Network configuration
machine_network_cidrs:
  - 192.168.1.0/24
rendezvous_ip: 192.168.1.100

# DNS servers
dns_servers:
  - 192.168.1.1
```

### Step 2: Update nodes.yml

Edit `nodes.yml` and configure the node network:

```yaml
nodes:
  - hostname: nutanix-sno-master-0
    role: master
    interfaces:
      - name: enp1s0
        mac-address: "52:54:00:00:00:01"  # Nutanix will assign actual MAC
        ipv4:
          address:
            - ip: 192.168.1.100           # Must match VIPs for SNO
              prefix-length: 24
    routes:
      config:
        - destination: 0.0.0.0/0
          next-hop-address: 192.168.1.1   # Your gateway
```

### Step 3: DNS Configuration

Create DNS records for:

```
api.nutanix-sno.example.com       A    192.168.1.100
*.apps.nutanix-sno.example.com    A    192.168.1.100
```

## Deployment

### Generate Installation Manifests

```bash
cd /path/to/openshift-agent-install

# Generate manifests
./hack/create-iso.sh nutanix-sno
```

### Review Generated Manifests

```bash
# Check install-config.yaml
cat ~/generated_assets/nutanix-sno/install-config.yaml

# Verify Nutanix platform section
grep -A 20 "^platform:" ~/generated_assets/nutanix-sno/install-config.yaml
```

Expected Nutanix platform section:
```yaml
platform:
  nutanix:
    apiVIPs:
    - 192.168.1.100
    ingressVIPs:
    - 192.168.1.100
    prismCentral:
      endpoint:
        address: prism-central.example.com
        port: 9440
      username: admin
      password: changeme
    prismElements:
    - endpoint:
        address: prism-element.example.com
        port: 9440
      uuid: 00000000-0000-0000-0000-000000000000
    subnetUUIDs:
    - subnet-uuid-1234-5678-90ab-cdef
```

### Create Agent ISO

The `create-iso.sh` script generates an Agent-Based Installer ISO that includes:
- Install configuration
- Agent configuration
- Ignition files
- Network configuration

### Boot and Install

1. **Upload ISO**: Upload the generated ISO to Nutanix Image Service
2. **Create VM**: Create a VM in Nutanix with:
   - 8+ vCPUs
   - 32+ GB RAM (64 GB recommended)
   - 120+ GB disk
   - Attach to configured network/VLAN
   - Mount the Agent ISO
3. **Start VM**: Power on the VM
4. **Monitor**: Watch installation progress:

```bash
# From your workstation
export KUBECONFIG=~/generated_assets/nutanix-sno/auth/kubeconfig

# Wait for installation (30-45 minutes for SNO)
./bin/openshift-install agent wait-for install-complete \
  --dir ~/generated_assets/nutanix-sno
```

## Validation

### Verify Cluster

```bash
# Check nodes
oc get nodes

# Check cluster operators
oc get co

# Check cluster version
oc get clusterversion
```

### Access Console

```bash
# Get console URL
oc whoami --show-console

# Get kubeadmin password
cat ~/generated_assets/nutanix-sno/auth/kubeadmin-password
```

## Troubleshooting

### Installation Fails

Check the VM console in Prism Central:
1. Navigate to **VMs**
2. Select the SNO VM
3. Click **Launch Console**
4. Look for errors during boot or installation

### Network Issues

Verify DNS resolution from the node:
```bash
# SSH to the node (during installation)
dig api.nutanix-sno.example.com
dig test.apps.nutanix-sno.example.com
```

### Prism Connection Issues

Test Prism Central connectivity:
```bash
curl -k https://prism-central.example.com:9440/api/nutanix/v3/clusters/list \
  -X POST \
  -H "Content-Type: application/json" \
  -u admin:changeme \
  -d '{}'
```

## Nutanix-Specific Notes

1. **VM Provisioning**: The Agent-Based Installer does NOT create VMs automatically on Nutanix. You must create the VM manually and boot from the generated ISO.

2. **MAC Addresses**: Nutanix AHV assigns MAC addresses when VMs are created. The MAC in `nodes.yml` is for reference only.

3. **Storage**: Nutanix presents virtual disks to VMs. Use `/dev/sda` for `rootDeviceHints` in most cases.

4. **Networking**: Ensure the Nutanix subnet has:
   - Correct VLAN configuration
   - Appropriate IP range
   - Gateway and DNS configured

5. **Updates**: For disconnected environments, see `examples/nutanix-disconnected/` (if available) or adapt from `examples/sno-disconnected/`.

## References

- [OpenShift Documentation - Installing on Nutanix](https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/installing_on_nutanix/)
- [OpenShift Documentation - Agent-Based Installer](https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/installing_an_on-premise_cluster_with_the_agent-based_installer/)
- [Nutanix Documentation](https://portal.nutanix.com/page/documents/details?targetId=AHV-Admin-Guide)

## Sources

- [openshift/hive - Nutanix Configuration Examples](https://github.com/openshift/hive/blob/master/docs/using-hive.md)
- [openshift/installer - Nutanix Platform Support](https://github.com/openshift/installer)
- [OpenShift 4.21 Nutanix Installation Documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/installing_on_nutanix/)
