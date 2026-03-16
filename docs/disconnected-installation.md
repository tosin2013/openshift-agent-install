---
layout: default
title: Disconnected Installation
description: Guide for installing OpenShift in disconnected and air-gapped environments
---

# Disconnected Installation Guide

This guide provides instructions for installing OpenShift in disconnected or air-gapped environments.

## Overview

A disconnected installation is useful when your environment:
- Has no direct internet access
- Requires strict security controls
- Needs complete control over container images
- Must comply with air-gap requirements

## Prerequisites

### Hardware Requirements
- Mirror registry server with sufficient storage
- Installation host with:
  - 8 CPU cores
  - 16 GB RAM
  - 100 GB storage

### Registry Options

You can use several container registry solutions for your disconnected environment:

1. [Red Hat Quay](https://access.redhat.com/documentation/en-us/red_hat_quay/3.10) - Enterprise container registry platform
2. [Harbor Registry](https://goharbor.io/) - Cloud native registry project
3. [JFrog Artifactory](https://jfrog.com/artifactory/) - Universal artifact repository
4. [Docker Registry](https://docs.docker.com/registry/) - Basic container registry

For automated registry setup and disconnected installation assistance, you can use the [OpenShift 4 Disconnected Helper](https://github.com/tosin2013/ocp4-disconnected-helper) tool, which provides:
- Automated registry setup (Harbor, JFrog)
- Image mirroring utilities
- Disconnected installation helpers
- Troubleshooting tools

### Software Requirements
```bash
# Install required packages
sudo dnf install -y \
  podman \
  httpd-tools \
  openssl \
  jq \
  skopeo
```

## Setup Steps

### 1. Configure Mirror Registry

Choose one of the following registry setup options:

#### Option 1: Basic Docker Registry
```bash
# Create registry certificates
mkdir -p /opt/registry/certs
openssl req -newkey rsa:4096 -nodes -sha256 \
  -keyout /opt/registry/certs/registry.key \
  -x509 -days 365 -out /opt/registry/certs/registry.crt \
  -subj "/CN=registry.example.com"

# Create registry auth
mkdir -p /opt/registry/auth
htpasswd -bBc /opt/registry/auth/htpasswd admin password

# Start the registry
podman run --name mirror-registry \
  -p 5000:5000 \
  -v /opt/registry/data:/var/lib/registry:z \
  -v /opt/registry/auth:/auth:z \
  -e "REGISTRY_AUTH=htpasswd" \
  -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" \
  -e "REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd" \
  -v /opt/registry/certs:/certs:z \
  -e "REGISTRY_HTTP_TLS_CERTIFICATE=/certs/registry.crt" \
  -e "REGISTRY_HTTP_TLS_KEY=/certs/registry.key" \
  -d docker.io/library/registry:2
```

#### Option 2: Red Hat Quay
For Quay installation instructions, see [Installing Red Hat Quay on RHEL](https://access.redhat.com/documentation/en-us/red_hat_quay/3.10/html/deploy_red_hat_quay_on_rhel/index).

#### Option 3: Harbor Registry
For Harbor setup using the disconnected helper:
```bash
# Using the disconnected helper tool
git clone https://github.com/tosin2013/ocp4-disconnected-helper
cd ocp4-disconnected-helper
ansible-playbook -i inventory setup-harbor-registry.yml
```

#### Option 4: JFrog Registry
For JFrog setup using the disconnected helper:
```bash
# Using the disconnected helper tool
git clone https://github.com/tosin2013/ocp4-disconnected-helper
cd ocp4-disconnected-helper
ansible-playbook -i inventory setup-jfrog-registry.yml
```

### 2. Mirror OpenShift Images

```bash
# Set environment variables
export LOCAL_REGISTRY="registry.example.com:5000"
export LOCAL_REPOSITORY="ocp4/openshift4"
export PRODUCT_REPO="openshift-release-dev"
export RELEASE_NAME="ocp-release"
export OCP_RELEASE="4.14.0"
export ARCHITECTURE="x86_64"
export REMOVABLE_MEDIA_PATH="/path/to/media"

# Mirror images
oc adm release mirror \
  -a ${LOCAL_SECRET_JSON} \
  --from=quay.io/${PRODUCT_REPO}/${RELEASE_NAME}:${OCP_RELEASE}-${ARCHITECTURE} \
  --to=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY} \
  --to-release-image=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}:${OCP_RELEASE}-${ARCHITECTURE}
```

### 3. Configure Image Content Sources

```yaml
# imageContentSources section in install-config.yaml
imageContentSources:
- mirrors:
  - registry.example.com:5000/ocp4/openshift4
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - registry.example.com:5000/ocp4/openshift4
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
```

### 4. Configure Additional Trust Bundle

```yaml
# additionalTrustBundle section in install-config.yaml
additionalTrustBundle: |
  -----BEGIN CERTIFICATE-----
  # Registry certificate content
  -----END CERTIFICATE-----
```

## Installation Process

### 1. Prepare Installation Files

```bash
# Create installation directory
mkdir ~/disconnected-install
cd ~/disconnected-install

# Create install-config.yaml
cat << EOF > install-config.yaml
apiVersion: v1
baseDomain: example.com
metadata:
  name: disconnected-cluster
platform:
  none: {}
pullSecret: '{"auths":{"registry.example.com:5000": {"auth": "BASE64_AUTH_STRING"}}}'
sshKey: 'SSH_PUBLIC_KEY'
imageContentSources:
- mirrors:
  - registry.example.com:5000/ocp4/openshift4
  source: quay.io/openshift-release-dev/ocp-release
additionalTrustBundle: |
  -----BEGIN CERTIFICATE-----
  # Registry certificate content
  -----END CERTIFICATE-----
EOF
```

### 2. Generate Installation Assets

```bash
# Create manifests
openshift-install create manifests --dir=.

# Create ignition configs
openshift-install create ignition-configs --dir=.
```

### 3. Configure Network

```yaml
# Example network configuration in nodes.yml
networkConfig:
  interfaces:
    - name: eno1
      type: ethernet
      state: up
      ipv4:
        enabled: true
        address:
          - ip: 192.168.1.10
            prefix-length: 24
        dhcp: false
  dns-resolver:
    config:
      server:
        - 192.168.1.53
  routes:
    config:
      - destination: 0.0.0.0/0
        next-hop-address: 192.168.1.1
        next-hop-interface: eno1
```

## Post-Installation Configuration

### 1. Configure Image Registry

```bash
oc patch configs.imageregistry.operator.openshift.io cluster \
  --type merge \
  --patch '{"spec":{"storage":{"emptyDir":{}}}}'
```

### 2. Configure Operators

```bash
# Create CatalogSource for disconnected operators
cat << EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: disconnected-operators
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: registry.example.com:5000/olm/redhat-operators:v1
  displayName: Disconnected Operator Catalog
  publisher: Red Hat
EOF
```

## Troubleshooting

### Common Issues

**Registry Certificate Issues**

```bash
# Check certificate validity
openssl x509 -in /opt/registry/certs/registry.crt -text -noout

# Verify trust bundle
oc get configmap custom-ca -n openshift-config -o yaml
```

**Image Pull Failures**

```bash
# Check image pull secret
oc get secret pull-secret -n openshift-config -o yaml

# Test image pull
podman pull --tls-verify=false registry.example.com:5000/ocp4/openshift4:latest
```

**Network Connectivity**

```bash
# Test registry connectivity
curl -k https://registry.example.com:5000/v2/_catalog

# Check DNS resolution
dig registry.example.com
```

## Related Documentation

- [Installation Guide](installation-guide)
- [Network Configuration](network-configuration)
- [Configuration Guide](configuration-guide)
- [Troubleshooting Guide](troubleshooting)

### External Resources
- [Red Hat Quay Documentation](https://access.redhat.com/documentation/en-us/red_hat_quay/3.10)
- [Harbor Documentation](https://goharbor.io/docs/latest/working-with-projects/create-projects/)
- [JFrog Container Registry Documentation](https://www.jfrog.com/confluence/display/JFROG/Get+Started%3A+JFrog+Container+Registry)
- [OpenShift 4 Disconnected Helper](https://github.com/tosin2013/ocp4-disconnected-helper)
- [OpenShift 4.17 Disconnected Installation Documentation](https://docs.openshift.com/container-platform/4.17/installing/disconnected_install/installing-mirroring-disconnected.html)
