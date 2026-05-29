---
layout: default
title: "Networking Architecture for KVM Deployments"
parent: Advanced Topics
nav_order: 1
---

# Networking Architecture for KVM Deployments

## Overview

This document describes the networking architecture for OpenShift deployments on KVM/libvirt using VyOS router and Agent-Based Installer.

## Network Topology

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           RHEL Hypervisor                                │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ System Network Manager                                            │   │
│  │ - Primary Connection: vnet48 (or similar)                         │   │
│  │ - DNS: 192.168.122.1 (libvirt) + upstream                        │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                           │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ Libvirt Default Network (192.168.122.0/24)                       │   │
│  │ - Bridge: virbr0                                                 │   │
│  │ - Gateway: 192.168.122.1                                         │   │
│  │ - DHCP Range: 192.168.122.2-254                                  │   │
│  │ - DNS: dnsmasq on 192.168.122.1                                  │   │
│  │   ├── Cluster DNS entries (api.*, *.apps.*)                      │   │
│  │   └── Forwarders: 8.8.8.8, 8.8.4.4                               │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│           │                                                               │
│           ├── VyOS Router (192.168.122.2)                                │
│           │   - External: eth0 (192.168.122.2/24)                        │
│           │   - Internal VLANs: eth1.1924 - eth1.1928                    │
│           │   - NAT: All VLANs → eth0 → Internet                         │
│           │   - Routes: Static routes to VLAN networks                   │
│           │                                                               │
│           └── OpenShift VMs                                               │
│               - Primary: eth0 on default network (no IP)                  │
│               - Bond0: eth1 + eth2 on VLAN networks                      │
│               - DNS: 192.168.122.1 (via routing)                         │
│                                                                           │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ Libvirt VLAN Networks                                            │   │
│  │ - VLAN 1924: 192.168.49.0/24 (192.168.50.0/24 on VyOS)           │   │
│  │ - VLAN 1925: 192.168.51.0/24 (192.168.52.0/24 on VyOS)           │   │
│  │ - VLAN 1926: 192.168.53.0/24 (192.168.54.0/24 on VyOS)           │   │
│  │ - VLAN 1927: 192.168.55.0/24 (192.168.56.0/24 on VyOS)           │   │
│  │ - VLAN 1928: 192.168.57.0/24 (192.168.58.0/24 on VyOS)           │   │
│  │                                                                   │   │
│  │ Note: VLAN 1924 is the standard for OpenShift deployments        │   │
│  │       VyOS maps: eth1.1924 → 192.168.50.0/24 (different CIDR!)   │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘

External Internet
      ↑
      │ (via hypervisor default gateway)
      │
192.168.122.1 (libvirt dnsmasq)
      │
      │ Cluster DNS + External DNS Resolution
      │
192.168.122.2 (VyOS eth0)
      │
      │ NAT Translation
      │
192.168.50.1 (VyOS eth1.1924 - VLAN 1924 gateway)
      │
      │ VLAN Tagged Traffic
      │
OpenShift VMs (bond0.1924)
```

## Standard Configuration (VLAN 1924)

### Cluster Configuration (`cluster.yml`)

```yaml
# DNS Server - CRITICAL
dns_servers:
  - 192.168.122.1  # Libvirt dnsmasq (NOT VyOS gateway!)

# Machine Network
machine_network_cidrs:
  - 192.168.50.0/24  # VLAN 1924 network on VyOS

# VIPs (must be in VLAN 1924 network)
api_vips:
  - 192.168.50.X  # SNO: same as node IP, HA: separate IP

app_vips:
  - 192.168.50.X  # SNO: same as node IP, HA: separate IP

