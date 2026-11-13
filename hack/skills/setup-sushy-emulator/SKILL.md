---
name: Setup Sushy Emulator
description: Configure sushy-emulator as a Redfish BMC emulator for KVM VMs, enabling bare-metal-style ISO delivery workflows on a KVM lab host
triggers:
  - sushy emulator
  - setup sushy
  - redfish emulator
  - virtual BMC
  - sushy-emulator
  - configure BMC emulation
  - test libvirt ssh
  - redfish for KVM
  - BMC testing
  - virtual redfish
---

# Setup Sushy Emulator

## When to Use This Skill

Activate when a user wants to:
- Test `deploy-iso-baremetal.sh` with Redfish against KVM VMs (instead of real hardware)
- Validate the bare metal deployment workflow without physical servers
- Set up a fully automated lab that simulates production BMC behavior
- Run `hack/configure-sushy-unix.sh` or `hack/test-libvirt-ssh.sh`

## IMPORTANT

Sushy-emulator exposes KVM VMs as Redfish Systems. This lets you use the **bare metal
deployment path** (`deploy-iso-baremetal.sh --method redfish`) against virtual machines.
It does NOT replace a real BMC for production — it is a development and testing tool.

## Prerequisites

- KVM/libvirt running and accessible (`sudo virsh list --all` works)
- `virbr0` network bridge active (`ip addr show virbr0` shows UP)
- podman installed (`dnf install -y podman`)
- Port 8000 available on the host
- sudo access
- At least one KVM VM defined (even if stopped) to verify the Systems endpoint

## Procedure

### Step 1: Determine the Best Libvirt Connection Method

```bash
./hack/test-libvirt-ssh.sh
```

This tests three libvirt connection methods:
- `qemu:///system` — basic virsh access
- `qemu+unix:///system` — unix socket (preferred for containers)
- `qemu+ssh://lab-user@localhost/system` — SSH method (fallback)

Note which method succeeds. The unix socket method (`qemu+unix:///system`) is what
`configure-sushy-unix.sh` uses by default.

### Step 2: Create the Network Interface and Configure the Emulator

```bash
sudo ./hack/configure-sushy-unix.sh
```

This script performs six actions:
1. Creates `sushy-bmc` macvlan interface on `virbr0` at `192.168.122.10/24`
2. Adds firewall rules: port 8000/tcp in the libvirt zone and trusted zone
3. Writes `/etc/sushy/sushy-emulator.conf` with the unix socket URI
4. Removes any existing sushy-emulator container
5. Creates a new podman container (`quay.io/metal3-io/sushy-tools`) with:
   - `--network=host` and `--privileged`
   - `/etc/sushy` and `/var/run/libvirt` mounted
6. Generates a systemd unit with `podman generate systemd` and enables it

The script then waits up to 30 seconds for the endpoint to respond before confirming success.

### Step 3: Verify the Redfish API

```bash
# Check the endpoint is live
curl -s http://192.168.122.10:8000/redfish/v1/ | python3 -m json.tool

# List all KVM VMs as Redfish Systems
curl -s http://192.168.122.10:8000/redfish/v1/Systems | python3 -m json.tool
```

Each KVM VM appears as a System with a UUID-based URI. Record these UUIDs — you need
them for the BMC address in `nodes.yml`.

### Step 4: Configure nodes.yml to Use the Emulated BMC

For each VM you want to treat as a "physical server":

```bash
# Find the UUID for a specific VM
VM_NAME="master-0"
sudo virsh domuuid $VM_NAME
```

Then in `nodes.yml`:
```yaml
nodes:
  - hostname: master-0
    bmc:
      address: "redfish://192.168.122.10:8000/redfish/v1/Systems/<uuid>"
      username: admin
      password: admin
    # ... rest of node config
```

### Step 5: Test Redfish Connectivity

```bash
# Verify each BMC address works (use the check method)
./hack/deploy-iso-baremetal.sh site-config/<cluster>/nodes.yml --method check
```

If all nodes respond, you are ready to run `deploy-cluster-baremetal` against the
emulated BMC endpoints.

## Environment Variables

The sushy-emulator configuration is entirely in `/etc/sushy/sushy-emulator.conf`.
Key settings written by the script:

| Setting | Value | Purpose |
|---------|-------|---------|
| `SUSHY_EMULATOR_LISTEN_IP` | `192.168.122.10` | IP of the sushy-bmc interface |
| `SUSHY_EMULATOR_LISTEN_PORT` | `8000` | Redfish API port |
| `SUSHY_EMULATOR_LIBVIRT_URI` | `qemu+unix:///system` | How sushy talks to libvirt |
| `SUSHY_EMULATOR_IGNORE_BOOT_DEVICE` | `True` | Do not enforce boot device ordering |

## Validation Criteria

The emulator is fully operational when:
1. `sudo systemctl status sushy-emulator` shows active/running
2. `curl -sf http://192.168.122.10:8000/redfish/v1/Systems` returns HTTP 200
3. Each KVM VM appears in the Systems response as a separate `@odata.id` entry
4. `deploy-iso-baremetal.sh --method check` succeeds for all nodes in nodes.yml
5. `sudo podman logs sushy-emulator` shows no ERROR lines

## Related Skills

- **Before this skill**: KVM host must be bootstrapped (`bootstrap-environment` complete, `validate_env.sh` passing)
- **After this skill**: Use `deploy-cluster-baremetal` with `--method redfish` and the emulated BMC addresses
- **For actual VMs**: VMs listed in the Systems endpoint must be defined in libvirt before this step produces useful output

## Common Failure Modes

| Phase | Symptom | Cause | Fix |
|-------|---------|-------|-----|
| Interface | "Cannot find device virbr0" | virbr0 not active | `sudo virsh net-start default`; then re-run |
| Interface | "macvlan: device already exists" | sushy-bmc already created | Script handles this; check `ip addr show sushy-bmc` |
| Container | "socket permission denied" | Libvirt socket not accessible | Ensure `--privileged` and `-v /var/run/libvirt:/var/run/libvirt:Z` in podman command |
| Container | Image pull fails | quay.io unreachable | Pre-pull: `sudo podman pull quay.io/metal3-io/sushy-tools` on a connected machine |
| API | "Connection refused" on port 8000 | Firewall blocking | `sudo firewall-cmd --add-port=8000/tcp --permanent && sudo firewall-cmd --reload` |
| API | Returns empty Systems list | Wrong LIBVIRT_URI in config | Edit `/etc/sushy/sushy-emulator.conf`; set `SUSHY_EMULATOR_LIBVIRT_URI` per test-libvirt-ssh.sh output |
| Systemd | Service immediately exits | Container startup error | `sudo podman logs sushy-emulator`; check config file syntax |
| Timeout | "Timeout waiting for sushy-emulator" | Container slow to start | `sudo systemctl status sushy-emulator`; check logs |

## Key Files

- `hack/configure-sushy-unix.sh` - Main setup script (interface, container, systemd)
- `hack/test-libvirt-ssh.sh` - Tests libvirt connection methods for container use
- `/etc/sushy/sushy-emulator.conf` - Runtime configuration written by the setup script
- `hack/deploy-iso-baremetal.sh` - The script you use after sushy is running (--method redfish)
