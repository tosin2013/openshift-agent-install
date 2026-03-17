# DNS Automation Implementation

## Overview

The deployment workflow now automatically configures DNS entries for OpenShift clusters, eliminating the need for manual DNS configuration.

## What Was Implemented

### 1. Automated DNS Configuration in `deploy-on-kvm.sh`

Two new functions added:

#### `configure_cluster_dns()`
- Parses cluster configuration (cluster_name, base_domain, api_vips, app_vips)
- Adds DNS entries to libvirt's dnsmasq (192.168.122.1)
- Configures API endpoints: `api.<cluster>.<domain>` and `api-int.<cluster>.<domain>`
- Configures common app routes (console, oauth, monitoring, etc.)
- Uses `virsh net-update --live --config` for persistent configuration

#### `configure_host_dns()`
- Detects primary network connection using NetworkManager
- Configures host to use 192.168.122.1 as primary DNS
- Preserves upstream DNS servers as backup (for internet resolution)
- Uses `nmcli` to update connection settings persistently

**Execution**: Both functions run automatically **before VM deployment** starts.

### 2. Automated DNS Cleanup in `destroy-on-kvm.sh`

#### `remove_cluster_dns()`
- Removes all DNS entries for the cluster being destroyed
- Cleans up both API and app route entries
- Runs **before VM destruction** to ensure clean teardown

## Benefits

1. **No Manual DNS Configuration**: DNS entries are automatically created during deployment
2. **Host Access Works**: `oc` commands work without `--server` or `--insecure-skip-tls-verify`
3. **Multi-Cluster Support**: Multiple clusters can coexist with different DNS entries
4. **Persistent**: Configuration survives host reboots
5. **Clean Teardown**: DNS entries automatically removed when cluster is destroyed
6. **Graceful Fallback**: Deployment continues even if DNS configuration fails

## How It Works

### Deployment Flow

```
./hack/deploy-on-kvm.sh examples/cnv-bond0-tagged/nodes.yml --redfish
  ↓
1. Parse nodes.yml and locate cluster.yml
  ↓
2. configure_cluster_dns()
   - Add api.ocp4.example.com → 192.168.50.253
   - Add api-int.ocp4.example.com → 192.168.50.253
   - Add console-openshift-console.apps.ocp4.example.com → 192.168.50.252
   - Add oauth-openshift.apps.ocp4.example.com → 192.168.50.252
   - Add other app routes → 192.168.50.252
  ↓
3. configure_host_dns()
   - Set host DNS: 192.168.122.1 (primary), 161.26.0.10 (backup)
  ↓
4. Deploy VMs (existing flow)
  ↓
5. Cluster installation proceeds with working DNS
```

### Destruction Flow

```
./hack/destroy-on-kvm.sh examples/cnv-bond0-tagged/nodes.yml
  ↓
1. Parse nodes.yml and locate cluster.yml
  ↓
2. remove_cluster_dns()
   - Remove all DNS entries for ocp4.example.com
  ↓
3. Destroy VMs (existing flow)
```

## Verification Steps

### Test 1: Fresh Deployment

```bash
# Deploy a cluster
./hack/create-iso.sh cnv-bond0-tagged
./hack/deploy-on-kvm.sh examples/cnv-bond0-tagged/nodes.yml --redfish

# Verify DNS entries were added to libvirt
sudo virsh net-dumpxml default | grep -A 2 "ocp4.example.com"

# Expected output:
# <host ip='192.168.50.253'>
#   <hostname>api.ocp4.example.com</hostname>
#   <hostname>api-int.ocp4.example.com</hostname>
# </host>
# <host ip='192.168.50.252'>
#   <hostname>console-openshift-console.apps.ocp4.example.com</hostname>
# </host>
```

### Test 2: DNS Resolution

```bash
# Test API DNS resolution (no @192.168.122.1 needed - host DNS is configured)
dig api.ocp4.example.com +short
# Expected: 192.168.50.253

dig console-openshift-console.apps.ocp4.example.com +short
# Expected: 192.168.50.252

# Test that upstream DNS still works
dig google.com +short
# Expected: IP addresses (upstream DNS working)
```

### Test 3: Check Host DNS Configuration

```bash
# View current DNS configuration
nmcli -g ipv4.dns connection show "$(nmcli -t -f NAME,DEVICE connection show --active | grep -v 'lo\|virbr' | head -1 | cut -d: -f1)"

# Expected output:
# 192.168.122.1 161.26.0.10 161.26.0.11
# (or similar, with 192.168.122.1 first)
```

### Test 4: Cluster Access

```bash
# Wait for cluster installation to complete
export KUBECONFIG=/home/vpcuser/generated_assets/ocp4/auth/kubeconfig

# Test cluster access (should work without workarounds)
oc get nodes
oc get co
oc whoami --show-console

# Expected: All commands work, console URL is accessible
```

### Test 5: DNS Cleanup

```bash
# Destroy cluster
./hack/destroy-on-kvm.sh examples/cnv-bond0-tagged/nodes.yml

# Verify DNS entries were removed
sudo virsh net-dumpxml default | grep "ocp4.example.com"

# Expected: No output (entries removed)
```

### Test 6: Multiple Clusters

