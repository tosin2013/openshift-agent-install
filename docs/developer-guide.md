# Developer Guide - KVM Development Environment

## Overview

This guide is for developers who want to:
1. **Develop and test** OpenShift deployments on KVM (local development)
2. **Fork and adapt** this repository for their organization's bare metal infrastructure
3. **Understand the full deployment workflow** from development to production

## Development Workflow

```
┌─────────────────────────────────────────────────────────────┐
│                    DEVELOPMENT (KVM)                        │
│  - Test deployment configurations                           │
│  - Validate manifests across versions                       │
│  - Develop automation scripts                               │
│  - Debug networking and DNS                                 │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      │ Fork & Adapt
                      ▼
┌─────────────────────────────────────────────────────────────┐
│              PRODUCTION (Bare Metal)                        │
│  - Deploy to organization infrastructure                    │
│  - Use validated configurations                             │
│  - Apply security policies                                  │
│  - Production-grade networking                              │
└─────────────────────────────────────────────────────────────┘
```

## KVM Development Environment Setup

### Prerequisites

1. **RHEL 9.x host** with KVM/libvirt
2. **Sufficient resources**:
   - RAM: 64GB+ (for HA clusters), 32GB+ (for SNO)
   - Disk: 200GB+ free space
   - CPU: 16+ cores recommended

3. **Required packages**:
   ```bash
   sudo dnf install -y qemu-kvm libvirt virt-install virt-manager \
                       cockpit cockpit-machines
   ```

4. **Enable and start services**:
   ```bash
   # Enable libvirt
   sudo systemctl enable --now libvirtd
   
   # Enable Cockpit for web-based VM management
   sudo systemctl enable --now cockpit.socket
   
   # Configure firewall for Cockpit
   sudo firewall-cmd --add-service=cockpit --permanent
   sudo firewall-cmd --reload
   ```

### Cockpit Web Interface

**Access Cockpit**: `https://<your-host-ip>:9090`

**Cockpit provides**:
- Web-based VM management
- Resource monitoring
- Console access to VMs
- Network configuration UI
- Storage management

**Required for**:
- VyOS router console access during initial setup
- VM monitoring during OpenShift deployment
- Quick troubleshooting without SSH

## Hard Requirement: VyOS Router

**CRITICAL**: VyOS router is a **mandatory prerequisite** for OpenShift deployment on KVM.

### Why VyOS Router is Required

The VyOS router provides:
1. **VLAN networking** (192.168.49.0/24 through 192.168.58.0/24)
2. **DNS services** for cluster domains
3. **Network isolation** between clusters
4. **DHCP services** (optional)
5. **Routing** between KVM networks and host network

All example configurations use VLAN-tagged interfaces that require these networks.

### VyOS Router Setup

#### Step 1: Deploy VyOS Router

```bash
# Set environment variable
export ACTION=create

# Deploy VyOS router (creates networks 1924-1928)
./hack/vyos-router.sh
```

This creates:
- **Libvirt networks**: 1924, 1925, 1926, 1927, 1928
- **VyOS VM**: vyos-router
- **Waits for manual configuration** (up to 30 minutes)

#### Step 2: Manual Configuration via Cockpit

1. **Open Cockpit**: `https://<your-host>:9090`
2. **Navigate to**: Virtual Machines → vyos-router
3. **Open Console**: Click "Console" tab
4. **Follow configuration guide**: https://github.com/tosin2013/demo-virt/blob/rhpds/demo.redhat.com/docs/step1.md

**Configuration steps**:
- Login with default credentials (vyos/vyos)
- Enter configuration mode
- Set up network interfaces
- Configure DNS forwarding
- Set static routes
- Commit and save configuration

#### Step 3: Verify VyOS Router

```bash
# Check router is accessible
ping -c 3 192.168.122.2

# Check VLAN network
ping -c 3 192.168.50.1

# Verify libvirt networks
sudo virsh net-list --all
```

Expected output:
```
Name    State    Autostart   Persistent
------------------------------------------
default active   yes         yes
1924    active   yes         yes
1925    active   yes         yes
1926    active   yes         yes
1927    active   yes         yes
1928    active   yes         yes
```

### VyOS Router Troubleshooting