# Rendezvous IP (for SNO, MUST match node IP)
rendezvous_ip: 192.168.50.X
```

### Node Configuration (`nodes.yml`)

**SNO with Bond0 + VLAN:**

```yaml
networkConfig:
  interfaces:
    # Bond interface
    - name: bond0
      type: bond
      state: up
      ipv4:
        dhcp: false
        enabled: true
      link-aggregation:
        mode: 802.3ad  # LACP
        options:
          miimon: '140'
        port:
        - enp1s0
        - enp2s0

    # VLAN on bond
    - name: bond0.1924
      type: vlan
      state: up
      ipv4:
        address:
        - ip: 192.168.50.21  # Node IP
          prefix-length: 24
        dhcp: false
        enabled: true
      vlan:
        base-iface: bond0
        id: 1924

  routes:
    config:
    - destination: 0.0.0.0/0
      next-hop-address: 192.168.50.1  # VyOS gateway
      next-hop-interface: bond0.1924
      table-id: 254

  dns-resolver:
    config:
      server:
        - 192.168.122.1  # Libvirt dnsmasq
```

**SNO with Single Interface + VLAN:**

```yaml
networkConfig:
  interfaces:
    # Base interface
    - name: ens192
      type: ethernet
      state: up
      mac-address: "00:50:56:9a:12:34"

    # VLAN on interface
    - name: ens192.1924
      type: vlan
      state: up
      vlan:
        id: 1924
        base-iface: ens192
      ipv4:
        enabled: true
        address:
          - ip: 192.168.50.50
            prefix-length: 24
        dhcp: false

  routes:
    config:
      - destination: 0.0.0.0/0
        next-hop-address: 192.168.50.1
        next-hop-interface: ens192.1924
        table-id: 254

  dns-resolver:
    config:
      server:
        - 192.168.122.1
```

## DNS Architecture

### Why Use 192.168.122.1 (Libvirt dnsmasq)?

**Correct Approach:**
```
VM (192.168.50.21) 
  → queries 192.168.122.1
  → routing via VyOS (192.168.50.1 → 192.168.122.2)
  → libvirt dnsmasq resolves:
      - Cluster DNS: api.cluster.example.com → 192.168.50.X
      - External DNS: quay.io → forwards to 8.8.8.8
```

**Why NOT use VyOS DNS (192.168.50.1)?**
- VyOS DNS forwarding requires RFC 1123 compliant domain names
- Validation errors during VyOS configuration
- Less tested path for OpenShift deployments
- Libvirt dnsmasq is auto-configured by `deploy-on-kvm.sh`

### DNS Resolution Flow

1. **VM boots** → Uses DNS server from cluster.yml (192.168.122.1)
2. **Cluster DNS query** (api.cluster.example.com)
   - VM → 192.168.122.1 (libvirt dnsmasq)
   - dnsmasq checks local DNS entries (added by virsh net-update)
   - Returns: 192.168.50.X (VIP)
3. **External DNS query** (quay.io)
   - VM → 192.168.122.1 (libvirt dnsmasq)
   - dnsmasq forwards → 8.8.8.8 (Google DNS)
   - Returns: external IP

### DNS Configuration Script

The `deploy-on-kvm.sh` script automatically configures:

1. **DNS Forwarders** (enables external DNS resolution):
```bash
configure_dns_forwarders() {
    # Adds Google DNS as upstream forwarders
    # Without this: VMs can't resolve quay.io, registry.redhat.io
}
```

2. **Cluster DNS Entries** (enables cluster DNS resolution):
```bash
configure_cluster_dns() {
    # Adds DNS entries via virsh net-update
    # api.cluster.example.com → API VIP
    # *.apps.cluster.example.com → App VIP (common routes)
}
```

3. **Host DNS** (enables hypervisor to resolve cluster DNS):
```bash
configure_host_dns() {
    # Updates NetworkManager to use libvirt DNS first
    # Allows: ssh core@api.cluster.example.com
}
```

## VLAN Configuration

### Standard VLAN: 1924

**Why VLAN 1924?**
- Consistent across all KVM examples
- Configured in VyOS router by default
- Maps to 192.168.50.0/24 on VyOS

**VyOS VLAN Mapping:**
```
Libvirt Network   VyOS Interface    VyOS Network      Purpose
─────────────────────────────────────────────────────────────────
1924              eth1.1924         192.168.50.0/24   OpenShift (Standard)
1925              eth1.1925         192.168.52.0/24   Secondary cluster
1926              eth1.1926         192.168.54.0/24   Secondary cluster
1927              eth1.1927         192.168.56.0/24   Secondary cluster
1928              eth1.1928         192.168.58.0/24   Secondary cluster
```

**Note:** The libvirt VLAN network ID (1924) does NOT match the IP range!
- Libvirt network 1924 uses bridge with no IP
- VyOS interface eth1.1924 has IP 192.168.50.1/24
- OpenShift VMs use 192.168.50.x addresses

### Creating Additional VLANs

If you need a new VLAN (e.g., 1929):

1. **Create libvirt network:**
```bash
cat > /tmp/vlan1929.xml <<EOF
<network>
  <name>1929</name>
  <forward mode='bridge'/>
  <bridge name='virbr1929'/>
  <virtualport type='openvswitch'/>
