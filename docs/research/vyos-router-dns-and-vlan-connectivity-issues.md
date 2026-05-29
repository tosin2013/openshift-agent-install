# VyOS Router DNS and VLAN Connectivity Issues

**Date**: 2026-05-29
**Category**: infrastructure
**Status**: In Progress
**Priority**: Critical - Blocking OpenShift deployment

## Research Questions

### Primary Question
**How should DNS resolution be configured for OpenShift VMs deployed on KVM with VyOS router and VLAN networking?**

### Sub-Questions

1. **VyOS VLAN Interface Accessibility**
   - Why is VyOS VLAN 1924 interface (192.168.50.1) not accessible from the hypervisor?
   - Are VyOS VLAN interfaces (eth1.1924, eth1.1925, etc.) properly configured and active?
   - What routing is required for hypervisor to reach VyOS VLAN networks?

2. **DNS Server Selection**
   - Should OpenShift VMs use libvirt dnsmasq (192.168.122.1) or VyOS gateway (192.168.50.1) for DNS?
   - What are the trade-offs between each DNS server option?
   - How does VLAN isolation affect DNS server accessibility?

3. **DNS Forwarder Configuration**
   - Are DNS forwarders required on both libvirt dnsmasq AND VyOS?
   - How do DNS queries flow from VM → DNS server → upstream resolvers → internet?
   - What happens when a VM on VLAN 1924 queries libvirt dnsmasq on 192.168.122.0/24 network?

4. **Network Routing Architecture**
   - How should routing be configured between:
     - Hypervisor ↔ VyOS management (192.168.122.2)
     - Hypervisor ↔ VyOS VLANs (192.168.50.0/24, etc.)
     - VMs on VLANs ↔ VyOS gateway
     - VMs ↔ libvirt dnsmasq
   - Does VyOS need NAT rules for VLAN networks?
   - Do static routes on hypervisor need to be persistent?

5. **Configuration Standardization**
   - What DNS configuration should be standardized across 15+ example cluster.yml files?
   - Should examples use different DNS based on VLAN or all use the same approach?
   - How should documentation reflect the correct DNS architecture?

## Background

### Current Problem
OpenShift SNO deployment on KVM failing due to DNS resolution issues after migrating from incorrect VLAN 100 (non-existent) to VLAN 1924 (configured in VyOS).

### Context
- **Environment**: RHEL 10 hypervisor with KVM/libvirt
- **OpenShift**: 4.20 SNO deployment using Agent-Based Installer
- **Networking**: VyOS router with VLANs 1924-1928 configured
- **DNS Architecture**: 
  - System dnsmasq: 127.0.0.1 (host DNS)
  - Libvirt dnsmasq: 192.168.122.1 (VM DNS, auto-configured by deploy-on-kvm.sh)
  - VyOS gateway: 192.168.50.1 (VLAN 1924 gateway, should provide DNS forwarding)

### Previous Fixes
1. ✅ **DNS forwarders added** - Libvirt dnsmasq now has upstream forwarders (8.8.8.8, 8.8.4.4)
2. ✅ **VLAN corrected** - Changed from non-existent VLAN 100 to VLAN 1924
3. ❌ **VyOS gateway inaccessible** - Cannot ping 192.168.50.1, blocking deployment

### Evidence
```bash
# VyOS reachable on management network
$ ping 192.168.122.2
✓ WORKING

# VyOS VLAN 1924 gateway NOT reachable
$ ping 192.168.50.1
✗ FAILED - Destination Host Unreachable

# Static route added but didn't help
$ sudo ip route add 192.168.50.0/24 via 192.168.122.2
# Still cannot reach 192.168.50.1

# SSH to VyOS times out when checking interfaces
$ sshpass -p 'vyos' ssh vyos@192.168.122.2 "show interfaces"
# No output (timeout or command issue)
```

## Methodology

### Phase 1: VyOS Configuration Verification
- [ ] SSH into VyOS and verify interface status: `show interfaces`
- [ ] Check VLAN 1924 configuration: `show interfaces ethernet eth1.1924`
- [ ] Verify IP address on eth1.1924: should be 192.168.50.1/24
- [ ] Check if interface is UP: `show interfaces ethernet eth1 vif 1924`
- [ ] Verify VyOS routing table: `show ip route`
- [ ] Test connectivity from VyOS to hypervisor: `ping 192.168.122.1`

