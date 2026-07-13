---
name: Deploy Cluster on Bare Metal
description: Deliver agent ISO to physical servers via Redfish virtual media or IPMI and monitor installation
triggers:
  - deploy bare metal
  - deploy to physical servers
  - redfish deploy
  - IPMI deploy
  - bare metal installation
  - production deployment
  - deploy-iso-baremetal
---

# Deploy Cluster on Bare Metal

## When to Use This Skill

Activate when a user wants to:
- Deploy OpenShift to physical bare metal servers
- Use Redfish virtual media or IPMI to boot servers from the agent ISO
- Validate a bare metal environment before deployment
- Deliver an ISO to servers with BMC (iDRAC, iLO, IPMI) access

## Prerequisites

- Cluster configuration ready with BMC credentials in nodes.yml
- Agent ISO already generated (`./hack/create-iso.sh`)
- Corporate DNS records configured (api, api-int, *.apps)
- BMC network reachable from deployment host
- `ipmitool` installed (for IPMI method)
- `curl` available (for Redfish method)
- Physical servers have UEFI boot mode enabled (recommended)

## Procedure

### Step 1: Validate the Bare Metal Environment

Run the pre-flight validator BEFORE attempting deployment:

```bash
./hack/validate-baremetal-env.sh <cluster-config-name>
# Example: ./hack/validate-baremetal-env.sh my-production-cluster
```

This checks 8 categories:
1. Required tools installed (yq, dig, curl/ipmitool, nmstatectl)
2. Cluster config files exist and parse correctly
3. Corporate DNS records resolve (api, api-int, *.apps)
4. VIPs are within machine_network_cidr
5. BMC addresses are network-reachable (ping)
6. NMState networkConfig syntax is valid
7. SSH public key is readable
8. Pull secret file exists

**ALL checks must pass before proceeding.**

### Step 2: Verify Corporate DNS

Unlike KVM (which uses libvirt dnsmasq), bare metal requires DNS records in your corporate DNS:

```bash
# Test from deployment host
dig api.<cluster-name>.<base-domain> @<corporate-dns>
dig api-int.<cluster-name>.<base-domain> @<corporate-dns>
dig test.apps.<cluster-name>.<base-domain> @<corporate-dns>
```

All three must resolve to the correct VIPs defined in cluster.yml.

### Step 3: Generate ISO (if not done)

```bash
SITE_CONFIG_DIR=site-config ./hack/create-iso.sh <cluster-name>
```

### Step 4: Deploy ISO to Servers

#### Method A: Redfish Virtual Media (Recommended)

For servers with iDRAC 9+, iLO 5+, or compatible Redfish BMC:

```bash
./hack/deploy-iso-baremetal.sh site-config/<cluster>/nodes.yml \
    --method redfish \
    --iso ~/generated_assets/<cluster-name>/agent.x86_64.iso
```

This will:
1. Start a temporary HTTP server on the deployment host (port 8080)
2. For each node: mount ISO via Redfish virtual media, set boot device, power cycle
3. Nodes boot from the ISO and begin installation

**Firewall requirement:** Port 8080 must be accessible from BMC addresses.

#### Method B: IPMI

For older servers or IPMI-only environments:

```bash
./hack/deploy-iso-baremetal.sh site-config/<cluster>/nodes.yml \
    --method ipmi \
    --iso ~/generated_assets/<cluster-name>/agent.x86_64.iso
```

**Note:** IPMI cannot mount ISOs remotely. The ISO must be pre-staged on each server's virtual media, or physically present. The script sets chassis boot device to cdrom and power-cycles.

#### Method C: Connectivity Check Only

Verify BMC reachability without deploying:

```bash
./hack/deploy-iso-baremetal.sh site-config/<cluster>/nodes.yml --method check
```

### Step 5: Monitor Installation

Bare metal nodes do NOT need the `watch-and-reboot-kvm-vms.sh` script (physical servers handle reboots natively).

```bash
# Wait for bootstrap (15-30 min typical for bare metal)
./bin/openshift-install agent wait-for bootstrap-complete \
    --dir ~/generated_assets/<cluster-name>/

# Wait for full install (30-60 min)
./bin/openshift-install agent wait-for install-complete \
    --dir ~/generated_assets/<cluster-name>/
```

### Step 6: Validate Cluster

