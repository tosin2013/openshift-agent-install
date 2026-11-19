---
layout: default
title: "Post-Install: cert-manager Operator"
parent: How-to Guides
nav_order: 20
---

# Post-Install: cert-manager Operator for OpenShift 5.0

Install the cert-manager Operator for Red Hat OpenShift after the cluster is fully up (`wait-for install-complete` has completed and all operators are Available).

**Source manifests**: [tosin2013/openshift-5-deployment-notes/cert-manager](https://github.com/tosin2013/openshift-5-deployment-notes/tree/main/cert-manager)

---

## Prerequisites

- Cluster installed and all operators Available (`oc get co`)
- `oc` pointed at the cluster (`export KUBECONFIG=~/generated_assets/<cluster>/auth/kubeconfig`)
- AWS credentials available (for Route53 DNS01 challenge — same creds used for DNS setup)

---

## Install cert-manager Operator

The manifests use kustomize overlays baked into the `oc` CLI — no separate `kustomize` binary needed.

### Step 1: Clone the deployment notes repo

```bash
git clone https://github.com/tosin2013/openshift-5-deployment-notes.git
cd openshift-5-deployment-notes
```

### Step 2: Apply the stable-v1 overlay

For OCP 5.0 the default channel is `stable-v1` (`cert-manager-operator.v1.20.1` as of Nov 2026):

```bash
oc apply -k cert-manager/operator/overlays/stable-v1
```

To pin to the 1.20 line specifically:
```bash
oc apply -k cert-manager/operator/overlays/stable-v1.20
```

### Step 3: Wait for the operator to be ready

```bash
# Subscription and CSV
oc get subscription -n cert-manager-operator
oc get csv -n cert-manager-operator   # Phase must be: Succeeded

# Operator pod (cert-manager-operator namespace)
oc get pods -n cert-manager-operator

# cert-manager workload pods (cert-manager namespace)
oc get pods -n cert-manager
```

Expected pods in `cert-manager`:
- `cert-manager-*` — core controller
- `cert-manager-cainjector-*` — CA injector
- `cert-manager-webhook-*` — webhook

---

## Configure Route53 DNS01 Issuer (IBM Cloud / AWS)

For clusters with public Route53 DNS (e.g. `sandbox2401.opentlc.com`), use a DNS01 ACME issuer with AWS credentials to obtain Let's Encrypt certificates.

### Create AWS credentials secret

```bash
oc create secret generic route53-credentials \
  --from-literal=awsSecretAccessKey=<your-aws-secret-key> \
  -n cert-manager
```

### Create a ClusterIssuer

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: <your-email>
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
    - dns01:
        route53:
          region: us-east-1
          hostedZoneID: <your-route53-zone-id>
          accessKeyID: <your-aws-access-key-id>
          secretAccessKeySecretRef:
            name: route53-credentials
            key: awsSecretAccessKey
```

```bash
oc apply -f clusterissuer.yaml
```

### Verify issuer is ready

```bash
oc get clusterissuer letsencrypt-prod -o jsonpath='{.status.conditions[0].message}'
# Should show: The ACME account was registered with the ACME server
```

---

## Replace Default Ingress Certificate

Once the issuer is ready, request a wildcard certificate for the apps domain:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: apps-wildcard
  namespace: openshift-ingress
spec:
  secretName: apps-wildcard-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - "*.apps.<cluster-name>.<base-domain>"
```

```bash
oc apply -f apps-certificate.yaml

# Wait for certificate to be issued (~2 min for DNS01 challenge)
oc get certificate -n openshift-ingress -w

# Patch ingress controller to use the new cert
oc patch ingresscontroller default -n openshift-ingress-operator \
  --type=merge \
  --patch='{"spec":{"defaultCertificate":{"name":"apps-wildcard-tls"}}}'
```

---

## References

- [cert-manager Operator for Red Hat OpenShift 5.0](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/security_and_compliance/cert-manager-operator-for-red-hat-openshift)
- [openshift-5-deployment-notes/cert-manager](https://github.com/tosin2013/openshift-5-deployment-notes/tree/main/cert-manager)
- [post-steps/create_custom_cert.sh](https://github.com/tosin2013/openshift-5-deployment-notes/blob/main/post-steps/create_custom_cert.sh) — full Route53 certificate automation script
