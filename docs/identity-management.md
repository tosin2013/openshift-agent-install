---
layout: default
title: Identity Management
description: Guide for configuring identity management in OpenShift Agent-based installations
---

# Identity Management Guide

This guide covers identity management configuration for OpenShift Agent-based installations.

## Overview

OpenShift supports various identity providers to authenticate users:
- LDAP/Active Directory
- HTPasswd
- OpenID Connect
- GitHub
- GitLab
- Google
- Azure Active Directory

## Configuration Methods

### 1. HTPasswd Provider

```yaml
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: local_auth
    mappingMethod: claim
    type: HTPasswd
    htpasswd:
      fileData:
        name: htpass-secret
```

Create HTPasswd file:
```bash
# Create HTPasswd file
htpasswd -c -B -b users.htpasswd admin password

# Create secret
oc create secret generic htpass-secret \
  --from-file=htpasswd=users.htpasswd \
  -n openshift-config

# Apply configuration
oc apply -f oauth-config.yaml
```

### 2. LDAP Authentication

```yaml
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: ldap_provider
    mappingMethod: claim
    type: LDAP
    ldap:
      attributes:
        id:
        - dn
        email:
        - mail
        name:
        - cn
        preferredUsername:
        - uid
      bindDN: "cn=directory manager"
      bindPassword:
        name: ldap-secret
      ca:
        name: ca-config-map
      insecure: false
      url: "ldap://ldap.example.com/ou=users,dc=example,dc=com?uid"
```

Configure LDAP:
```bash
# Create bind password secret
oc create secret generic ldap-secret \
  --from-literal=bindPassword=<password> \
  -n openshift-config

# Create CA config map
oc create configmap ca-config-map \
  --from-file=ca.crt=ldap-ca.crt \
  -n openshift-config

# Apply configuration
oc apply -f oauth-ldap-config.yaml
```

### 3. OpenID Connect Provider

```yaml
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: oidc_provider
    mappingMethod: claim
    type: OpenID
    openID:
      clientID: <client_id>
      clientSecret:
        name: oidc-client-secret
      claims:
        preferredUsername:
        - preferred_username
        - email
        name:
        - name
        email:
        - email
      issuer: https://oidc.example.com
```

Configure OpenID Connect:
```bash
# Create client secret
oc create secret generic oidc-client-secret \
  --from-literal=clientSecret=<secret> \
  -n openshift-config

# Apply configuration
oc apply -f oauth-oidc-config.yaml
```

## Role-Based Access Control (RBAC)

### 1. Cluster Roles

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: custom-admin
rules:
- apiGroups: [""]
  resources: ["pods", "services"]
  verbs: ["get", "list", "watch", "create", "update", "delete"]
```

### 2. Role Bindings

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: custom-admin-binding
subjects:
- kind: User
  name: admin
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: custom-admin
  apiGroup: rbac.authorization.k8s.io
```

## Group Synchronization

### 1. LDAP Group Sync

```yaml
apiVersion: config.openshift.io/v1
kind: LDAPSyncConfig
kind: RFC2307
bindDN: "cn=directory manager"
bindPassword: "password"
insecure: false
ca: ca.crt
rfc2307:
    groupsQuery:
        baseDN: "ou=groups,dc=example,dc=com"
        scope: sub
        derefAliases: never
        filter: "(objectClass=groupOfNames)"
    groupUIDAttribute: dn
    groupNameAttributes: [ cn ]
    groupMembershipAttributes: [ member ]
    usersQuery:
        baseDN: "ou=users,dc=example,dc=com"
        scope: sub
        derefAliases: never
        filter: "(objectClass=person)"
    userUIDAttribute: dn
    userNameAttributes: [ uid ]
```

Run group sync:
```bash
# Perform group synchronization
oc adm groups sync --sync-config=ldap-sync-config.yaml --confirm

# View synchronized groups
oc get groups
```

## Security Best Practices

### 1. Password Policies

```yaml
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  tokenConfig:
    accessTokenMaxAgeSeconds: 86400
    accessTokenInactivityTimeout: 24h
```

### 2. Certificate Management

```bash
# Rotate OAuth certificates
oc -n openshift-config delete secret v4-0-config-system-oauth-template-secret

# Verify certificate rotation
oc get secrets -n openshift-config
```

### 3. Audit Logging

```yaml
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  audit:
    profile: WriteRequestBodies
```

## Troubleshooting

### Common Issues

**Authentication Failures**

```bash
# Check OAuth pods
oc get pods -n openshift-authentication

# View OAuth logs
oc logs deployment/oauth-openshift -n openshift-authentication

# Check OAuth configuration
oc get oauth cluster -o yaml
```

**Group Sync Issues**

```bash
# Debug group sync
oc adm groups sync --sync-config=ldap-sync-config.yaml --confirm --debug-level=5

# Check group membership
oc get groups <group_name> -o yaml
```

**Certificate Issues**

```bash
# Verify certificate validity
openssl x509 -in /path/to/cert.crt -text -noout

# Check OAuth routes
oc get routes -n openshift-authentication
```

## Related Documentation

- [Installation Guide](installation-guide)
- [Configuration Guide](configuration-guide)
- [Security Guide](security-guide)
- [Troubleshooting Guide](troubleshooting) 