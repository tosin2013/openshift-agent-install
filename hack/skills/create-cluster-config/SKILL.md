---
name: Create Cluster Configuration
description: Author cluster.yml and nodes.yml for SNO, 3-node compact, or HA OpenShift deployments
triggers:
  - create cluster configuration
  - new cluster config
  - write cluster.yml
  - write nodes.yml
  - configure new cluster
  - add a cluster
  - SNO configuration
  - HA cluster setup
---

# Create Cluster Configuration

## When to Use This Skill

Activate when a user wants to:
- Create a new OpenShift cluster configuration from scratch
- Adapt an existing example for their environment
- Configure networking (VLAN, bond, static IP) for a deployment
- Set up a SNO, 3-node compact, or HA cluster definition

## Prerequisites

- Know the deployment pattern: SNO (1 node), 3-node compact (3 masters, 0 workers), or HA (3 masters + N workers)
- Know the target platform: `none` (SNO only), `baremetal`, `vsphere`, or `nutanix`
- Have node hardware details: MAC addresses, IP addresses, interface names
- Know the network topology: VLAN IDs, bond configuration, gateway, DNS server
- Have a pull secret downloaded from https://console.redhat.com/openshift/downloads

## Procedure

### Step 1: Choose a Base Example

Select the closest match from `examples/`:

| Pattern | Platform | Example |
|---------|----------|---------|
| SNO, simple VLAN | none | `examples/sno-4.20-standard/` |
| SNO, bond+VLAN | none | `examples/sno-bond0-signal-vlan/` |
| SNO, disconnected | none | `examples/sno-disconnected/` |
| 3-node compact | baremetal | `examples/ha-4.21-disconnected/` |
| HA with workers | baremetal | `examples/ha-4.22-standard/` |
| HA, bond+VLAN | baremetal | `examples/cnv-bond0-tagged/` |
| vSphere | vsphere | `examples/vmware-example/` |
| Nutanix | nutanix | `examples/nutanix-ha/` |

### Step 2: Create Configuration Directory

```bash
# For development/testing (tracked in git):
mkdir -p examples/<cluster-name>/

# For real deployments (gitignored):
mkdir -p site-config/<cluster-name>/
```

### Step 3: Author cluster.yml

Required fields for ALL deployments:

```yaml
use_site_configs: false
pull_secret_path: ~/pull-secret.json
base_domain: example.com
cluster_name: my-cluster
ocp_version: "4.22"
platform_type: baremetal    # none (SNO only), baremetal, vsphere, nutanix

api_vips:
  - 192.168.50.5
app_vips:
  - 192.168.50.6

dns_servers:
  - 192.168.122.1

cluster_network_cidr: 10.128.0.0/14
cluster_network_host_prefix: 23
service_network_cidrs:
  - 172.30.0.0/16
machine_network_cidrs:
  - 192.168.50.0/24

network_type: OVNKubernetes
rendezvous_ip: 192.168.50.10
```

**Critical rules:**
- `api_vips` and `app_vips` MUST be within `machine_network_cidrs`
- `rendezvous_ip` MUST be one of the node IPs in nodes.yml
- `network_type` MUST be `OVNKubernetes` for OpenShift 4.21+ (OpenShiftSDN removed)
- For SNO: `platform_type: none` and VIPs equal the single node's IP
- `ocp_version` must be quoted (e.g., `"4.22"`) to prevent YAML float interpretation

**KVM lab conventions** (when deploying to local libvirt):
- `dns_servers: [192.168.122.1]` (libvirt dnsmasq)
- VLAN `1924`, network `192.168.50.0/24`, gateway `192.168.50.1` (VyOS router)

### Step 4: Author nodes.yml

```yaml
control_plane_replicas: 3
app_node_replicas: 2

nodes:
  - hostname: master-0
    role: master
    rootDeviceHints:
      deviceName: /dev/vda       # KVM
      # deviceName: /dev/sda     # bare metal
      # wwn: "0x600..."          # multipath
    interfaces:
      - name: enp1s0
        mac_address: "52:54:00:42:22:10"
    networkConfig:
      interfaces:
        - name: enp1s0
          type: ethernet
          state: up
          mac-address: "52:54:00:42:22:10"
          ipv4:
            enabled: false
        - name: enp1s0.1924
          type: vlan
          state: up
          vlan:
            id: 1924
            base-iface: enp1s0
          ipv4:
            enabled: true
            address:
              - ip: 192.168.50.10
                prefix-length: 24
            dhcp: false
      dns-resolver:
        config:
          server:
            - 192.168.122.1
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: 192.168.50.1
            next-hop-interface: enp1s0.1924
            table-id: 254
```

