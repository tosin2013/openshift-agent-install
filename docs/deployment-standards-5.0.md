---
layout: default
title: "Deployment Standards: OpenShift 5.0"
parent: Reference
nav_order: 8
---

# OpenShift 5.0 Deployment Pattern Standards

Released October 2026. First major version boundary since OpenShift 4.0. Uses RHCOS 10 (RHEL 10 based) as the default OS with crun as the container runtime. Upgrade from 4.22 follows the standard in-place update path.

**Hardware requirement**: x86-64-v3 or newer CPU (Cascadelake, Ice Lake, Zen 3+). Older CPUs (pre-Haswell, pre-Zen 3) are not supported by RHCOS 10. Use `os_image_stream: rhel-9` to pin RHCOS 9 if hardware does not qualify.

## Deployment Types Supported
1. **Connected Standard** (default: internet-connected, public registries)
2. **Disconnected/Air-Gapped** (mirror registry, no internet)
3. **Proxy** (corporate proxy, restricted internet)
4. **SNO (Single Node OpenShift)** (single-node compact)
5. **3-Node Compact** (3 masters, no dedicated workers)
6. **HA (High Availability)** (3+ masters, 2+ workers)
7. **OpenShift Virtualization / CNV** (HA with ODF storage workers)

---

## CONNECTED STANDARD Deployment Standards

### Image Registry Configuration
- **NO** `imageDigestSources` or `imageContentSources` (uses public registries)
- **NO** `image-mirror-config.yaml` needed
- **MUST** have valid pull secret for registry.redhat.io

### Network Configuration
- **MANDATORY**: `networkType: OVNKubernetes` (OpenShiftSDN removed since 4.21, not present in 5.x)
- **MUST NOT** specify `OpenShiftSDN` (not available)

### Platform Configuration
- **SUPPORTED**: baremetal, vsphere, none, nutanix, external
- **MUST** set `platform_type` in cluster.yml
- `platform_type: none` valid for SNO only

### CLI Download
- **MUST** use the `openshift-v5` mirror (not `openshift-v4`):
  ```bash
  ./download-openshift-cli.sh 5.0
  # Downloads from: mirror.openshift.com/pub/openshift-v5/x86_64/clients/ocp/stable-5.0
  ```
- **DO NOT** mix 4.x `openshift-install` binary with 5.0 cluster config — `create-iso.sh` will error

---

## DISCONNECTED/AIR-GAPPED Deployment Standards

### Image Registry Configuration
- **MUST** use `ImageDigestMirrorSet` (IDMS) — same as 4.20+
- **MUST NOT** use deprecated `ImageContentSourcePolicy` (ICSP)
- Mirror images from the **openshift-v5 release image** (different base path from 4.x)

### Mirror Registry Requirements
- **MUST** mirror all release images from `quay.io/openshift-release-dev/ocp-release:5.0.*`
- **MUST** include operator catalog images if using OLM operators
- **RECOMMENDED**: Use `oc-mirror` v2 for registry mirroring

### Network Configuration
- **MANDATORY**: `networkType: OVNKubernetes`
- **MUST** configure proxy settings if partial connectivity exists
- **MUST** include mirror registry CA in `additionalTrustBundle`

---

## Key Changes from 4.22

| Area | Change | Impact |
|------|--------|--------|
| RHCOS | RHCOS 10 (RHEL 10 based) is default | x86-64-v3 CPU required; use `os_image_stream: rhel-9` to pin RHCOS 9 |
| Container runtime | crun replaces runc | runc deprecated in 5.0, removed in 5.3; workloads requiring runc must migrate |
| CLI mirror | `openshift-v5` mirror path | `download-openshift-cli.sh 5.0` handles this automatically |
| Major version | 4.x → 5.x boundary | Upgrade from 4.22 via standard in-place update; not a re-install |
| `os_image_stream` | New cluster.yml field | Pin to `rhel-9` for RHCOS 9 during transition; `rhel-10` is the default |
| RHEL 10 host | Host OS support expanded | RHEL 10 host supported for KVM deployment (RHEL 9.x still recommended) |

---

## Agent-Based Installer Specifics (5.0)

### Validated Configuration (2026-11-19)

Validated on IBM Cloud KVM host (RHEL 10, 48 CPUs Intel Cascadelake, 377GB RAM):
- Topology: CNV HA — 3 control plane + 6 workers (workers 0-2 with ODF disks)
- Network: bond0 (802.3ad) + VLAN 1924 (192.168.50.0/24) via VyOS router
- Example: `examples/cnv-5.0-single-bond0-vlan/`

### cluster.yml Requirements
```yaml
ocp_version: "5.0"               # quoted string — required
network_type: OVNKubernetes       # mandatory for all OCP 5.x
platform_type: baremetal          # or vsphere/none/nutanix (none = SNO only)

# Optional: pin OS image stream (default is rhel-10 for OCP 5.x)
# os_image_stream: rhel-9         # uncomment to stay on RHCOS 9 during transition
```

### Known Working Versions
- openshift-install 5.0.1
- oc CLI 5.0.x
- RHCOS 10 (RHEL 10 based, x86-64-v3)
- Host OS: RHEL 10.0 (experimental), RHEL 9.x (recommended)

### KVM Deployment Notes

For KVM deployments with VyOS VLAN routing, run the VyOS smoke test before deploying:
```bash
# All three must pass before running deploy-on-kvm.sh
ping -c 3 192.168.50.1                              # VLAN gateway up
dig @192.168.50.1 quay.io +short +timeout=5         # DNS forwarding working
sshpass -p 'vyos' ssh vyos@192.168.122.2 "/bin/ping -c 3 8.8.8.8"  # NAT to internet
```

The `vyos-router.sh` script now runs this smoke test automatically and blocks deployment if any check fails.

---

## Validation Checklist

Before deploying OCP 5.0:

- [ ] `ocp_version: "5.0"` set in cluster.yml (quoted string)
- [ ] `network_type: OVNKubernetes` (mandatory)
- [ ] openshift-install binary is 5.0.x (`./bin/openshift-install version`)
- [ ] Host CPU meets x86-64-v3 requirement (`lscpu | grep "Model name"`)
- [ ] Pull secret valid for registry.redhat.io
- [ ] Platform type set correctly (baremetal/vsphere/none/nutanix)
- [ ] For disconnected: IDMS configured (not ICSP), images mirrored from openshift-v5
- [ ] DNS entries configured for api.* and *.apps.*
- [ ] NTP servers configured
- [ ] **KVM only**: VyOS smoke test passes (internet, DNS via 192.168.50.1, NAT)
- [ ] **IBM Cloud**: Host DNS includes `127.0.0.1` so `wait-for` resolves cluster API

---

## Forward Look: OpenShift 5.1

OpenShift 5.1 continues the RHCOS 10 lineage. `os_image_stream: rhel-9` (RHCOS 9 pinning) is deprecated in 5.0 and expected to be removed in 5.3.

This repository will add `v5.1` support once GA is released.

---

## References

- [OCP 5.0 Release Notes](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/release_notes/)
- [RHCOS 10 Requirements](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/installation_overview/)
- [openshift-v5 Mirror](https://mirror.openshift.com/pub/openshift-v5/x86_64/clients/ocp/)
- [Upgrade from 4.22 to 5.0](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/updating_clusters/)
- [crun Migration Guide](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/)
