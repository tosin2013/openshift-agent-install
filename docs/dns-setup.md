# DNS Setup for OpenShift Agent-Based Installation

## Overview

This project uses **dnsmasq** as a lightweight DNS server for OpenShift cluster deployments. This replaces the previous FreeIPA-based solution, which was unnecessarily complex for our simple DNS requirements.

## Why dnsmasq Instead of FreeIPA?

### FreeIPA Limitations
- **Outdated**: Targets RHEL 8, incompatible with RHEL 9 environments
- **Overkill**: Deploys full identity management server (Kerberos, LDAP, CA, audit) but only uses DNS
- **Complex**: Requires full VM deployment, bootstrap scripts
- **Resource Heavy**: ~2GB RAM, full VM resources for just 2 DNS A records per cluster
- **Maintenance**: Security patches and management for unused features

### dnsmasq Benefits
- **Lightweight**: ~100MB RAM footprint vs 2GB VM
- **Simple**: Text file configuration
- **Fast**: Immediate setup, no VM provisioning
- **Reliable**: Battle-tested DNS server used widely in virtualization
- **Maintainable**: Single configuration file to manage
- **RHEL 9 Compatible**: Standard package, no version conflicts

## DNS Requirements

For each OpenShift cluster, only **3 DNS records** are needed:

```
api.<cluster_name>.<domain>          -> api_vips[0]
api-int.<cluster_name>.<domain>      -> api_vips[0]
*.apps.<cluster_name>.<domain>       -> app_vips[0]
```

### Example
For cluster `sno-4-20.example.com` with VIP `192.168.100.50`:
```
api.sno-4-20.example.com         -> 192.168.100.50
api-int.sno-4-20.example.com     -> 192.168.100.50
*.apps.sno-4-20.example.com      -> 192.168.100.50
```

## Installation

### Automated Setup (Recommended)

The bootstrap script automatically installs and configures dnsmasq:

```bash
sudo ./e2e-tests/bootstrap_env.sh
```

### Manual Setup

If you need to set up dnsmasq manually:

```bash
# Install and configure dnsmasq
sudo ./hack/setup-dnsmasq.sh

# Add DNS entries for a cluster
sudo ./hack/configure-dnsmasq-entries.sh add examples/sno-4.20-standard/cluster.yml
```

## Configuration Files

- **Main dnsmasq config**: `/etc/dnsmasq.d/openshift.conf`
- **Logs**: `/var/log/dnsmasq.log`
- **Service**: `dnsmasq.service`

## Managing DNS Entries

### Add DNS Entries from Cluster Config

```bash
sudo ./hack/configure-dnsmasq-entries.sh add <cluster_config.yml>
```

Example:
```bash
sudo ./hack/configure-dnsmasq-entries.sh add examples/sno-4.20-standard/cluster.yml
```

### Shortcut Syntax

```bash
sudo ./hack/configure-dnsmasq-entries.sh <cluster_config.yml>
```

### Remove DNS Entries

```bash
sudo ./hack/configure-dnsmasq-entries.sh remove <cluster_name> <base_domain>
```

Example:
```bash
sudo ./hack/configure-dnsmasq-entries.sh remove sno-4-20 example.com
```

### List All DNS Entries

```bash
sudo ./hack/configure-dnsmasq-entries.sh list
```

## Testing DNS Resolution

### Test API Endpoint

```bash
dig @localhost api.<cluster_name>.<base_domain>
```

Example:
```bash
dig @localhost api.sno-4-20.example.com
```

Expected output:
```
;; ANSWER SECTION:
api.sno-4-20.example.com. 0 IN  A       192.168.100.50
```

### Test Wildcard Apps

```bash
dig @localhost test.apps.<cluster_name>.<base_domain>
```

Example:
```bash
dig @localhost console-openshift-console.apps.sno-4-20.example.com
```

Expected output:
```
;; ANSWER SECTION:
console-openshift-console.apps.sno-4-20.example.com. 0 IN A 192.168.100.50
```

### Test from Cluster Nodes

From a cluster node or any machine on the network:

```bash
# Set the DNS server to the host running dnsmasq
dig @<host_ip> api.<cluster_name>.<base_domain>
```

## Troubleshooting

### dnsmasq Not Starting

Check the logs:
```bash
sudo journalctl -u dnsmasq -f
sudo tail -f /var/log/dnsmasq.log
```

