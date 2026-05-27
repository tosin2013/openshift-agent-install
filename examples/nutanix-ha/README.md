# Nutanix HA Deployment Example

This example demonstrates deploying a High Availability (HA) OpenShift cluster on Nutanix AHV using the Agent-Based Installer.

## Overview

- **Topology**: HA (3 control plane nodes, 2 worker nodes)
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
   - DNS resolution for `api.<cluster>.<domain>`, `api-int.<cluster>.<domain>`, and `*.apps.<cluster>.<domain>`

### Nutanix Requirements (Per Node)

- **Storage**: Minimum 120 GB per node
- **CPU**: Minimum 8 vCPUs per node
- **Memory**: 
  - Control plane: 32 GB RAM minimum (64 GB recommended)
  - Workers: 32 GB RAM minimum
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
cluster_name: nutanix-ha          # Your cluster name

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

# VIPs - Separate from node IPs for HA
api_vips:
  - 192.168.1.100
app_vips:
  - 192.168.1.101

# HA Configuration: 3 control plane, 2 workers
control_plane_replicas: 3
app_node_replicas: 2

# Network configuration
machine_network_cidrs:
  - 192.168.1.0/24
rendezvous_ip: 192.168.1.110  # First control plane node

# DNS servers
dns_servers:
  - 192.168.1.1
```

### Step 2: Update nodes.yml

Edit `nodes.yml` and configure the 5-node cluster network:

```yaml
nodes:
  # Control Plane Nodes
  - hostname: nutanix-ha-master-0
    role: master
    interfaces:
      - name: enp1s0
        mac-address: "52:54:00:00:01:01"  # Nutanix will assign actual MAC
        ipv4:
          address:
            - ip: 192.168.1.110
              prefix-length: 24
    routes:
      config:
        - destination: 0.0.0.0/0
          next-hop-address: 192.168.1.1

  - hostname: nutanix-ha-master-1
    role: master
    interfaces:
      - name: enp1s0
        mac-address: "52:54:00:00:01:02"
        ipv4:
          address:
            - ip: 192.168.1.111
              prefix-length: 24
    routes:
      config:
        - destination: 0.0.0.0/0
          next-hop-address: 192.168.1.1

  - hostname: nutanix-ha-master-2
    role: master
    interfaces:
      - name: enp1s0
        mac-address: "52:54:00:00:01:03"
        ipv4:
          address:
            - ip: 192.168.1.112
              prefix-length: 24
    routes:
      config:
        - destination: 0.0.0.0/0
          next-hop-address: 192.168.1.1

  # Worker Nodes
  - hostname: nutanix-ha-worker-0
    role: worker
    interfaces:
      - name: enp1s0
        mac-address: "52:54:00:00:02:01"
        ipv4:
          address:
            - ip: 192.168.1.120
              prefix-length: 24
    routes:
      config:
        - destination: 0.0.0.0/0
          next-hop-address: 192.168.1.1

  - hostname: nutanix-ha-worker-1
    role: worker
    interfaces:
      - name: enp1s0
        mac-address: "52:54:00:00:02:02"
        ipv4:
          address:
            - ip: 192.168.1.121
              prefix-length: 24
    routes:
      config:
        - destination: 0.0.0.0/0
          next-hop-address: 192.168.1.1
```

### Step 3: DNS Configuration

Create DNS records for:

```
api.nutanix-ha.example.com       A    192.168.1.100
api-int.nutanix-ha.example.com   A    192.168.1.100
*.apps.nutanix-ha.example.com    A    192.168.1.101
```

**Critical**: For HA clusters, you MUST configure both `api` and `api-int` DNS records. The VIPs must be separate from node IPs.

## Deployment

### Generate Installation Manifests

```bash
cd /path/to/openshift-agent-install

# Generate manifests
./hack/create-iso.sh nutanix-ha
```

### Review Generated Manifests

```bash
# Check install-config.yaml
cat ~/generated_assets/nutanix-ha/install-config.yaml

# Verify Nutanix platform section
grep -A 30 "^platform:" ~/generated_assets/nutanix-ha/install-config.yaml
```

Expected Nutanix platform section:
```yaml
platform:
  nutanix:
    apiVIPs:
    - 192.168.1.100
    ingressVIPs:
    - 192.168.1.101
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

### Create VMs in Nutanix

**IMPORTANT**: The Agent-Based Installer does NOT create VMs automatically on Nutanix. You must manually create 5 VMs:

1. **Create 3 Control Plane VMs**:
   - Name: nutanix-ha-master-0, nutanix-ha-master-1, nutanix-ha-master-2
   - CPU: 8+ vCPUs
   - RAM: 32+ GB (64 GB recommended)
   - Disk: 120+ GB
   - Network: Attach to configured VLAN/subnet

2. **Create 2 Worker VMs**:
   - Name: nutanix-ha-worker-0, nutanix-ha-worker-1
   - CPU: 8+ vCPUs
   - RAM: 32+ GB
   - Disk: 120+ GB
   - Network: Attach to configured VLAN/subnet

3. **Note MAC Addresses**: After VM creation, update `nodes.yml` with actual MAC addresses assigned by Nutanix

4. **Upload Agent ISO**: Upload the generated ISO to Nutanix Image Service

5. **Attach ISO**: Mount the Agent ISO to all 5 VMs

### Boot and Install

