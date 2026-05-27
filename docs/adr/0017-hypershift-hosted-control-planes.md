# ADR-0017: HyperShift Hosted Control Planes for Edge Deployments

**Status:** Accepted  
**Date:** 2026-05-27  
**Deciders:** Tosin Akinosho, Project Contributors  
**Technical Story:** [PRD REQ-5.6.2] Support cost-optimized edge deployments with Hub-hosted control planes

## Context and Problem Statement

Traditional OpenShift deployments require three dedicated control plane nodes per cluster, each running etcd, API servers, controller managers, and schedulers. For edge computing and distributed deployments where organizations need many small clusters (e.g., retail stores, telecom edge sites, factory floors), this creates massive infrastructure overhead:

- **3-node cluster minimum:** Even a "compact" cluster requires 3 control plane nodes
- **Control plane resource waste:** Edge workloads often need only 1-2 worker nodes, but must provision 3 control planes
- **Operational complexity:** Each cluster has its own independent control plane to monitor, patch, and upgrade

HyperShift solves this by running control plane components as standard pods on a central "Hub" cluster, while worker nodes run on bare metal or virtual machines at the edge. This is now GA for bare metal as of OpenShift 4.14 and is the strategic direction for edge computing in OpenShift.

**Problem:** How do we integrate HyperShift hosted control planes into the project's declarative deployment model while maintaining compatibility with traditional standalone deployments?

## Decision Drivers

- **Cost Optimization:** Eliminate dedicated control plane nodes for edge clusters
- **Scalability:** Enable management of hundreds of edge clusters from a single Hub
- **Resource Efficiency:** Free up compute, memory, and storage for actual workloads
- **Edge Strategy Alignment:** HyperShift is Red Hat's strategic direction for edge deployments
- **Operational Simplicity:** Centralized control plane management and lifecycle
- **Worker Node Consistency:** Edge workers should boot via same Agent-based discovery ISO as traditional deployments

## Considered Options

### Option 1: New platform_type: hypershift (Selected)

Add `platform_type: hypershift` as a deployment target alongside `rhacm`, `baremetal`, `vsphere`, and `none`. When selected:
- Generate `HostedCluster` CR defining the cluster's control plane configuration
- Generate `NodePool` CR defining the worker node configuration
- Apply manifests to Hub cluster with HyperShift Operator enabled
- Worker nodes boot via Agent-based discovery ISO, maintaining consistency with existing approach

**New Required Variables in cluster.yml:**
```yaml
platform_type: hypershift
hub_kubeconfig: ~/.kube/hub-config
hub_namespace: clusters  # Namespace for HostedCluster CR
hosted_cluster_namespace: "{{ cluster_name }}"  # Namespace where control plane pods run

# HyperShift-specific configuration
hypershift:
  release_image: quay.io/openshift-release-dev/ocp-release:4.21.0-x86_64
  node_pool_replicas: 2  # Number of worker nodes
  management_type: Standalone  # or Management (multi-tenant)
```

**New Optional Variables:**
```yaml
hypershift:
  fips_enabled: false
  network_type: OVNKubernetes
  service_cidr: 172.31.0.0/16
  cluster_cidr: 10.132.0.0/14
  control_plane_availability: HighlyAvailable  # or SingleReplica
```

### Option 2: Extend RHACM deployment with --hypershift flag

Add a `--hypershift` flag to the existing `deploy-to-rhacm.yml` playbook that switches from traditional AgentClusterInstall to HyperShift HostedCluster.

**Pros:**
- Single playbook for all Hub-based deployments
- Shared validation and error handling logic

**Cons:**
- Complicates playbook logic with conditionals
- HostedCluster and AgentClusterInstall have fundamentally different architectures
- Harder to maintain and debug

### Option 3: Manual HyperShift CLI workflow

Rely on the `hypershift` CLI tool for cluster creation and only generate discovery ISO for worker nodes.

**Pros:**
- Leverages upstream HyperShift CLI tooling
- No custom CR generation needed

**Cons:**
- Breaks the project's declarative, Ansible-driven automation model
- Requires users to learn HyperShift CLI commands
- Doesn't align with the "single configuration file" philosophy

## Decision Outcome

**Chosen option:** Option 1 (platform_type: hypershift) because it:
- Maintains the declarative, single-configuration model
- Clearly separates HyperShift logic from traditional RHACM deployments
- Enables future optimization specific to HyperShift (e.g., control plane resource tuning)
- Provides a natural evolution path: standalone → RHACM → HyperShift
- Keeps worker node provisioning consistent with existing Agent-based approach

