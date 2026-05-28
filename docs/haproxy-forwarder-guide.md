---
layout: default
title: HAProxy Forwarder Guide
nav_order: 3
parent: Getting Started
---

# HAProxy Forwarder Configuration Guide

## Overview

The OpenShift Forwarder provides external access to OpenShift clusters via HAProxy load balancing. This guide covers two deployment scenarios:

1. **Development Mode** - Local KVM deployment with example.com domains
2. **Production Mode** - AWS/Cloud deployment with corporate domains

## Repository

**OpenShift Forwarder**: https://github.com/tosin2013/openshift-forwarder

## Architecture

```
                      ┌─────────────────────────────┐
                      │   HAProxy Load Balancer    │
                      │  (External Access Point)    │
                      └──────────┬──────────────────┘
                                 │
                ┌────────────────┼────────────────┐
                │                │                │
                ▼                ▼                ▼
        ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
        │ Master Node  │ │ Master Node  │ │ Master Node  │
        │    (API)     │ │    (API)     │ │    (API)     │
        └──────────────┘ └──────────────┘ └──────────────┘
                │                │                │
                ▼                ▼                ▼
        ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
        │ Worker Node  │ │ Worker Node  │ │ Worker Node  │
        │   (Apps)     │ │   (Apps)     │ │   (Apps)     │
        └──────────────┘ └──────────────┘ └──────────────┘
```

**HAProxy Frontend Ports**:
- **6443/tcp** - OpenShift API (kubernetes API server)
- **80/tcp** - HTTP application traffic (router/ingress)
- **443/tcp** - HTTPS application traffic (router/ingress)
- **1936/tcp** - HAProxy statistics page (admin access)

## Deployment Mode 1: Development (example.com)

### Use Case

- Local KVM development
- Testing cluster deployments
- Quick validation
- Personal lab environments

### Configuration

**Environment**:
```bash
export EXTERNAL_IP=192.168.1.100  # Your development host's IP
```

**Cluster Configuration** (`cluster.yml`):
```yaml
cluster_name: sno-4-20
base_domain: example.com
api_vips:
  - 192.168.100.50
app_vips:
  - 192.168.100.50
```

**Deploy HAProxy**:
```bash
# Configure HAProxy forwarder for development
./hack/configure-haproxy-forwarder.sh examples/sno-4.20-standard/cluster.yml
```

### Access URLs

**API Access**:
```bash
# Direct IP access
export KUBECONFIG=~/generated_assets/sno-4-20/auth/kubeconfig
oc login https://192.168.1.100:6443

# Or with domain (if DNS configured)
oc login https://api.sno-4-20.example.com:6443
```

**Application Access**:
- HTTP: `http://192.168.1.100` → Routes to `*.apps.sno-4-20.example.com`
- HTTPS: `https://192.168.1.100` → Routes to `*.apps.sno-4-20.example.com`

**HAProxy Stats**:
- URL: `http://192.168.1.100:1936/haproxy?stats`
- Username: `admin`
- Password: `password`

### DNS Configuration (Optional)

For development with DNS:

```bash
# Add to /etc/hosts or dnsmasq
192.168.1.100 api.sno-4-20.example.com
192.168.1.100 console-openshift-console.apps.sno-4-20.example.com
192.168.1.100 oauth-openshift.apps.sno-4-20.example.com
```

## Deployment Mode 2: Production (AWS/Corporate Domain)

### Use Case

- Production OpenShift clusters
- AWS/Cloud deployments
- Corporate environments
- Public-facing applications

### AWS Infrastructure Setup

#### Step 1: VPC and Security Groups

**VPC Requirements**:
- Private subnet for OpenShift nodes
- Public subnet for HAProxy instance
- Internet Gateway for public subnet
- NAT Gateway for private subnet (optional)