```bash
# Deploy first cluster (ocp4)
./hack/deploy-on-kvm.sh examples/cnv-bond0-tagged/nodes.yml --redfish

# Modify cluster config for second cluster
cp -r examples/cnv-bond0-tagged examples/cnv-bond0-tagged-2
# Edit examples/cnv-bond0-tagged-2/cluster.yml:
#   cluster_name: ocp5
#   api_vips: [192.168.50.254]
#   app_vips: [192.168.50.253]

# Deploy second cluster
./hack/create-iso.sh cnv-bond0-tagged-2
./hack/deploy-on-kvm.sh examples/cnv-bond0-tagged-2/nodes.yml --redfish

# Both clusters' DNS should work
dig api.ocp4.example.com +short  # → 192.168.50.253
dig api.ocp5.example.com +short  # → 192.168.50.254
```

## Known Limitations

### 1. Wildcard DNS Not Supported

Libvirt dnsmasq doesn't support `*.apps.ocp4.example.com` wildcards.

**Workaround**: Pre-configured common app routes are added automatically:
- console-openshift-console.apps
- oauth-openshift.apps
- grafana-openshift-monitoring.apps
- prometheus-k8s-openshift-monitoring.apps
- alertmanager-main-openshift-monitoring.apps
- thanos-querier-openshift-monitoring.apps
- downloads-openshift-console.apps

**Impact**: Less common routes may not resolve until manually added.

**Solution for additional routes**:
```bash
# Manually add a specific route if needed
sudo virsh net-update default add dns-host \
  "<host ip='192.168.50.252'><hostname>my-app.apps.ocp4.example.com</hostname></host>" \
  --live --config
```

### 2. Requires sudo Access

Both `virsh net-update` and `nmcli connection modify` require sudo privileges.

**Impact**: User must have sudo access on the deployment host.

### 3. Duplicate Entry Warnings

Re-running deployment without cleanup may produce "already exists" warnings.

**Mitigation**: Warnings are suppressed with `grep -v "already exists"` and `2>/dev/null || true`.

### 4. NetworkManager Dependency

Host DNS configuration requires NetworkManager.

**Impact**: Systems using systemd-resolved or static network configuration will skip host DNS setup but libvirt DNS entries will still be configured.

## Troubleshooting

### DNS Resolution Not Working

```bash
# Check if DNS entries exist in libvirt
sudo virsh net-dumpxml default | grep -A 2 "ocp4.example.com"

# If missing, manually configure:
sudo virsh net-update default add dns-host \
  "<host ip='192.168.50.253'><hostname>api.ocp4.example.com</hostname></host>" \
  --live --config
```

### Host Not Using Libvirt DNS

```bash
# Check current DNS configuration
cat /etc/resolv.conf

# If 192.168.122.1 is not listed, check NetworkManager settings
nmcli connection show

# Manually set DNS for your primary connection
PRIMARY_CONN="<your-connection-name>"
sudo nmcli connection modify "$PRIMARY_CONN" ipv4.dns "192.168.122.1 161.26.0.10 161.26.0.11"
sudo nmcli connection up "$PRIMARY_CONN"
```

### DNS Entries Not Removed

```bash
# Manually remove DNS entries
CLUSTER_NAME="ocp4"
BASE_DOMAIN="example.com"
API_VIP="192.168.50.253"
APP_VIP="192.168.50.252"

# Remove API entries
sudo virsh net-update default delete dns-host \
  "<host ip='${API_VIP}'><hostname>api.${CLUSTER_NAME}.${BASE_DOMAIN}</hostname><hostname>api-int.${CLUSTER_NAME}.${BASE_DOMAIN}</hostname></host>" \
  --live --config

# Remove app entries (repeat for each app)
sudo virsh net-update default delete dns-host \
  "<host ip='${APP_VIP}'><hostname>console-openshift-console.apps.${CLUSTER_NAME}.${BASE_DOMAIN}</hostname></host>" \
  --live --config
```

## Configuration Files

### Modified Files

1. **hack/deploy-on-kvm.sh**
   - Lines 49-136: DNS configuration functions
   - Lines 250-274: DNS setup execution before VM deployment

2. **hack/destroy-on-kvm.sh**
   - Lines 12-53: DNS cleanup function
   - Lines 60-72: DNS cleanup execution before VM destruction

### No New Files Created

All functionality integrated into existing deployment scripts.

## Success Criteria

- ✅ DNS entries automatically added to libvirt during deployment
- ✅ Host DNS automatically configured to use libvirt as primary
- ✅ DNS entries automatically removed during destruction
- ✅ DNS resolution works without manual intervention
- ✅ `oc` commands work without workarounds
- ✅ Internet DNS still works (upstream servers as backup)
- ✅ Multiple clusters can coexist
- ✅ Configuration persists across reboots
- ✅ Graceful error handling (deployment continues if DNS fails)

## Future Enhancements

1. **Dynamic Wildcard Support**: Explore alternative DNS solutions that support wildcards
2. **DNS Validation**: Add automated DNS resolution tests before completing deployment
3. **Route Discovery**: Dynamically detect and configure all cluster routes
4. **DNS Fallback**: Optionally add entries to /etc/hosts as backup
5. **Host DNS Restore**: Optionally restore original DNS configuration on destroy