</network>
EOF

sudo virsh net-define /tmp/vlan1929.xml
sudo virsh net-start 1929
sudo virsh net-autostart 1929
```

2. **Configure VyOS:**
```bash
ssh vyos@192.168.122.2
configure
set interfaces ethernet eth1 vif 1929 address 192.168.60.1/24
set nat source rule 15 outbound-interface name eth0
set nat source rule 15 source address 192.168.60.0/24
set nat source rule 15 translation address masquerade
commit
save
```

3. **Add hypervisor route:**
```bash
sudo ip route add 192.168.60.0/24 via 192.168.122.2
```

## Bonding Configuration

### Bond Modes

**802.3ad (LACP) - Recommended for Production:**
```yaml
link-aggregation:
  mode: 802.3ad
  options:
    miimon: '140'  # Link monitoring interval
  port:
  - enp1s0
  - enp2s0
```

**active-backup - Simple Failover:**
```yaml
link-aggregation:
  mode: active-backup
  options:
    miimon: '100'
  port:
  - enp1s0
  - enp2s0
```

**balance-rr - Round Robin (Testing Only):**
```yaml
link-aggregation:
  mode: balance-rr
  options:
    miimon: '100'
  port:
  - enp1s0
  - enp2s0
```

### Bond + VLAN Best Practices

1. **SNO Deployments:**
   - Use bond0 + VLAN for resilience
   - 2 NICs minimum
   - LACP if switch supports it, otherwise active-backup

2. **HA Deployments:**
   - Use bond0 + VLAN on all nodes
   - Consistent bond mode across all nodes
   - Separate VLANs for multi-cluster environments

3. **Testing/Development:**
   - Single interface + VLAN acceptable
   - Faster deployment, less configuration
   - No redundancy

## Routing

### VyOS Router Configuration

**External Interface (eth0):**
- IP: 192.168.122.2/24
- Gateway: 192.168.122.1
- Purpose: Access to internet via hypervisor

**VLAN Interfaces (eth1.19XX):**
- VLAN 1924: 192.168.50.1/24
- VLAN 1925: 192.168.52.1/24
- etc.
- Purpose: Gateway for OpenShift VMs

**NAT Rules:**
- Source NAT for all VLAN networks → eth0
- Allows VMs to access internet for image pulls

### Hypervisor Routes

**Automatic (via VyOS deployment):**
```bash
# Added by hack/vyos-router.sh
192.168.50.0/24 via 192.168.122.2
192.168.52.0/24 via 192.168.122.2
# ... (all VLANs)
```

**Manual (if needed):**
```bash
sudo ip route add 192.168.50.0/24 via 192.168.122.2
```

**Persistent (NetworkManager):**
```bash
nmcli connection modify "System eth0" +ipv4.routes "192.168.50.0/24 192.168.122.2"
nmcli connection up "System eth0"
```

## Troubleshooting

### DNS Not Resolving

**Symptom:** Bootstrap fails with "cannot resolve quay.io"

**Diagnosis:**
```bash
# From hypervisor
dig @192.168.122.1 quay.io          # Should resolve
dig @192.168.122.1 api.cluster.example.com  # Should resolve