**Security Group for HAProxy**:
```hcl
# Terraform example
resource "aws_security_group" "haproxy" {
  name        = "openshift-haproxy"
  description = "HAProxy for OpenShift external access"
  vpc_id      = aws_vpc.main.id

  # OpenShift API
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP Application Traffic
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS Application Traffic
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HAProxy Stats (restrict to corporate IP)
  ingress {
    from_port   = 1936
    to_port     = 1936
    protocol    = "tcp"
    cidr_blocks = ["203.0.113.0/24"]  # Your corporate network
  }

  # SSH Access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["203.0.113.0/24"]  # Your corporate network
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

#### Step 2: Elastic IP

**Allocate Elastic IP**:
```bash
# AWS CLI
aws ec2 allocate-address --domain vpc

# Note the Allocation ID and Public IP
# Example: eipalloc-12345678, 203.0.113.50
```

**Associate with HAProxy instance**:
```bash
aws ec2 associate-address \
  --allocation-id eipalloc-12345678 \
  --instance-id i-1234567890abcdef0
```

#### Step 3: Route53 DNS

**Create Hosted Zone** (if not exists):
```bash
aws route53 create-hosted-zone \
  --name mycompany.com \
  --caller-reference $(date +%s)
```

**DNS Records**:
```json
{
  "Changes": [
    {
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "api.prod-cluster.mycompany.com",
        "Type": "A",
        "TTL": 300,
        "ResourceRecords": [
          {
            "Value": "203.0.113.50"
          }
        ]
      }
    },
    {
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "*.apps.prod-cluster.mycompany.com",
        "Type": "A",
        "TTL": 300,
        "ResourceRecords": [
          {
            "Value": "203.0.113.50"
          }
        ]
      }
    }
  ]
}
```

Apply DNS changes:
```bash
aws route53 change-resource-record-sets \
  --hosted-zone-id Z1234567890ABC \
  --change-batch file://dns-records.json
```

### Production HAProxy Configuration

**Environment**:
```bash
export EXTERNAL_IP=203.0.113.50  # Your Elastic IP
export BASE_DOMAIN=mycompany.com
```

**Cluster Configuration** (`cluster.yml`):
```yaml
cluster_name: prod-cluster
base_domain: mycompany.com
api_vips:
  - 10.0.1.100  # Private subnet VIP
app_vips:
  - 10.0.1.101  # Private subnet VIP

# Master nodes in private subnet
masters:
  - ip: 10.0.1.10
  - ip: 10.0.1.11
  - ip: 10.0.1.12

# Worker nodes in private subnet
workers:
  - ip: 10.0.1.20
  - ip: 10.0.1.21
  - ip: 10.0.1.22
```

**Deploy HAProxy**:
```bash
# On HAProxy instance (EC2)
./hack/configure-haproxy-forwarder.sh examples/aws-production/cluster.yml
```

### Production Access URLs

**API Access**:
```bash
oc login https://api.prod-cluster.mycompany.com:6443
```

**Application Access**:
- Console: `https://console-openshift-console.apps.prod-cluster.mycompany.com`
- OAuth: `https://oauth-openshift.apps.prod-cluster.mycompany.com`
- Custom Apps: `https://<route-name>.apps.prod-cluster.mycompany.com`

**HAProxy Stats** (secured):
- URL: `http://203.0.113.50:1936/haproxy?stats`
- Restrict access via security group to corporate IPs only

### Production Security Hardening

#### SSL/TLS Certificates

**Option 1: Let's Encrypt** (for public domains):
```bash
# Install certbot
sudo dnf install -y certbot

# Get wildcard certificate
sudo certbot certonly --manual \
  --preferred-challenges dns \
  -d "*.apps.prod-cluster.mycompany.com"

# Configure HAProxy with certificate
sudo cat /etc/letsencrypt/live/apps.prod-cluster.mycompany.com/fullchain.pem \
        /etc/letsencrypt/live/apps.prod-cluster.mycompany.com/privkey.pem \
        > /etc/haproxy/certs/apps.pem
```