### Phase 2: VyOS Configuration Script Analysis
- [ ] Review ~/vyos-config.sh to understand what SHOULD be configured
- [ ] Determine if script was fully applied (check NAT rules, interfaces, DNS)
- [ ] Identify any VyOS command syntax issues or errors during application
- [ ] Re-run vyos-config.sh if needed with verbose output

### Phase 3: Network Routing Investigation
- [ ] Map all network paths: hypervisor ↔ VyOS ↔ VMs
- [ ] Test routing from VyOS perspective (reverse path)
- [ ] Check if VyOS needs bridge or NAT for VLAN access from hypervisor
- [ ] Verify libvirt network XML includes proper routing
- [ ] Test if VMs on VLAN can reach different networks

### Phase 4: DNS Architecture Decision
- [ ] Test DNS resolution from VM using libvirt dnsmasq (192.168.122.1)
- [ ] Test DNS resolution from VM using VyOS gateway (192.168.50.1) - IF reachable
- [ ] Measure DNS query latency and reliability for both options
- [ ] Identify which DNS server can resolve: cluster DNS + external DNS + internet
- [ ] Document DNS query flow for each architecture

### Phase 5: Standardization and Documentation
- [ ] Choose DNS architecture based on test results
- [ ] Update all 15+ example cluster.yml files consistently
- [ ] Update CLAUDE.md, llm.txt, README.md with DNS requirements
- [ ] Create troubleshooting guide for DNS issues
- [ ] Add DNS validation to create-iso.sh and deploy-on-kvm.sh

## Key Findings

### Finding 1: VyOS Management vs VLAN Network Isolation
- **Description**: VyOS management interface (192.168.122.2) is on different network than VLAN interfaces (192.168.50.1)
- **Evidence**: Can ping 192.168.122.2 but not 192.168.50.1
- **Confidence**: High
- **Implication**: Static route alone may not be sufficient; VyOS may need bridge/NAT or hypervisor needs interface on VLAN

### Finding 2: Two Possible DNS Architectures
- **Description**: Two valid DNS approaches identified:
  - **Option A**: VMs use libvirt dnsmasq (192.168.122.1) - requires VMs can route to 192.168.122.0/24
  - **Option B**: VMs use VyOS gateway (192.168.50.1) - requires VyOS VLAN interfaces working
- **Evidence**: deploy-on-kvm.sh auto-configures libvirt DNS, vyos-config.sh includes DNS forwarding
- **Confidence**: High
- **Current blocker**: Option B blocked by VyOS VLAN inaccessibility; Option A needs network routing validation

### Finding 3: DNS Forwarders Critical for External Resolution
- **Description**: Libvirt dnsmasq MUST have upstream forwarders to resolve external domains (quay.io, registry.redhat.io)
- **Evidence**: Bootstrap failed with "cannot resolve quay.io" until forwarders added
- **Confidence**: High
- **Status**: ✅ FIXED - configure_dns_forwarders() added to deploy-on-kvm.sh

### Finding 4: Example Configurations Inconsistent
- **Description**: 15+ examples use different DNS servers, many pointing to non-existent addresses
- **Evidence**: GitHub Issue #32 tracks 12 examples needing DNS fixes
- **Confidence**: High
- **Impact**: Poor first-time user experience, deployment failures

## Implications

### Architectural Impact
- **DNS Architecture Decision Needed**: Must choose between libvirt dnsmasq vs VyOS gateway approach and standardize
- **Routing Requirements**: Network routing between hypervisor, VyOS, and VMs must be clearly defined
- **VLAN Strategy**: Need to document which VLANs are used for what purposes

### Technology Choices
- **VyOS Configuration**: May need to modify vyos-config.sh to ensure VLAN interfaces are UP
- **Libvirt Network**: May need to add static routes or bridge configuration to libvirt network XML
- **OpenShift NMState**: Node network configuration must match chosen DNS architecture

### Risk Assessment
- **High Risk**: Continuing deployment without VyOS VLAN access will cause DNS failures
- **Medium Risk**: Inconsistent DNS configuration across examples will confuse users
- **Low Risk**: DNS forwarder fix may need validation in disconnected environments

## Recommendations