**Problem**: Router VM created but not accessible

**Solution**:
1. Access console via Cockpit: `https://<host>:9090`
2. Check VyOS boot logs
3. Verify network interfaces are up
4. Reconfigure following step1.md guide

**Problem**: Networks created but no VLAN connectivity

**Solution**:
```bash
# Check routes on host
ip route show | grep 192.168.5

# Re-run VyOS configuration
ACTION=create ./hack/vyos-router.sh
```

**Problem**: Script times out waiting for router

**Solution**:
- VyOS configuration must be completed within 30 minutes
- Use Cockpit console for faster access
- Save VyOS configuration to prevent loss on reboot

## DNS Infrastructure

Two DNS approaches are supported:

### Option 1: dnsmasq (Simpler, Development)

```bash
# Install and configure dnsmasq
sudo ./hack/setup-dnsmasq.sh

# Add DNS entries for cluster
sudo ./hack/configure-dnsmasq-entries.sh add examples/sno-4.20-standard/cluster.yml
```

**Use when**:
- Single cluster development
- Quick testing
- Simplified setup

### Option 2: VyOS Router DNS (Production-like)

VyOS router provides DNS services automatically when configured.

**Use when**:
- Multi-cluster environments
- Production-like networking
- VLAN isolation required

## Complete Development Deployment Workflow

### One-Shot Deployment Script

The `deploy-connected-full.sh` script orchestrates the complete deployment:

```bash
# Full deployment with VyOS router
./hack/deploy-connected-full.sh examples/sno-4.20-standard --with-router

# Deployment phases:
#   Phase 0: VyOS Router Infrastructure (HARD REQUIREMENT)
#   Phase 1: Environment validation
#   Phase 2: ISO generation
#   Phase 3: DNS configuration
#   Phase 4: HAProxy forwarder (optional)
#   Phase 5: VM deployment
#   Phase 6: Installation monitoring
#   Phase 7: Post-deployment validation
```

### Manual Step-by-Step (For Understanding)

```bash
# 1. Ensure VyOS router is running
ping -c 3 192.168.50.1

# 2. Generate cluster ISO
./hack/create-iso.sh sno-4.20-standard

# 3. Configure DNS
sudo ./hack/configure-dnsmasq-entries.sh add examples/sno-4.20-standard/cluster.yml

# 4. Deploy VMs
./hack/deploy-on-kvm.sh examples/sno-4.20-standard/nodes.yml --redfish

# 5. Monitor installation
./bin/openshift-install agent wait-for install-complete \
  --dir ~/generated_assets/sno-4-20/
```

## OpenShift Forwarder (HAProxy)

The OpenShift Forwarder provides external access to clusters via HAProxy.

### Two Deployment Modes

#### Mode 1: Development (example.com)

**Use case**: Local KVM development, testing

```bash
# Configure HAProxy for local access
export EXTERNAL_IP=192.168.1.100  # Your host's IP
./hack/configure-haproxy-forwarder.sh examples/sno-4.20-standard/cluster.yml
```

**Access URLs**:
- API: `https://192.168.1.100:6443`
- HTTP: `http://192.168.1.100:80`
- HTTPS: `https://192.168.1.100:443`

#### Mode 2: Production (AWS/Cloud)

**Use case**: Production clusters, cloud deployments

```bash
# For AWS deployment
export EXTERNAL_IP=<elastic-ip>
export BASE_DOMAIN=mycompany.com
./hack/configure-haproxy-forwarder.sh examples/production-ha/cluster.yml
```

**Access URLs**:
- API: `https://api.cluster-name.mycompany.com:6443`
- HTTP: `http://*.apps.cluster-name.mycompany.com:80`
- HTTPS: `https://*.apps.cluster-name.mycompany.com:443`

### OpenShift Forwarder Configuration

**Repository**: https://github.com/tosin2013/openshift-forwarder

**Configuration Variables**:

```yaml
# vars/vars.yml
haproxy_log_address: "127.0.0.1"
haproxy_chroot_directory: "/var/lib/haproxy"
haproxy_pidfile: "/var/run/haproxy.pid"
haproxy_max_connections: 4000

# Master nodes (from cluster.yml)
masters:
  - ip: "192.168.100.21"
  - ip: "192.168.100.22"
  - ip: "192.168.100.23"

# Worker nodes (from cluster.yml)
workers:
  - ip: "192.168.100.24"
  - ip: "192.168.100.25"
```