# Check DNS forwarders
sudo virsh net-dumpxml default | grep forwarder
```

**Fix:**
```bash
# If missing forwarders, re-run deployment or manually add:
sudo virsh net-dumpxml default > /tmp/net.xml
# Edit /tmp/net.xml to add:
#   <dns forwardPlainNames="yes">
#     <forwarder addr="8.8.8.8"/>
#     <forwarder addr="8.8.4.4"/>
#   </dns>
sudo virsh net-destroy default
sudo virsh net-define /tmp/net.xml
sudo virsh net-start default
```

### VyOS Not Accessible

**Symptom:** Cannot ping 192.168.122.2

**Diagnosis:**
```bash
sudo virsh list | grep vyos  # Should show "running"
ping 192.168.122.2            # Should succeed
```

**Fix:**
```bash
# If VM running but not accessible, check manual configuration
# Access via Cockpit console: https://<hypervisor-ip>:9090
# Verify eth0 has IP: 192.168.122.2/24
```

### VMs Can't Reach Internet

**Symptom:** Image pulls fail, ping to 8.8.8.8 fails

**Diagnosis:**
```bash
# From hypervisor
ssh vyos@192.168.122.2
show nat source rules  # Should show NAT rules for VLANs
ping 8.8.8.8 source-address 192.168.50.1  # Should work
```

**Fix:**
```bash
# Re-apply VyOS configuration
scp ~/vyos-config.sh vyos@192.168.122.2:/tmp/
ssh vyos@192.168.122.2 "sudo vbash /tmp/vyos-config.sh"
```

### VLAN Traffic Not Working

**Symptom:** VMs can't communicate, or no network at all

**Diagnosis:**
```bash
# Check libvirt VLAN network exists
sudo virsh net-list | grep 1924

# Check VyOS VLAN interface
ssh vyos@192.168.122.2 "show interfaces ethernet eth1 vif 1924"
```

**Fix:**
```bash
# Recreate VLAN network if missing
sudo virsh net-define <vlan-xml>
sudo virsh net-start 1924
sudo virsh net-autostart 1924
```

## Reference Templates

### SNO Deployment
**Use:** `examples/sno-bond0-signal-vlan/`
- Bond0 + VLAN 1924
- Single node (control plane + worker)
- DNS: 192.168.122.1
- Network: 192.168.50.0/24
- VIPs: 192.168.50.21 (matches node IP)

### HA Deployment
**Use:** `examples/cnv-bond0-tagged/`
- Bond0 + VLAN 1924
- 3 control plane + 3 workers
- DNS: 192.168.122.1
- Network: 192.168.50.0/24
- VIPs: 192.168.50.252-253

## Best Practices

1. **Always use libvirt dnsmasq (192.168.122.1)** for DNS
   - Auto-configured by deployment scripts
   - Handles cluster + external DNS
   - Tested and validated

2. **Use VLAN 1924 (192.168.50.0/24)** for consistency
   - Standard across all examples
   - VyOS configured by default
   - Simplifies troubleshooting

3. **Prefer bond0 for production** deployments
   - Provides NIC redundancy
   - LACP (802.3ad) for load balancing
   - active-backup for simple failover

4. **Validate before deployment:**
   ```bash
   ./hack/validate-kvm-examples.sh
   ```

5. **Test DNS before OpenShift installation:**
   ```bash
   dig @192.168.122.1 quay.io
   dig @192.168.122.1 api.cluster.example.com
   ```

## Further Reading

- [VyOS Manual Configuration](vyos-manual-configuration.md)
- [DNS Automation (ADR-019)](../DNS_AUTOMATION.md)
- [Agent-Based Installer Guide](https://docs.openshift.com/container-platform/latest/installing/installing_with_agent_based_installer/preparing-to-install-with-agent-based-installer.html)
- [NMState Documentation](https://nmstate.io/)
