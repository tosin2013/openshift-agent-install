# HA 4.22 Standard - VLAN-Based 6-Node Cluster

High-Availability OpenShift 4.22 cluster on KVM with VLAN networking (802.1Q tagged).

## Topology

| Role | Count | vCPU | RAM | Disk |
|------|-------|------|-----|------|
| Control Plane | 3 | 8 | 32 GB | 130 GB |
| Worker | 3 | 8 | 32 GB | 130 GB |

## Networking

- **VLAN 1924** on `enp1s0` (192.168.50.0/24)
- **Gateway**: 192.168.50.1 (VyOS router)
- **DNS**: 192.168.122.1 (host dnsmasq via libvirt default network)
- **API VIP**: 192.168.50.5
- **Apps VIP**: 192.168.50.6

## Requirements

- VyOS router deployed with VLAN 1924 network active (`virsh net-list` shows 1924)
- dnsmasq running on host
- ~2 TB storage recommended for VM disks (thin-provisioned)
- 192 GB RAM minimum (6 x 32 GB)

## Deployment

```bash
# One-shot deployment with VyOS router networking
./hack/deploy-connected-full.sh examples/ha-4.22-standard --with-router

# Or with external access (HAProxy + Route53 + Let's Encrypt)
export EXTERNAL_IP="<your-public-ip>"
./hack/deploy-ha-full.sh examples/ha-4.22-standard
```

## Cleanup

```bash
./hack/destroy-on-kvm.sh examples/ha-4.22-standard/nodes.yml
```