**Critical rules:**
- `control_plane_replicas + app_node_replicas` MUST equal the number of entries in `nodes[]`
- Every MAC address MUST be unique across all nodes
- Each node IP MUST be unique and within `machine_network_cidrs`
- `rootDeviceHints.deviceName` is `/dev/vda` for KVM, typically `/dev/sda` or `/dev/nvme0n1` for bare metal
- Interface names must match actual hardware (`enp1s0` for KVM, `eno1`/`ens192` for physical)

**Networking patterns:**

Simple VLAN:
```yaml
networkConfig:
  interfaces:
    - name: ens192.1924
      type: vlan
      state: up
      vlan: { id: 1924, base-iface: ens192 }
      ipv4: { enabled: true, address: [{ip: X.X.X.X, prefix-length: 24}], dhcp: false }
```

Bond + VLAN:
```yaml
networkConfig:
  interfaces:
    - name: bond0
      type: bond
      state: up
      link-aggregation:
        mode: 802.3ad        # or active-backup
        port: [eno1, eno2]
      ipv4: { enabled: false }
    - name: bond0.1924
      type: vlan
      state: up
      vlan: { id: 1924, base-iface: bond0 }
      ipv4: { enabled: true, address: [{ip: X.X.X.X, prefix-length: 24}], dhcp: false }
```

**For bare metal with BMC (Redfish):**
```yaml
nodes:
  - hostname: worker-0
    role: worker
    bmc:
      address: "redfish://192.168.1.100/redfish/v1/Systems/1"
      username: admin
      password: password
    # ... rest of config
```

### Step 5: Validate

For KVM deployments:
```bash
./hack/validate-kvm-examples.sh
```

For bare metal deployments:
```bash
./hack/validate-baremetal-env.sh <cluster-config-name>
```

General YAML validation:
```bash
yq eval '.' examples/<name>/cluster.yml > /dev/null
yq eval '.' examples/<name>/nodes.yml > /dev/null
```

NMState syntax validation (if `nmstatectl` available):
```bash
yq eval '.nodes[0].networkConfig' examples/<name>/nodes.yml | nmstatectl gc -
```

## Validation Criteria

The configuration is correct when:
1. Both YAML files parse without errors
2. VIPs are within `machine_network_cidrs`
3. Node count matches replica declarations
4. All MAC addresses are unique
5. `rendezvous_ip` matches one node's IP
6. `network_type: OVNKubernetes` for 4.21+
7. Platform matches topology (`none` only for SNO)
8. `hack/validate-kvm-examples.sh` passes (KVM) or `hack/validate-baremetal-env.sh` passes (bare metal)

## Common Failure Modes

| Symptom | Cause | Fix |
|---------|-------|-----|
| ISO generation fails with template error | Missing required field in cluster.yml | Compare against working example |
| Bootstrap hangs indefinitely | `rendezvous_ip` doesn't match any node | Verify IP appears in a node's networkConfig |
| No API access after install | VIP outside machine network | Ensure api_vips within machine_network_cidrs |
| Nodes not joining cluster | Duplicate MAC addresses | Audit all MACs for uniqueness |
| create-iso.sh rejects config | OpenShiftSDN with 4.21+ | Change network_type to OVNKubernetes |
| DNS resolution fails | Wrong dns_servers value | Use 192.168.122.1 for KVM, corporate DNS for bare metal |
| NMState validation error | Wrong interface name or VLAN syntax | Check `nmstatectl gc` output |

## Key Files

- `examples/` - All reference configurations
- `hack/validate-kvm-examples.sh` - KVM configuration validator
- `hack/validate-baremetal-env.sh` - Bare metal pre-flight validator
- `playbooks/templates/install-config.yml.j2` - How cluster.yml maps to install-config
- `playbooks/templates/agent-config.yml.j2` - How nodes.yml maps to agent-config
- `docs/configuration-guide.md` - Full parameter reference
- `llm.txt` - "Configuration Reference" section