**Option 2: Corporate PKI**:
```bash
# Use your organization's certificate authority
sudo cp /path/to/corporate.crt /etc/haproxy/certs/
sudo cp /path/to/corporate.key /etc/haproxy/certs/
cat /etc/haproxy/certs/corporate.crt \
    /etc/haproxy/certs/corporate.key \
    > /etc/haproxy/certs/apps.pem
```

#### HAProxy Stats Authentication

Update `/etc/haproxy/haproxy.cfg`:
```
listen stats
    bind :1936
    mode http
    stats enable
    stats uri /haproxy?stats
    stats realm HAProxy\ Statistics
    stats auth admin:SecurePasswordHere123!  # Change this!
    stats refresh 30s
```

#### Firewall Rules

```bash
# Allow only necessary ports
sudo firewall-cmd --permanent --add-port=6443/tcp
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="203.0.113.0/24" port protocol="tcp" port="1936" accept'
sudo firewall-cmd --reload
```

## OpenShift Forwarder Installation

### Prerequisites

```bash
# Clone openshift-forwarder repository
git clone https://github.com/tosin2013/openshift-forwarder.git /opt/openshift-forwarder

# Create Ansible role symlink
mkdir -p ~/.ansible/roles/
sudo ln -s /opt/openshift-forwarder ~/.ansible/roles/
```

### Configuration Files

**Create variables file** (`vars/production.yml`):
```yaml
---
# HAProxy Global Settings
haproxy_log_address: "127.0.0.1"
haproxy_chroot_directory: "/var/lib/haproxy"
haproxy_pidfile: "/var/run/haproxy.pid"
haproxy_max_connections: 4000

# Timeout Settings
default_retries: 3
default_timeout_http_request: "10s"
default_timeout_queue: "1m"
default_timeout_connect: "10s"
default_timeout_client: "1m"
default_timeout_server: "1m"
default_timeout_http_keep_alive: "10s"
default_timeout_check: "10s"
default_max_connections: 3000

# Master Nodes (from cluster.yml)
masters:
  - ip: "10.0.1.10"
  - ip: "10.0.1.11"
  - ip: "10.0.1.12"

# Worker Nodes (from cluster.yml)
workers:
  - ip: "10.0.1.20"
  - ip: "10.0.1.21"
  - ip: "10.0.1.22"
```

**Create playbook** (`playbooks/deploy-haproxy.yml`):
```yaml
---
- hosts: localhost
  become: true
  roles:
   - openshift-forwarder
```

### Deployment

**Development**:
```bash
ansible-playbook ./playbooks/deploy-haproxy.yml \
  --extra-vars "@vars/development.yml" \
  -e "ansible_python_interpreter=/usr/bin/python3" -v
```

**Production (AWS)**:
```bash
# On HAProxy EC2 instance
ansible-playbook ./playbooks/deploy-haproxy.yml \
  --extra-vars "@vars/production.yml" \
  -e "ansible_python_interpreter=/usr/bin/python3" -v
```

**RHEL 8.x**:
```bash
ansible-playbook ./playbooks/deploy-haproxy.yml \
  --extra-vars "@vars/production.yml" \
  -e "ansible_python_interpreter=/usr/libexec/platform-python" -v
```

## Monitoring and Health Checks

### HAProxy Stats Dashboard

Access: `http://<haproxy-ip>:1936/haproxy?stats`

**Metrics to Monitor**:
- **Session Rate** - Current connections per second
- **Backend Status** - Green (healthy), Red (down), Orange (draining)
- **Queue Length** - Should be 0 under normal operation
- **Downtime** - Track master/worker node availability
- **Response Time** - Monitor backend response times

### Health Check Endpoints

HAProxy performs health checks every 10 seconds (configurable):

**API Servers** (Masters):
- Port: 6443
- Check: TCP connection
- Interval: 10s

**Ingress Routers** (Workers):
- Port: 80, 443
- Check: HTTP GET /healthz
- Interval: 10s