### Immediate Actions (Next 2 hours)
1. **SSH into VyOS and verify VLAN interface configuration** - HIGHEST PRIORITY
   - Run: `show interfaces ethernet eth1 vif 1924`
   - Verify IP: 192.168.50.1/24
   - If DOWN, bring up: `configure; set interfaces ethernet eth1 vif 1924 state up; commit; save`

2. **Re-apply VyOS configuration script if interfaces not configured**
   - Copy: `scp ~/vyos-config.sh vyos@192.168.122.2:/tmp/`
   - Execute: `ssh vyos@192.168.122.2 "sudo vbash /tmp/vyos-config.sh"`
   - Verify: Check all VLAN interfaces are UP

3. **Test network routing from VyOS perspective**
   - From VyOS: `ping 192.168.122.1` (hypervisor libvirt bridge)
   - From VyOS: Check routing: `show ip route`
   - Identify if VyOS can route back to hypervisor

### Short-term Actions (Next 24 hours)
4. **Choose and document DNS architecture**
   - If VyOS VLANs working → Test Option B (VyOS gateway DNS)
   - If VyOS VLANs not accessible → Use Option A (libvirt dnsmasq)
   - Document decision in ADR

5. **Standardize all example configurations**
   - Update 12 remaining examples per GitHub Issue #32
   - Use consistent DNS server based on chosen architecture
   - Add validation to create-iso.sh

6. **Update documentation**
   - CLAUDE.md: Add DNS architecture section
   - llm.txt: Update cluster.yml dns_servers parameter docs
   - README.md: Add DNS prerequisites
   - Create troubleshooting guide

### Long-term Actions (Next week)
7. **Add DNS validation to deployment scripts**
   - create-iso.sh: Validate DNS server accessibility
   - deploy-on-kvm.sh: Test DNS resolution before VM deployment
   - Add `--skip-dns-check` flag for advanced users

8. **Create VyOS deployment validation**
   - Add VyOS interface checks to vyos-router.sh
   - Wait for VLAN interfaces to be UP before proceeding
   - Add timeout/retry logic

9. **Consider alternative VyOS configuration**
   - Investigate if VyOS should bridge VLANs to hypervisor
   - Explore if libvirt network should include VLAN definitions
   - Test if VyOS NAT rules need modification

## Related ADRs

- **DNS Automation (ADR-019)** - Auto-configure libvirt DNS entries via virsh net-update
- **VyOS Router Deployment** - Manual configuration required for VyOS installation
- **Network Configuration Standards** - VLAN and interface naming conventions

## Next Steps

### Immediate (NOW)
- [ ] SSH into VyOS and run `show interfaces` to check VLAN 1924 status
- [ ] If interface DOWN, bring it UP and test connectivity
- [ ] If interface doesn't exist, re-run vyos-config.sh script
- [ ] Test `ping 192.168.50.1` after VyOS fix

### After VyOS Fix
- [ ] Regenerate cluster ISO with correct VLAN 1924 configuration
- [ ] Deploy VM from scratch with new configuration
- [ ] Monitor bootstrap process and DNS resolution
- [ ] Document working DNS architecture in ADR

### Follow-up
- [ ] Update GitHub Issue #32 with chosen DNS architecture
- [ ] Fix remaining 12 example configurations
- [ ] Add DNS validation to deployment scripts
- [ ] Create troubleshooting documentation

## References

- **ICM Memory**: `01KSSZ63A9P1XKMVDN6RBBR2RA` (KVM DNS architecture decision)
- **ICM Memory**: `01KSSZS0J8M4GEW1E54VMDVNCM` (External DNS resolution fix - forwarders)
- **GitHub Issue**: #32 (DNS configuration fixes for 12 remaining examples)
- **File**: `hack/deploy-on-kvm.sh` (lines 49-88: DNS forwarder configuration)
- **File**: `hack/vyos-router.sh` (VyOS deployment script)
- **File**: `~/vyos-config.sh` (VyOS VLAN and DNS configuration)
- **Documentation**: `docs/vyos-manual-configuration.md` (VyOS setup guide)

## Research Timeline

- **2026-05-29 13:41 UTC**: Research template created
- **Status**: Phase 1 (VyOS Configuration Verification) - IN PROGRESS
- **Blocker**: VyOS VLAN interface inaccessibility preventing deployment
- **Next Update**: After VyOS interface investigation complete
