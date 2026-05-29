# Using the openshift-forwarder Ansible Role

## Overview

The `configure-haproxy-forwarder.sh` script clones the [openshift-forwarder](https://github.com/tosin2013/openshift-forwarder) Ansible role but generates its own custom playbook instead of using the role directly.

**Important**: The upstream `openshift-forwarder` role **already includes firewall configuration** - our script's bash firewall function is a workaround for not using the role.

## Option 1: Use Our Script (Current Default)

**Script**: `hack/configure-haproxy-forwarder.sh`

**What it does**:
- Clones openshift-forwarder role (but doesn't use it)
- Generates custom Ansible playbook
- Uses bash `configure_firewall()` function for firewall setup
- Simpler configuration, fewer variables

**Firewall handling**:
```bash
# Automatic firewall configuration via bash function
export EXTERNAL_IP="your-ip"
./hack/configure-haproxy-forwarder.sh site-config/cluster/cluster.yml
```

**Advantages**:
- ✅ Simpler setup (fewer Ansible dependencies)
- ✅ Clear error messages from bash function
- ✅ Integrated into deployment workflow
- ✅ Firewall verification built-in

**Disadvantages**:
- ❌ Doesn't leverage upstream role features
- ❌ Misses SELinux port configuration
- ❌ No future updates from upstream role

## Option 2: Use openshift-forwarder Role Directly

**Repository**: https://github.com/tosin2013/openshift-forwarder

**What the role provides**:
- ✅ HAProxy installation
- ✅ Firewall configuration (firewalld)
- ✅ SELinux port configuration
- ✅ HAProxy service management
- ✅ Template-based configuration

### Installation

```bash
# Clone the role
git clone https://github.com/tosin2013/openshift-forwarder.git
cd openshift-forwarder

# Install dependencies
ansible-galaxy collection install ansible.posix
```

### Usage

Create a playbook that uses the role:

```yaml
---
# haproxy-playbook.yml
- name: Configure HAProxy for OpenShift
  hosts: localhost
  become: yes
  vars:
    external_ip: "169.59.189.20"  # Your external/public IP
    api_vip: "192.168.50.253"      # API VIP from cluster.yml
    app_vip: "192.168.50.252"      # Ingress VIP from cluster.yml
    cluster_name: "ha-test"
    base_domain: "sandbox590.opentlc.com"
  
  roles:
    - role: openshift-forwarder
```

Run the playbook:

```bash
ansible-playbook -i localhost, haproxy-playbook.yml
```

### What the Role Configures

**Firewall Rules** (automatic):
```yaml
# From tasks/install-haproxy.yaml
- name: Add firewall rules for HAProxy
  ansible.posix.firewalld:
    port: "{{ item }}"
    permanent: true
    state: enabled
    immediate: yes
  loop:
    - 80/tcp       # HTTP
    - 443/tcp      # HTTPS
    - 6443/tcp     # Kubernetes API
    - 22623/tcp    # Machine Config Server
    - 32700/tcp    # Additional port
    - 1936/tcp     # HAProxy stats (optional)
```

**SELinux Configuration** (automatic):
```yaml
- name: Set semanage ports for SELinux
  seport:
    ports: "{{ item.port }}"
    proto: tcp
    setype: http_port_t
    state: present
  loop:
    - { port: 22623 }
    - { port: 6443 }
    - { port: 32700 }
    - { port: 1936 }
```

**HAProxy Configuration**:
- Frontend on `external_ip` for all ports
- Backend to cluster VIPs
- Health checks enabled
- TLS passthrough mode

### Required Variables

The role requires these variables:

| Variable | Description | Example |
|----------|-------------|---------|
| `external_ip` | External/public IP address | `169.59.189.20` |
| `api_vip` | OpenShift API VIP | `192.168.50.253` |
| `app_vip` | OpenShift Ingress VIP | `192.168.50.252` |
| `cluster_name` | Cluster name | `ha-test` |
| `base_domain` | Base domain | `sandbox590.opentlc.com` |

### Advantages of Using the Role

- ✅ **Firewall automatic**: No need for manual firewall-cmd
- ✅ **SELinux configured**: Ports properly labeled
- ✅ **Upstream updates**: Get fixes and improvements
- ✅ **Ansible best practices**: Role-based, reusable
- ✅ **Complete solution**: All dependencies handled

### Disadvantages

- ❌ **More dependencies**: Requires ansible.posix collection
- ❌ **More variables**: Need to provide all role vars
- ❌ **Less integrated**: Not in hack/ scripts workflow

## Comparison

| Feature | Our Script | openshift-forwarder Role |
|---------|-----------|--------------------------|
| **Firewall Config** | Bash function | Ansible (firewalld module) |
| **SELinux Config** | ❌ Not included | ✅ Automatic |
| **Installation** | ✅ Simple | Requires ansible.posix |
| **Integration** | ✅ Part of workflow | Manual playbook |
| **Verification** | ✅ Built-in checks | Ansible task reporting |
| **Updates** | Manual | ✅ Upstream git pull |
| **Error Handling** | ✅ Clear bash messages | Ansible error format |

## Recommendation

**For most users**: Use our script (`hack/configure-haproxy-forwarder.sh`)
- ✅ Integrated into deployment workflow
- ✅ Firewall configuration automatic (bash function)
- ✅ Simpler setup

**For advanced users**: Use openshift-forwarder role directly
- ✅ SELinux configuration included
- ✅ More maintainable (Ansible best practices)
- ✅ Get upstream updates

**For production**: Consider using the role
- ✅ SELinux properly configured
- ✅ More robust (Ansible idempotency)
- ✅ Easier to manage at scale

## Why Our Script Doesn't Use the Role

**Historical reasons**:
- Script was created to simplify HAProxy setup
- Custom playbook allows tighter integration with our workflow
- Fewer external dependencies for users

**Trade-offs**:
- We maintain our own HAProxy configuration logic
- We miss upstream role improvements
- We had to add our own firewall function (Issue #33)

## Future Considerations

We may consider:
1. **Option A**: Refactor script to use the role properly
2. **Option B**: Stop cloning the role (don't need it)
3. **Option C**: Keep current approach (working well)

For now, **Option C is implemented** with improved firewall handling.

## Related Documentation

- **IBM Cloud Deployment**: [docs/ibm-cloud-deployment.md](ibm-cloud-deployment.md)
- **HAProxy Script Reference**: [hack/REFERENCE.md](../hack/REFERENCE.md#configure-haproxy-forwardersh)
- **Upstream Role**: https://github.com/tosin2013/openshift-forwarder
- **GitHub Issue #33**: Firewall configuration bug (fixed in our script)

## Examples

### Example 1: Using Our Script (Recommended)

```bash
# Export configuration
export EXTERNAL_IP="169.59.189.20"

# Run integrated script
./hack/configure-haproxy-forwarder.sh site-config/ha-test-4.21-vyos/cluster.yml

# Firewall is configured automatically!
```

### Example 2: Using the Role Directly

```bash
# Clone the role
git clone https://github.com/tosin2013/openshift-forwarder.git roles/openshift-forwarder

# Create inventory
cat > inventory.ini <<EOF
[openshift_forwarder]
localhost ansible_connection=local
EOF

# Create playbook
cat > haproxy.yml <<EOF
---
- hosts: openshift_forwarder
  become: yes
  vars:
    external_ip: "169.59.189.20"
    api_vip: "192.168.50.253"
    app_vip: "192.168.50.252"
    cluster_name: "ha-test"
    base_domain: "sandbox590.opentlc.com"
  roles:
    - openshift-forwarder
EOF

# Install dependencies
ansible-galaxy collection install ansible.posix

# Run playbook
ansible-playbook -i inventory.ini haproxy.yml
```

Both approaches work - choose based on your needs!

## Support

**For script issues**: Create issue in [openshift-agent-install](https://github.com/tosin2013/openshift-agent-install/issues)

**For role issues**: Create issue in [openshift-forwarder](https://github.com/tosin2013/openshift-forwarder/issues)