Common issues:
1. **Port 53 already in use**: Check if another DNS server is running
   ```bash
   sudo lsof -i :53
   ```

2. **Configuration errors**: Validate the config file
   ```bash
   sudo dnsmasq --test
   ```

### DNS Resolution Not Working

1. **Check dnsmasq is running**:
   ```bash
   sudo systemctl status dnsmasq
   ```

2. **Verify DNS entries exist**:
   ```bash
   sudo ./hack/configure-dnsmasq-entries.sh list
   ```

3. **Test directly**:
   ```bash
   dig @localhost api.<cluster_name>.<base_domain>
   ```

4. **Check firewall**:
   ```bash
   sudo firewall-cmd --list-services
   # Should include 'dns'
   ```

### Reload Configuration

After manual edits to `/etc/dnsmasq.d/openshift.conf`:

```bash
sudo systemctl reload dnsmasq
```

## Integration with Cluster Deployments

### Update cluster.yml

Ensure your cluster configuration points to the dnsmasq server:

```yaml
dns_servers:
  - 192.168.100.1  # IP of host running dnsmasq
```

For localhost deployments:
```yaml
dns_servers:
  - 127.0.0.1
```

### Deployment Workflow

1. **Bootstrap environment** (includes dnsmasq setup):
   ```bash
   sudo ./e2e-tests/bootstrap_env.sh
   ```

2. **Add DNS entries for your cluster**:
   ```bash
   sudo ./hack/configure-dnsmasq-entries.sh add site-config/my-cluster/cluster.yml
   ```

3. **Verify DNS resolution**:
   ```bash
   dig @localhost api.my-cluster.example.com
   ```

4. **Deploy OpenShift cluster**:
   ```bash
   ./openshift-agent-install.sh site-config/my-cluster/cluster.yml
   ```

## Migration from FreeIPA

If you were previously using FreeIPA:

1. **Stop and remove FreeIPA VM** (optional):
   ```bash
   sudo kcli delete vm freeipa
   ```

2. **Install dnsmasq**:
   ```bash
   sudo ./hack/setup-dnsmasq.sh
   ```

3. **Migrate DNS entries**: For each cluster, run:
   ```bash
   sudo ./hack/configure-dnsmasq-entries.sh add <cluster_config.yml>
   ```

4. **Update cluster configs**: Change `dns_servers` to point to dnsmasq host

5. **Test resolution**: Verify all DNS entries work

## Advanced Configuration

### Custom Upstream DNS Servers

Edit `/etc/dnsmasq.d/openshift.conf`:

```bash
# Add before the OpenShift entries:
server=8.8.8.8
server=1.1.1.1
```

Then reload:
```bash
sudo systemctl reload dnsmasq
```

### Disable Query Logging

For production, comment out the logging line in `/etc/dnsmasq.d/openshift.conf`:

```bash
# log-queries
# log-facility=/var/log/dnsmasq.log
```

### Listen on Specific Interface

Edit `/etc/dnsmasq.d/openshift.conf`:

```bash
# Change listen-address to specific IP
listen-address=192.168.100.1
```

## Performance Comparison

| Aspect | FreeIPA | dnsmasq |
|--------|---------|---------|
| **RAM Usage** | ~2GB | ~100MB |
| **Disk Usage** | ~10GB | ~50MB |
| **Setup Time** | 10-15 min | < 1 min |
| **Dependencies** | Full RHEL 8 VM | Single package |
| **Configuration** | Multiple playbooks | Single text file |
| **Maintenance** | VM patching, updates | Service restart |
| **RHEL 9 Support** | ❌ No | ✅ Yes |

## Security Considerations

1. **Firewall**: dnsmasq listens on port 53 (UDP/TCP)
   - Configure firewalld appropriately
   - Restrict access to trusted networks

2. **Logging**: Query logs are enabled by default
   - Review logs regularly
   - Disable in production if not needed

3. **Updates**: Keep dnsmasq package updated
   ```bash
   sudo dnf update dnsmasq
   ```

## References

- [dnsmasq documentation](http://www.thekelleys.org.uk/dnsmasq/doc.html)
- [OpenShift Agent-Based Installation](https://docs.openshift.com/container-platform/latest/installing/installing_with_agent_based_installer/preparing-to-install-with-agent-based-installer.html)
- [Project README](../README.md)