### Implementation Details

#### New Playbook: `playbooks/deploy-to-hypershift.yml` (or extend deploy-to-rhacm.yml)

**Decision:** Start with separate playbook, merge later if commonalities justify it.

Core orchestration logic:
1. Validate Hub cluster has HyperShift Operator installed (MCE 2.3+)
2. Create namespaces: one for HostedCluster CR, one for control plane pods
3. Generate HostedCluster and NodePool CRs
4. Apply manifests to Hub cluster
5. Monitor HostedCluster conditions until Available=True
6. Generate discovery ISO for worker nodes (via InfraEnv CR)
7. Provision worker nodes (KVM or bare metal with BMC)

#### New Templates Required

1. **hostedcluster.yml.j2**
   - Defines HostedCluster CR with control plane configuration
   - Maps cluster.yml values: cluster_name, base_domain, network_type, release_image
   - Specifies platform: Agent (for bare metal worker nodes)
   - Configures control plane availability (SingleReplica for cost optimization, HighlyAvailable for production)

2. **nodepool.yml.j2**
   - Defines NodePool CR with worker node configuration
   - Maps nodes.yml values: node count, machine type, root device hints
   - References InfraEnv for discovery ISO
   - Specifies node labels, taints, and autoscaling config

#### Workflow Comparison

**Traditional Standalone Deployment:**
```
3 control plane nodes + N worker nodes
Each node runs: kubelet, CRI-O, control plane containers (CP nodes only)
Dedicated etcd, API server, controllers per cluster
```

**HyperShift Deployment:**
```
Hub Cluster:
  - Control plane pods (etcd, API, controllers) run as workloads
  - Managed by HyperShift Operator
  - Centralized monitoring and lifecycle

Edge Location:
  - N worker nodes (no control planes)
  - Boot via Agent discovery ISO
  - Connect to Hub-hosted control plane
```

**Cost Comparison (10 Edge Clusters):**

| Deployment Model | Control Plane Nodes | Worker Nodes | Total Nodes |
|---|---|---|---|
| Traditional (3-node compact) | 30 | 0 | 30 |
| Traditional (HA with workers) | 30 | 20 | 50 |
| HyperShift | 0 (Hub shared) | 20 | 20 |

**Savings:** 60% reduction in infrastructure for compact clusters, 40% for HA clusters.

## Consequences

### Positive

- **Cost Optimization:** Eliminate 3 control plane nodes per edge cluster (60-80% infrastructure reduction)
- **Scalability:** Single Hub cluster can host hundreds of edge cluster control planes
- **Operational Efficiency:** Centralized control plane upgrades, monitoring, and disaster recovery
- **Edge Strategy Alignment:** Matches Red Hat's strategic direction for edge computing
- **Worker Node Consistency:** Edge workers use same Agent-based ISO as traditional deployments

### Negative

- **Hub Cluster Dependency:** Edge clusters cannot function if Hub cluster is unavailable (mitigated by multi-Hub HA)
- **Version Matrix Complexity:** Hub OCP version, MCE version, and edge cluster version must be compatible
- **Network Latency:** Worker-to-control-plane latency matters (Hub should be < 100ms from edge)
- **Learning Curve:** Operators must understand HyperShift architecture and troubleshooting

### Neutral

- **New Architecture:** HyperShift is a fundamentally different deployment model, not just a configuration variant
- **Limited Platform Support:** Currently GA for bare metal Agent platform only (AWS/Azure/vSphere support varies)

## Risks and Mitigations

### Risk 1: Hub Cluster Availability

**Risk:** If the Hub cluster fails, all edge cluster control planes fail, causing widespread outage.

**Mitigation:**
- Document multi-Hub HA configuration in `docs/rhacm-hypershift-compatibility.md`
- Recommend dedicated Hub cluster for production (not shared with dev workloads)
- Implement Hub cluster monitoring and automated failover

### Risk 2: Version Compatibility Matrix

**Risk:** The HyperShift Operator version is tied to MCE version, which is tied to Hub cluster version. This creates a three-way version matrix:

| Hub OCP Version | MCE Version | Supported Edge OCP Versions |
|---|---|---|
| 4.20 | 2.6 | 4.18, 4.19, 4.20 |
| 4.21 | 2.7 | 4.19, 4.20, 4.21 |
| 4.22 | 2.8 | 4.20, 4.21, 4.22 |

