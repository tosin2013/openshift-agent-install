# ADR-0016: RHACM Hub Cluster as Deployment Target

**Status:** Accepted  
**Date:** 2026-05-27  
**Deciders:** Tosin Akinosho, Project Contributors  
**Technical Story:** [PRD REQ-5.6.1] Support enterprise cluster-as-infrastructure pattern via RHACM/MCE integration

## Context and Problem Statement

Currently, the openshift-agent-install project deploys clusters to local KVM/libvirt environments or directly to bare metal. In enterprise environments, clusters are rarely deployed in isolation. Organizations use a "Cluster-as-Infrastructure" pattern where an existing OpenShift "Hub" cluster running Red Hat Advanced Cluster Management (RHACM) or the Multicluster Engine (MCE) is used to provision and manage new "Spoke" clusters.

The project already contains three dormant Jinja2 templates that are the exact Kubernetes Custom Resources (CRs) required for this pattern: `agentclusterinstall.yml.j2`, `clusterdeployment.yml.j2`, and `clusterimageset.yml.j2`. These are rendered when `create_ztp_manifests: true` is set but are never applied to a Hub cluster. The wiring stops at file generation.

**Problem:** How do we extend the project to support Hub cluster-based deployments while maintaining the existing local KVM and bare metal workflows?

## Decision Drivers

- **Enterprise Adoption:** RHACM is the standard for multi-cluster management in enterprise environments
- **Zero Touch Provisioning (ZTP):** Existing ZTP templates need integration, not replacement
- **Redfish Automation:** BareMetalHost CRs enable fully automated server provisioning without manual ISO boot
- **Backward Compatibility:** Local KVM deployments must continue to work unchanged
- **Consistency:** Network configuration (NMState) and node definitions (nodes.yml) should reuse existing data models

## Considered Options

### Option 1: New platform_type: rhacm (Selected)

Add `platform_type: rhacm` as a first-class deployment target alongside `baremetal`, `vsphere`, and `none`. When selected:
- Generate complete set of RHACM provisioning CRs (ClusterDeployment, AgentClusterInstall, ClusterImageSet, InfraEnv, NMStateConfig, BareMetalHost)
- Apply manifests to Hub cluster using `kubernetes.core.k8s` Ansible module
- Monitor AgentClusterInstall status until cluster reaches `Installed` state

**New Required Variables in cluster.yml:**
```yaml
platform_type: rhacm
hub_kubeconfig: ~/.kube/hub-config
hub_namespace: "{{ cluster_name }}"  # Namespace for cluster resources
```

**New Optional Variables in nodes.yml (for automated BMC provisioning):**
```yaml
nodes:
  - hostname: worker-01
    bmc_address: 192.168.1.100
    bmc_username: admin
    bmc_password: "{{ vault_bmc_password }}"
    bmc_protocol: redfish-virtualmedia  # or ipmi
```

### Option 2: Separate rhacm-deploy script

Create a standalone `hack/deploy-to-rhacm.sh` script that operates independently of the main playbook workflow.

**Pros:**
- Clear separation of concerns
- No risk of breaking existing workflows

**Cons:**
- Duplicates manifest generation logic
- Requires separate documentation and examples
- Breaks the unified configuration model (cluster.yml as single source of truth)

### Option 3: External GitOps integration

Rely on external GitOps tools (Argo CD, Flux) to apply generated manifests to Hub cluster.

**Pros:**
- Leverages existing GitOps infrastructure
- No custom deployment logic needed

**Cons:**
- Requires users to manage GitOps tooling separately
- Doesn't align with the project's "declarative, automated deployment" philosophy
- No built-in status monitoring or validation

## Decision Outcome

**Chosen option:** Option 1 (platform_type: rhacm) because it:
- Maintains the declarative, single-configuration model
- Reuses existing templates and data structures
- Enables fully automated physical server provisioning via Redfish
- Provides a clear upgrade path for users transitioning from local to Hub-based deployments
- Keeps the project's scope focused on OpenShift deployment automation

### Implementation Details

#### New Playbook: `playbooks/deploy-to-rhacm.yml`

Core orchestration logic:
1. Validate Hub cluster kubeconfig and connectivity
2. Create namespace on Hub cluster if it doesn't exist
3. Generate all required CRs using existing templates
4. Apply manifests to Hub cluster
5. Monitor AgentClusterInstall status conditions
6. Report installation progress and final state

#### New Templates Required

1. **infraenv.yml.j2** (Missing Critical Piece)
   - Defines InfraEnv CR that instructs Hub's Assisted Service to generate Discovery ISO
   - Maps to cluster.yml configuration (cluster_name, base_domain, pull_secret)
   - Outputs ISO download URL for manual retrieval if needed

2. **nmstateconfig.yml.j2**
   - Maps directly to per-node `networkConfig` blocks in nodes.yml
   - No new data model changes required for majority of use cases
   - Reuses existing NMState YAML validation

3. **baremetalhost.yml.j2** (Optional, requires BMC details)
   - Generated only when `bmc_address`, `bmc_username`, `bmc_password` defined in nodes.yml
   - Enables fully automated server power-on and ISO boot
   - Replaces manual `hack/deploy-on-kvm.sh` workflow for physical environments

