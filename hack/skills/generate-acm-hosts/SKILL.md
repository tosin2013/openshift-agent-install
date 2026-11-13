---
name: Generate ACM BareMetalHost Resources
description: Convert nodes.yml BMC credentials into Kubernetes Secret and BareMetalHost manifests for RHACM/Metal3 hub-based cluster deployment
triggers:
  - generate ACM hosts
  - BareMetalHost manifest
  - generate BMC hosts
  - ACM deployment
  - metal3 hosts
  - generate_bmc_acm_hosts
  - RHACM bare metal
  - hub cluster deployment
  - spoke cluster via ACM
---

# Generate ACM BareMetalHost Resources

## When to Use This Skill

Activate when a user wants to:
- Deploy OpenShift clusters managed by a Red Hat Advanced Cluster Management (RHACM) hub
- Generate Metal3 BareMetalHost and Secret resources from an existing `nodes.yml`
- Use the agent-install flow from a hub cluster instead of running `deploy-iso-baremetal.sh` directly
- Run `hack/generate_bmc_acm_hosts.py`

## Scope

This skill generates the BareMetalHost manifests for one spoke cluster. It does **not**:
- Set up the RHACM hub cluster
- Create the InfraEnv or AgentClusterInstall resources
- Deploy the cluster itself (the hub does that after you apply the manifests)

## Prerequisites

- `nodes.yml` with the `bmc` section fully populated for every node
- `python3` with `pyyaml` installed (`pip3 install pyyaml` or `dnf install python3-pyyaml`)
- A running RHACM hub cluster with Metal3 and agent-install operators
- An InfraEnv already created in the hub for this cluster (determines the namespace)
- `oc` CLI configured with the hub cluster's kubeconfig

## Procedure

### Step 1: Confirm nodes.yml Has BMC Credentials

Every node in `nodes.yml` must have this structure:

```yaml
nodes:
  - hostname: master-0
    bmc:
      address: "redfish://192.168.1.100/redfish/v1/Systems/System.Embedded.1"
      username: admin
      password: "s3cur3p@ss"
    interfaces:
      - name: eno1
        mac_address: "aa:bb:cc:dd:ee:01"
    # ... rest of node config
```

BMC address formats:
- Dell iDRAC: `redfish://10.0.0.100/redfish/v1/Systems/System.Embedded.1`
- HPE iLO: `redfish://10.0.0.100/redfish/v1/Systems/1`
- KVM/sushy: `redfish://192.168.122.10:8000/redfish/v1/Systems/<uuid>` (see `setup-sushy-emulator` skill)

### Step 2: Generate the Manifests

```bash
./hack/generate_bmc_acm_hosts.py site-config/<cluster>/nodes.yml output-bmh.yaml
# Example:
./hack/generate_bmc_acm_hosts.py site-config/my-production-cluster/nodes.yml my-cluster-bmh.yaml
```

The output file contains one Kubernetes document per resource, separated by `---`:
- One `Secret` per node: `bmc-<hostname>-credentials` (base64-encoded username/password)
- One `BareMetalHost` per node: `bmh-<hostname>` with the MAC address and BMC reference

Default namespace: `openshift` (matches a typical InfraEnv namespace).

### Step 3: Review and Customize the Output

```bash
cat output-bmh.yaml
```

If your InfraEnv is in a different namespace, update it:
```bash
# Change namespace in the output file
sed -i 's/namespace: openshift/namespace: my-infraenv-namespace/g' output-bmh.yaml
```

Review these fields in each BareMetalHost:
- `automatedCleaningMode: disabled` — prevents Metal3 from wiping disks automatically
- `online: false` — the hub sets this to true when provisioning begins
- `bootMACAddress` — must match the first interface's MAC in nodes.yml

### Step 4: Apply to the Hub Cluster

```bash
export KUBECONFIG=<path-to-hub-kubeconfig>
oc apply -f output-bmh.yaml
```

### Step 5: Monitor Host Discovery

```bash
# Watch BareMetalHost status
oc get bmh -n openshift -w

# Check agent registration (each host should register within 15 min of BMH creation)
oc get agent -n openshift

# Inspect a specific host
oc describe bmh bmh-master-0 -n openshift
```

Expected BareMetalHost state progression:
`registering` → `inspecting` → `available` → `provisioning` (once cluster install starts)

## Validation Criteria

The workflow is successful when:
1. `oc get bmh -n openshift` shows one BareMetalHost per node in `nodes.yml`
2. All BareMetalHosts reach `available` state within 30 minutes
3. `oc get agent -n openshift` shows agents registering (one per host)
4. No Secret shows an error in `oc describe secret bmc-<hostname>-credentials -n openshift`

## Related Skills

- **Before this skill**: `create-cluster-config` must be complete — this skill reads `nodes.yml` from that skill's output
- **Alternative path**: Instead of this skill, `deploy-cluster-baremetal` runs `deploy-iso-baremetal.sh` directly (without RHACM hub orchestration)
- **For KVM testing**: Use `setup-sushy-emulator` to get emulated BMC addresses for the nodes.yml before running this script

## Common Failure Modes

| Symptom | Cause | Fix |
|---------|-------|-----|
| "Missing key 'bmc'" | Node in nodes.yml has no bmc section | Add bmc credentials to every node; KVM VMs need sushy emulator addresses |
| "pyyaml module not found" | python3-pyyaml not installed | `pip3 install pyyaml` or `dnf install python3-pyyaml` |
| BareMetalHost stays in "registering" | Wrong BMC address or unreachable | `curl -k <bmc-address>` from hub; check firewall to BMC network |
| "Secret not found" error in BMH | Namespace mismatch between Secret and BMH | Ensure both resources use the same namespace |
| Agents don't register | InfraEnv missing or in wrong namespace | Verify InfraEnv exists: `oc get infraenv -A` |
| "bootMACAddress conflict" | Duplicate MAC in multi-BMH setup | Verify all MAC addresses are unique across all nodes |

## Key Files

- `hack/generate_bmc_acm_hosts.py` - The generator script (reads nodes.yml, writes multi-doc YAML)
- `site-config/<cluster>/nodes.yml` - Input: must have bmc section for every node
- Metal3 BareMetalHost API: `metal3.io/v1alpha1`
- RHACM agent-install API: `agent-install.openshift.io/v1beta1` (InfraEnv, AgentClusterInstall)