**Deployment**:

```bash
# Clone openshift-forwarder
git clone https://github.com/tosin2013/openshift-forwarder.git /opt/openshift-forwarder
sudo ln -s /opt/openshift-forwarder ~/.ansible/roles/

# Run HAProxy setup playbook
ansible-playbook ./playbooks/openshift-forwarder.yml \
  --extra-vars "@vars/vars.yml" \
  -e "ansible_python_interpreter=/usr/bin/python3" -v
```

**Access HAProxy Stats**:
- URL: `http://<haproxy-ip>:1936/haproxy?stats`
- Username: `admin`
- Password: `password`

### AWS-Specific Configuration

For AWS deployments with Elastic IPs and Route53:

1. **Elastic IP**: Assign to HAProxy instance
2. **Security Groups**: 
   - Allow 6443/tcp (API)
   - Allow 80/tcp, 443/tcp (Apps)
   - Allow 22/tcp (SSH)
   - Allow 1936/tcp (HAProxy stats, internal only)

3. **Route53 DNS**:
   ```
   api.cluster-name.mycompany.com → <elastic-ip>
   *.apps.cluster-name.mycompany.com → <elastic-ip>
   ```

4. **Configure HAProxy**:
   ```bash
   export EXTERNAL_IP=<elastic-ip>
   export BASE_DOMAIN=mycompany.com
   ./hack/configure-haproxy-forwarder.sh examples/aws-production/cluster.yml
   ```

## Adapting for Your Organization

### Fork and Customize Workflow

1. **Fork this repository**:
   ```bash
   # Create your organization fork on GitHub
   # Then clone it
   git clone https://github.com/your-org/openshift-agent-install.git
   cd openshift-agent-install
   ```

2. **Create organization-specific examples**:
   ```bash
   # Copy reference example
   cp -r examples/sno-4.20-standard examples/your-org-sno
   
   # Customize for your infrastructure
   vim examples/your-org-sno/cluster.yml
   vim examples/your-org-sno/nodes.yml
   ```

3. **Adjust for bare metal differences**:

   **KVM Development** → **Bare Metal Production** changes:

   | Component | KVM | Bare Metal |
   |-----------|-----|------------|
   | **Networking** | VyOS VLAN networks | Physical switch VLANs |
   | **MAC Addresses** | Generated | Real hardware MACs |
   | **IPMI/BMC** | Redfish mock | Real IPMI/iDRAC/iLO |
   | **DNS** | dnsmasq or VyOS | Corporate DNS server |
   | **Storage** | qcow2 virtual disks | Physical disks (NVMe, SAS) |
   | **Network Speed** | Virtual (unlimited) | Physical (1G, 10G, 25G) |

4. **Update configurations**:

   ```yaml
   # cluster.yml adjustments for bare metal
   platform_type: baremetal  # Change from 'none'
   
   # Use real hardware network
   machine_cidr: 10.0.0.0/24  # Your production network
   
   # Real VIPs on hardware network
   api_vips:
     - 10.0.0.100
   app_vips:
     - 10.0.0.101
   ```

   ```yaml
   # nodes.yml adjustments for bare metal
   nodes:
     - hostname: prod-master-1
       bmc:
         address: ipmi://10.0.1.10  # Real IPMI address
         username: ADMIN
         password: "{{ lookup('env', 'BMC_PASSWORD') }}"
       interfaces:
         - name: eno1  # Real interface name
           mac_address: "AA:BB:CC:DD:EE:01"  # Real MAC
       rootDeviceHints:
         deviceName: /dev/nvme0n1  # Real disk
   ```

5. **Security hardening for production**:
   - Store BMC credentials in Ansible Vault
   - Use corporate PKI for certificates
   - Integrate with corporate DNS/DHCP
   - Apply network security policies
   - Enable audit logging

6. **Maintain your fork**:
   ```bash
   # Add upstream for updates
   git remote add upstream https://github.com/tosin2013/openshift-agent-install.git
   
   # Sync with upstream improvements
   git fetch upstream
   git merge upstream/main
   
   # Keep your customizations in separate branch
   git checkout -b my-org-customizations
   ```