```bash
export KUBECONFIG=~/generated_assets/<cluster-name>/auth/kubeconfig
oc get nodes
oc get co
oc get clusterversion
```

## nodes.yml BMC Configuration

For bare metal, nodes.yml needs BMC credentials:

```yaml
nodes:
  - hostname: master-0
    role: master
    bmc:
      address: "redfish://192.168.1.100/redfish/v1/Systems/1"
      username: admin
      password: "s3cur3p@ss"
    rootDeviceHints:
      deviceName: /dev/sda
      # Or for multipath: wwn: "0x6001..."
    interfaces:
      - name: eno1
        mac_address: "aa:bb:cc:dd:ee:01"
    networkConfig:
      # ... NMState config with production interface names
```

BMC address formats:
- Dell iDRAC: `redfish://10.0.0.100/redfish/v1/Systems/System.Embedded.1`
- HPE iLO: `redfish://10.0.0.100/redfish/v1/Systems/1`
- Generic IPMI: `ipmi://10.0.0.100` (for --method ipmi)

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `SITE_CONFIG_DIR` | `examples` | Use `site-config` for production |
| `GENERATED_ASSET_PATH` | `~/generated_assets` | ISO location |
| `HTTP_BIND_IP` | Auto-detected | IP for Redfish HTTP server |
| `DNS_SERVER` | From cluster.yml | DNS server to test against |

## Validation Criteria

Deployment is successful when:
1. `validate-baremetal-env.sh` shows 8/8 PASSED
2. All BMC addresses respond to `--method check`
3. Nodes appear in the agent console within 15 minutes of boot
4. `wait-for bootstrap-complete` exits 0
5. `wait-for install-complete` exits 0
6. `oc get nodes` shows all nodes Ready
7. `oc get co` shows all operators Available

## Common Failure Modes

| Phase | Symptom | Cause | Fix |
|-------|---------|-------|-----|
| Validate | DNS check fails | Corporate DNS records not created | Register api/api-int/*.apps in BIND/Infoblox/AD |
| Validate | BMC ping fails | BMC on different VLAN or firewall | Verify L3 path to BMC management network |
| Validate | NMState error | Wrong interface names | Use `ip link` on target server to find real names |
| Redfish | "Connection refused" on :8080 | Firewall blocking HTTP server | `firewall-cmd --add-port=8080/tcp` |
| Redfish | "Virtual media insert failed" | BMC firmware too old | Update BMC firmware or use IPMI method |
| Boot | Nodes don't appear in console | Wrong boot mode (Legacy vs UEFI) | Set UEFI in BIOS settings |
| Boot | Nodes boot to wrong device | Boot order not set to virtual media | Manually set one-time boot in BMC |
| Install | Nodes can't reach rendezvous IP | Network isolation / VLAN misconfiguration | Verify all nodes on same L2 segment |
| Install | "unable to resolve host" in node logs | Node DNS config wrong | Check networkConfig dns-resolver points to corporate DNS |
| Install | Timeout after 60 min | Resource issue or stuck node | Console into node, check `journalctl -u agent` |

## Key Differences from KVM Deployment

| Aspect | KVM | Bare Metal |
|--------|-----|-----------|
| DNS | libvirt dnsmasq (192.168.122.1) | Corporate DNS (BIND/AD/Infoblox) |
| ISO delivery | `deploy-on-kvm.sh` + libvirt | `deploy-iso-baremetal.sh` via Redfish/IPMI |
| VM reboot | `watch-and-reboot-kvm-vms.sh` required | Not needed (hardware reboots natively) |
| Validation | `validate-kvm-examples.sh` | `validate-baremetal-env.sh` |
| Interface names | `enp1s0`, `enp2s0` | `eno1`, `ens192`, `ens1f0` (hardware-dependent) |
| Root device | `/dev/vda` | `/dev/sda`, `/dev/nvme0n1`, multipath WWN |
| Config location | `examples/` | `site-config/` (gitignored) |

## Key Files

- `hack/deploy-iso-baremetal.sh` - ISO delivery via Redfish/IPMI
- `hack/validate-baremetal-env.sh` - Pre-flight validation (8 checks)
- `docs/bare-metal-production-guide.md` - Production runbook
- `docs/bare-metal-tutorial.md` - Step-by-step tutorial
- `docs/bmc-management.md` - BMC configuration guide
- `docs/fork-and-adapt-checklist.md` - KVM-to-production migration