1. **Power on all 5 VMs simultaneously**
2. **Monitor installation progress**:

```bash
# From your workstation
export KUBECONFIG=~/generated_assets/nutanix-ha/auth/kubeconfig

# Wait for installation (60-90 minutes for HA)
./bin/openshift-install agent wait-for install-complete \
  --dir ~/generated_assets/nutanix-ha
```

Installation phases:
- **Bootstrap (0-15 min)**: First control plane node becomes bootstrap
- **Control Plane (15-45 min)**: All 3 control planes join cluster
- **Worker Join (45-60 min)**: 2 workers join cluster
- **Operators (60-90 min)**: Cluster operators reach Available state

## Validation

### Verify Cluster

```bash
# Check all nodes are Ready
oc get nodes
# Expected: 5 nodes (3 masters, 2 workers) in Ready state

# Check cluster operators
oc get co
# Expected: All operators Available=True, Degraded=False

# Check cluster version
oc get clusterversion
# Expected: Version 4.21.x, Available=True
```

### Verify High Availability

```bash
# Check etcd members (should show 3)
oc get pods -n openshift-etcd | grep etcd-nutanix-ha-master

# Check API server pods (should show 3)
oc get pods -n openshift-apiserver | grep apiserver

# Verify VIP assignment
# API VIP should be assigned to one of the control plane nodes
oc get pods -n openshift-kube-apiserver -o wide
```

### Access Console

```bash
# Get console URL
oc whoami --show-console

# Get kubeadmin password
cat ~/generated_assets/nutanix-ha/auth/kubeadmin-password
```

## Troubleshooting

### Installation Fails

Check VM consoles in Prism Central:
1. Navigate to **VMs**
2. Select each VM
3. Click **Launch Console**
4. Look for errors during boot or installation

### Network Issues

Verify DNS resolution from nodes:
```bash
# SSH to a node (during installation)
dig api.nutanix-ha.example.com
dig api-int.nutanix-ha.example.com
dig test.apps.nutanix-ha.example.com

# All should resolve to correct VIPs
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

### VIP Assignment Issues

For HA clusters, VIPs are managed by keepalived:
```bash
# Check keepalived pods
oc get pods -n openshift-kube-apiserver | grep keepalived

# Check VIP assignment
oc logs -n openshift-kube-apiserver <keepalived-pod>
```

### Worker Nodes Not Joining

If workers don't join automatically:
```bash
# Check pending CSRs (Certificate Signing Requests)
oc get csr

# Approve pending CSRs for workers
oc get csr -o name | xargs oc adm certificate approve
```

## HA-Specific Notes

### Load Balancing

- **API Load Balancing**: Nutanix platform manages API VIP automatically via keepalived
- **Ingress Load Balancing**: Nutanix platform manages Ingress VIP automatically
- **No external load balancer required** for Nutanix platform deployments

### Resilience

- **Control Plane**: Cluster survives loss of 1 control plane node (quorum requires 2/3)
- **Workers**: Workloads distributed across 2+ workers for redundancy
- **Etcd**: 3-member etcd cluster provides HA for cluster state

### Scaling

To add more workers after installation:
1. Create additional VMs in Nutanix
2. Boot from Agent ISO or use machine API
3. Approve CSRs for new nodes

### Production Recommendations

1. **Network Bonding**: Use bonded interfaces for network redundancy (see `examples/cnv-bond0-tagged/`)
2. **Storage**: Configure Nutanix Storage Containers with appropriate replication factor
3. **Monitoring**: Deploy OpenShift monitoring stack and configure alerting
4. **Backups**: Configure etcd backups and disaster recovery procedures
5. **Updates**: Plan for regular OpenShift updates and Nutanix AOS updates

## Nutanix-Specific Notes

1. **VM Provisioning**: The Agent-Based Installer does NOT create VMs automatically on Nutanix. You must create all 5 VMs manually.

2. **MAC Addresses**: Nutanix AHV assigns MAC addresses when VMs are created. Update `nodes.yml` with actual MACs after VM creation.

3. **Storage**: Nutanix presents virtual disks to VMs. Use `/dev/sda` for `rootDeviceHints` in most cases.

4. **Networking**: Ensure the Nutanix subnet has:
   - Correct VLAN configuration
   - Appropriate IP range (at least 7 IPs: 3 masters + 2 workers + 2 VIPs)
   - Gateway and DNS configured

5. **VIP Management**: Nutanix platform deployments use keepalived for VIP management. No external load balancer is required.

6. **Updates**: For disconnected environments, see `examples/nutanix-disconnected/` (if available) or adapt from `examples/ha-4.21-disconnected/`.

## References

- [OpenShift Documentation - Installing on Nutanix](https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/installing_on_nutanix/)
- [OpenShift Documentation - Agent-Based Installer](https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/installing_an_on-premise_cluster_with_the_agent-based_installer/)
- [Nutanix Documentation](https://portal.nutanix.com/page/documents/details?targetId=AHV-Admin-Guide)
- [OpenShift HA Architecture](https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/architecture/)

## Sources

- [openshift/hive - Nutanix Configuration Examples](https://github.com/openshift/hive/blob/master/docs/using-hive.md)
- [openshift/installer - Nutanix Platform Support](https://github.com/openshift/installer)
- [OpenShift 4.21 Nutanix Installation Documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/installing_on_nutanix/)