## Development Best Practices

### 1. Version Control Your Configurations

```bash
# Track your examples
git add examples/your-org-*/
git commit -m "Add production configurations"
git push origin main
```

### 2. Test in KVM Before Bare Metal

```bash
# Always validate on KVM first
./hack/deploy-connected-full.sh examples/your-org-sno

# Verify successful deployment
export KUBECONFIG=~/generated_assets/your-cluster/auth/kubeconfig
oc get nodes
oc get co
```

### 3. Use Version Validation

```bash
# Test across OpenShift versions
./hack/generate-version-manifests.sh your-org-sno "4.20 4.21"

# Validate deployment standards
./hack/validate-deployment-standards.sh \
  ~/generated_assets/version-compare/your-org-sno-4.21 4.21
```

### 4. Document Your Customizations

Create `docs/organization-deployment.md`:

```markdown
# YourOrg OpenShift Deployment

## Network Configuration
- VLAN: 100
- Network: 10.0.100.0/24
- Gateway: 10.0.100.1

## Hardware Inventory
| Hostname | Role | IPMI | MAC |
|----------|------|------|-----|
| prod-master-1 | master | 10.0.1.10 | AA:BB:CC:DD:EE:01 |
...

## Deployment Procedure
1. Prepare hardware (BIOS settings, RAID)
2. Configure network switches (VLANs, trunking)
3. Generate manifests
4. Deploy via Redfish/IPMI
```

## Common Development Scenarios

### Scenario 1: Testing Disconnected Deployment

```bash
# 1. Set up local mirror registry (optional)
# 2. Use disconnected example
./hack/deploy-connected-full.sh examples/ha-4.21-disconnected --with-router
```

### Scenario 2: Multi-Cluster Testing

```bash
# Deploy cluster 1
./hack/deploy-connected-full.sh examples/cluster-1 --with-router

# Deploy cluster 2 (VyOS router already running)
./hack/deploy-connected-full.sh examples/cluster-2 --skip-dns
```

### Scenario 3: Version Upgrade Testing

```bash
# Deploy 4.20 cluster
./hack/deploy-connected-full.sh examples/sno-4.20-standard

# Test 4.21 upgrade path
oc adm upgrade --to=4.21.x
```

## Troubleshooting Development Environment

### VyOS Router Issues

**Problem**: Cannot access Cockpit
```bash
# Check Cockpit is running
sudo systemctl status cockpit.socket

# Check firewall
sudo firewall-cmd --list-services | grep cockpit

# Restart Cockpit
sudo systemctl restart cockpit.socket
```

**Problem**: VyOS networks not created
```bash
# Check libvirt networks
sudo virsh net-list --all

# Manually create if needed
ACTION=create ./hack/vyos-router.sh
```

### Resource Constraints

**Problem**: Not enough memory for HA cluster
```bash
# Check available resources
free -h
df -h /var/lib/libvirt/images

# Deploy SNO instead
./hack/deploy-connected-full.sh examples/sno-4.20-standard
```

### Network Connectivity

**Problem**: VMs can't reach internet
```bash
# Check VyOS DNS forwarding
ping -c 3 8.8.8.8

# Check NAT is enabled
sudo iptables -t nat -L -v
```

## Next Steps

1. **Read**: [Installation Guide](installation-guide.md) - Complete deployment walkthrough
2. **Reference**: [Configuration Guide](configuration-guide.md) - All configuration parameters
3. **Understand**: [Network Configuration](network-configuration.md) - Detailed networking guide
4. **Deploy**: Start with `examples/sno-4.20-standard` on KVM
5. **Adapt**: Fork repository and create organization-specific configurations
6. **Validate**: Test on KVM before bare metal deployment

## Related Documentation

- [VyOS Router Setup (External)](https://github.com/tosin2013/demo-virt/blob/rhpds/demo.redhat.com/docs/step1.md)
- [OpenShift Forwarder Repository](https://github.com/tosin2013/openshift-forwarder)
- [Cockpit Documentation](https://cockpit-project.org/documentation.html)
- [Bare Metal Deployment Guide](deployment-patterns.md#bare-metal)