#### Existing Templates (Validate and Enhance)

- **agentclusterinstall.yml.j2:** Ensure completeness for Hub deployment
- **clusterdeployment.yml.j2:** Ensure completeness for Hub deployment  
- **clusterimageset.yml.j2:** Ensure completeness for Hub deployment

#### Workflow Comparison

**Current Workflow (Local KVM):**
```
cluster.yml + nodes.yml
  ↓
ansible-playbook playbooks/create-manifests.yml
  ↓
openshift-install agent create image
  ↓
hack/deploy-on-kvm.sh (VMs + Redfish emulation)
  ↓
Monitor installation via openshift-install agent wait-for
```

**New Workflow (RHACM Hub):**
```
cluster.yml + nodes.yml + platform_type: rhacm
  ↓
ansible-playbook playbooks/deploy-to-rhacm.yml
  ↓
Apply CRs to Hub cluster (ClusterDeployment, AgentClusterInstall, InfraEnv, etc.)
  ↓
Hub's Assisted Service generates Discovery ISO
  ↓
BareMetalHost CRs power on physical servers (if BMC configured)
  ↓
Monitor AgentClusterInstall status via playbook
```

## Consequences

### Positive

- **Enterprise Alignment:** Matches how Red Hat customers actually deploy clusters at scale
- **Physical Server Automation:** BareMetalHost integration eliminates manual ISO boot steps
- **Hub Cluster Testing:** Enables E2E testing of the full RHACM deployment lifecycle
- **ZTP Template Activation:** Existing dormant templates now have a functional integration path
- **Redfish Value:** Redfish/BMC management capabilities become fully utilized

### Negative

- **Hub Cluster Prerequisite:** Requires an existing Hub cluster with RHACM/MCE installed
- **Testing Complexity:** E2E tests now require Hub cluster setup (mitigated by `hack/deploy-hub-cluster.sh`)
- **Version Matrix:** Hub cluster version, MCE version, and target OCP version must be compatible
- **Authentication:** Requires valid kubeconfig with permissions to create namespaces and CRs

### Neutral

- **Coexistence:** Local KVM deployments continue unchanged; no breaking changes for existing users
- **Learning Curve:** Users must understand RHACM/MCE concepts for Hub-based deployments

## Risks and Mitigations

### Risk 1: Hub Cluster Availability for Testing

**Risk:** E2E tests require a running Hub cluster, which may not be available in all CI/CD environments.

**Mitigation:** Create `hack/deploy-hub-cluster.sh` script that deploys a minimal Hub cluster using the existing KVM automation, enabling self-contained E2E testing.

### Risk 2: RHACM/MCE Version Compatibility

**Risk:** Different Hub cluster versions support different MCE versions, which in turn support different target OpenShift versions.

**Mitigation:** 
- Document compatibility matrix in `docs/rhacm-hypershift-compatibility.md`
- Add runtime validation for `hub_mce_version` variable
- Fail early with clear error messages if incompatible versions detected

### Risk 3: Credential Management for BMC

**Risk:** Storing BMC credentials in plain text in nodes.yml is a security risk.

**Mitigation:**
- Document Ansible Vault usage in `examples/rhacm-sno-example/README.md`
- Provide `vault-example.yml` template with encrypted credential structure
- Add pre-flight validation for required BMC variables

## Validation and Testing

### Acceptance Criteria

- [ ] Setting `platform_type: rhacm` and running `ansible-playbook playbooks/deploy-to-rhacm.yml` results in creation of all required CRs on Hub cluster
- [ ] Hub cluster successfully generates Discovery ISO and begins cluster installation
- [ ] When BMC details provided, BareMetalHost CR is created and Hub cluster powers on physical server automatically
- [ ] New example directory `examples/rhacm-sno-example/` created with reference cluster.yml and nodes.yml
- [ ] Documentation added to deployment-patterns.md covering RHACM Hub deployment workflow

### Test Scenarios

1. **SNO via RHACM (Virtual):** Deploy SNO cluster to KVM-emulated BMC via Hub cluster
2. **SNO via RHACM (Physical):** Deploy SNO cluster to physical server with Redfish BMC
3. **3-Node Compact via RHACM:** Deploy 3-node compact cluster with automated BMC provisioning
4. **Hub Cluster Bootstrap:** Validate `hack/deploy-hub-cluster.sh` can deploy minimal Hub for testing

## References

- [Hive Integration with Assisted Service](https://github.com/openshift/assisted-service/blob/master/docs/hive-integration/README.md)
- [OpenShift Agent-Based Installer Documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/installing_an_on-premise_cluster_with_the_agent-based_installer/)
- [Red Hat Advanced Cluster Management Documentation](https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/)
- [PRD Section 5.6.1: RHACM Agent-Based Provisioning](../prd-forward-looking-roadmap.md#561-rhacm-agent-based-provisioning-hive-integration)

## Related ADRs

- [ADR-0001: Agent-Based Installation Approach](0001-agent-based-installation-approach.md) - Foundation decision
- [ADR-0008: BMC Management and Automation](0008-bmc-management-and-automation.md) - Redfish integration
- [ADR-0017: HyperShift Hosted Control Planes](0017-hypershift-hosted-control-planes.md) - Next evolution (Hub-hosted control planes)