### Alerting

**Prometheus Integration** (if using OpenShift monitoring):
```bash
# HAProxy Exporter
podman run -d -p 9101:9101 \
  quay.io/prometheus/haproxy-exporter:latest \
  --haproxy.scrape-uri="http://admin:password@localhost:1936/haproxy?stats;csv"
```

## Troubleshooting

### Problem: Cannot access API via HAProxy

**Check 1: HAProxy is running**
```bash
sudo systemctl status haproxy
sudo netstat -tlnp | grep :6443
```

**Check 2: Backend nodes are healthy**
```bash
# Check HAProxy stats page
curl -u admin:password http://localhost:1936/haproxy?stats

# Manually test API endpoint
curl -k https://10.0.1.10:6443/healthz
```

**Check 3: Firewall rules**
```bash
sudo firewall-cmd --list-ports
sudo firewall-cmd --list-services
```

### Problem: Application routes not accessible

**Check 1: Worker nodes healthy**
```bash
# From HAProxy host
curl http://10.0.1.20:80/healthz
curl http://10.0.1.21:80/healthz
```

**Check 2: DNS resolution**
```bash
dig api.prod-cluster.mycompany.com
dig console-openshift-console.apps.prod-cluster.mycompany.com
```

**Check 3: OpenShift router pods**
```bash
oc get pods -n openshift-ingress
oc logs -n openshift-ingress <router-pod>
```

### Problem: High latency through HAProxy

**Check 1: Network path**
```bash
# Test direct connection vs HAProxy
time curl -k https://10.0.1.10:6443/healthz
time curl -k https://203.0.113.50:6443/healthz
```

**Check 2: HAProxy configuration**
```bash
# Review timeout settings
sudo grep timeout /etc/haproxy/haproxy.cfg

# Check connection limits
sudo grep maxconn /etc/haproxy/haproxy.cfg
```

**Check 3: Resource utilization**
```bash
top
free -h
netstat -s | grep -i overflow
```

## Best Practices

### Development Environment

1. **Use IP-based access** - Simplifies setup, no DNS required
2. **Default credentials** - `admin:password` is acceptable for local development
3. **Monitor stats page** - Learn HAProxy behavior during testing
4. **Test failure scenarios** - Kill nodes, simulate network issues

### Production Environment

1. **Use Elastic/Static IPs** - Prevent IP changes from disrupting service
2. **Implement strong authentication** - Change default HAProxy stats credentials
3. **Restrict stats access** - Use security groups to limit stats page access
4. **Enable SSL/TLS** - Use valid certificates from corporate PKI or Let's Encrypt
5. **Monitor actively** - Integrate with Prometheus/Grafana
6. **Document configuration** - Keep runbooks for HAProxy maintenance
7. **Regular updates** - Keep HAProxy package updated for security patches
8. **Backup configuration** - Version control HAProxy configuration files

### High Availability HAProxy

For production, consider multiple HAProxy instances:

```
        ┌─────────────┐
        │   AWS ELB   │  (or corporate load balancer)
        │  (Layer 4)  │
        └──────┬──────┘
               │
       ┌───────┴───────┐
       │               │
  ┌────▼────┐    ┌────▼────┐
  │ HAProxy │    │ HAProxy │
  │  Node 1 │    │  Node 2 │
  └─────────┘    └─────────┘
       │               │
       └───────┬───────┘
               │
        ┌──────▼──────┐
        │  OpenShift  │
        │   Cluster   │
        └─────────────┘
```

## Related Documentation

- [Developer Guide](developer-guide.md) - KVM development setup
- [Installation Guide](installation-guide.md) - Complete deployment walkthrough
- [OpenShift Forwarder Repository](https://github.com/tosin2013/openshift-forwarder)
- [HAProxy Official Documentation](http://www.haproxy.org/#docs)
- [AWS Elastic Load Balancing](https://docs.aws.amazon.com/elasticloadbalancing/)
