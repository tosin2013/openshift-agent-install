# DNS Requirements for JFrog Disconnected OpenShift Deployment

## FreeIPA DNS Server
- **Server**: `192.168.122.177` (idm.example.com)
- **Domain**: `example.com`

## Required DNS Records

### OpenShift Cluster Records (ocp-jfrog.example.com)

| Record Type | Name | Value | Purpose |
|-------------|------|-------|---------|
| A | api.ocp-jfrog.example.com | 192.168.122.100 | Kubernetes API |
| A | api-int.ocp-jfrog.example.com | 192.168.122.100 | Internal API |
| A (wildcard) | *.apps.ocp-jfrog.example.com | 192.168.122.101 | Ingress/Routes |

### Node Records

| Record Type | Name | Value |
|-------------|------|-------|
| A | ocp-jfrog-master-0.example.com | 192.168.122.110 |
| A | ocp-jfrog-master-1.example.com | 192.168.122.111 |
| A | ocp-jfrog-master-2.example.com | 192.168.122.112 |

### JFrog Registry Record

| Record Type | Name | Value | Purpose |
|-------------|------|-------|---------|
| A | jfrog.example.com | 192.168.122.200 | JFrog Artifactory |

### Reverse DNS (PTR) Records (Optional but Recommended)

| IP | PTR Record |
|----|------------|
| 192.168.122.100 | api.ocp-jfrog.example.com |
| 192.168.122.110 | ocp-jfrog-master-0.example.com |
| 192.168.122.111 | ocp-jfrog-master-1.example.com |
| 192.168.122.112 | ocp-jfrog-master-2.example.com |
| 192.168.122.200 | jfrog.example.com |

## FreeIPA Commands to Add Records

```bash
# Authenticate to FreeIPA
kinit admin

# Add API VIP record
ipa dnsrecord-add example.com api.ocp-jfrog --a-rec=192.168.122.100
ipa dnsrecord-add example.com api-int.ocp-jfrog --a-rec=192.168.122.100

# Add wildcard apps record
ipa dnsrecord-add example.com '*.apps.ocp-jfrog' --a-rec=192.168.122.101

# Add node records
ipa dnsrecord-add example.com ocp-jfrog-master-0 --a-rec=192.168.122.110
ipa dnsrecord-add example.com ocp-jfrog-master-1 --a-rec=192.168.122.111
ipa dnsrecord-add example.com ocp-jfrog-master-2 --a-rec=192.168.122.112

# Add JFrog registry record
ipa dnsrecord-add example.com jfrog --a-rec=192.168.122.200

# Verify records
dig @192.168.122.177 api.ocp-jfrog.example.com +short
dig @192.168.122.177 *.apps.ocp-jfrog.example.com +short
dig @192.168.122.177 jfrog.example.com +short
```

## Verification

After adding DNS records, verify with:

```bash
# Test API endpoint
dig @192.168.122.177 api.ocp-jfrog.example.com +short
# Expected: 192.168.122.100

# Test wildcard apps
dig @192.168.122.177 console-openshift-console.apps.ocp-jfrog.example.com +short
# Expected: 192.168.122.101

# Test JFrog registry
dig @192.168.122.177 jfrog.example.com +short
# Expected: 192.168.122.200
```

## Notes

- DNS records must be configured BEFORE running the `ocp_jfrog_agent_deployment` DAG
- The JFrog VM IP (192.168.122.200) should match the IP assigned during VM provisioning
- Update the IPs in this document to match your actual network configuration