**Mitigation:**
- Create `docs/rhacm-hypershift-compatibility.md` with full version matrix
- Add `hub_mce_version` variable validation in deploy-to-hypershift.yml playbook
- Fail early with descriptive error if incompatible versions detected
- Document version compatibility in `examples/hypershift-sno-example/README.md`

### Risk 3: Network Latency Requirements

**Risk:** HyperShift has stricter network latency requirements than traditional deployments (worker-to-control-plane < 100ms recommended).

**Mitigation:**
- Document latency requirements in `docs/deployment-patterns.md`
- Add latency testing to `hack/deploy-hub-cluster.sh` validation
- Recommend Hub cluster placement in same region/datacenter as edge clusters

### Risk 4: MCE Installation Prerequisite

**Risk:** HyperShift requires MCE (Multicluster Engine) installed on Hub cluster, which is not part of standard OpenShift.

**Mitigation:**
- Document MCE installation in `examples/hypershift-sno-example/README.md`
- Add pre-flight validation to check for HyperShift Operator availability
- Provide `hack/install-mce.sh` helper script for automated MCE deployment

## Validation and Testing

### Acceptance Criteria

- [ ] Setting `platform_type: hypershift` and running `ansible-playbook playbooks/deploy-to-hypershift.yml` creates valid HostedCluster and NodePool CRs on Hub cluster
- [ ] Hub cluster successfully provisions control plane pods in hosted cluster namespace
- [ ] Worker nodes boot via Agent discovery ISO and join the hosted cluster
- [ ] New example directory `examples/hypershift-sno-example/` created with reference configuration
- [ ] Documentation added to `docs/deployment-patterns.md` covering HyperShift workflow

### Test Scenarios

1. **Single-Replica SNO:** Deploy 1-worker HyperShift cluster with SingleReplica control plane (cost-optimized)
2. **HighlyAvailable 2-Node:** Deploy 2-worker HyperShift cluster with HA control plane
3. **Multi-Cluster Edge:** Deploy 3 HyperShift clusters to same Hub, validate resource isolation
4. **Control Plane Scaling:** Validate Hub cluster can scale to 10+ hosted control planes
5. **Network Partition:** Test edge worker behavior when Hub connectivity lost (expect graceful degradation)

### Version Compatibility Testing

| Test Case | Hub OCP | MCE | Edge OCP | Expected Result |
|---|---|---|---|---|
| Supported path | 4.21 | 2.7 | 4.21 | Success |
| Older edge | 4.21 | 2.7 | 4.19 | Success (N-2 support) |
| Newer edge | 4.21 | 2.7 | 4.22 | Failure (validation should block) |
| Older Hub | 4.19 | 2.5 | 4.21 | Failure (HyperShift unavailable) |

## References

- [HyperShift Documentation](https://hypershift-docs.netlify.app/)
- [Preparing to Deploy Hosted Control Planes (OCP 4.20)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/hosted_control_planes/preparing-to-deploy-hosted-control-planes)
- [Deploying OpenShift Hosted Clusters with HyperShift (Red Hat Developers)](https://developers.redhat.com/articles/2025/10/07/deploying-openshift-hosted-clusters-hypershift)
- [Multicluster Engine Documentation](https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/2.7/html/multicluster_engine/)
- [PRD Section 5.6.2: HyperShift Hosted Control Planes](../prd-forward-looking-roadmap.md#562-hypershift-hosted-control-planes-forward-looking)

## Related ADRs

- [ADR-0001: Agent-Based Installation Approach](0001-agent-based-installation-approach.md) - Foundation decision
- [ADR-0016: RHACM Hub Deployment Target](0016-rhacm-hub-deployment-target.md) - Prerequisite Hub integration
- [ADR-0012: Deployment Patterns and Configurations](0012-deployment-patterns-and-configurations.md) - Edge deployment patterns

## Migration Path

For users currently deploying standalone edge clusters:

1. **Phase 1:** Continue standalone deployments while setting up Hub cluster
2. **Phase 2:** Deploy new clusters via HyperShift to validate workflow
3. **Phase 3:** Migrate existing standalone clusters to HyperShift (manual process, no in-place conversion)

**Note:** There is no automated migration from standalone to HyperShift. Clusters must be redeployed.
