# OpenShift Agent-Based Installer: how to deploy 4.22 clusters with declarative automation

## The cluster deployment problem every platform engineer knows

If you've ever hand-crafted an install-config.yaml for Red Hat OpenShift, you know the pain. One misplaced CIDR, a forgotten DNS record, or a deprecated field for your target version, and you're staring at a failed bootstrap wondering what went wrong. Multiply that across dozens of clusters in development, staging, and production, and the toil becomes unsustainable.

The Agent-Based Installer (ABI) simplified OpenShift deployments by eliminating the need for a bootstrap node. But you still need to produce correct manifests, manage DNS, and deliver the ISO to your infrastructure. That's where declarative automation comes in.

In this post, I'll walk you through an open source framework that wraps the standard openshift-install tool with two-file declarative configuration, Ansible-driven manifest templating, and end-to-end orchestration for both KVM labs and bare-metal production. You'll go from two YAML files to a running OpenShift 4.22 cluster with a single command.

## Prerequisites

Before you begin, make sure you have:

- A Red Hat Enterprise Linux 9.x host (physical or VM with nested virtualization for KVM labs)
- An OpenShift pull secret from the Red Hat Hybrid Cloud Console
- The openshift-install binary for your target version (4.22)
- Ansible Core 2.14+ and the community.general collection
- For KVM deployments: libvirt, QEMU/KVM, and at least 32 GB RAM
- For bare-metal deployments: Redfish or IPMI-capable baseboard management controllers (BMCs)
- Git installed to clone the repository

## Step 1: clone the repository and explore the examples

Start by cloning the openshift-agent-install repository:

    git clone https://github.com/tosin2013/openshift-agent-install.git
    cd openshift-agent-install

The examples/ directory contains 22 reference configurations covering Single Node OpenShift (SNO), 3-node compact clusters, highly available (HA) topologies, disconnected air-gapped deployments, vSphere, Nutanix, bond+VLAN networking, and appliance builds. These are tracked in git for learning and testing.

For your own production deployments, copy a relevant example into site-config/ (which is gitignored) and adapt it. This fork-and-adapt pattern keeps your secrets and environment-specific details out of version control while giving you a proven starting point.

## Step 2: define your cluster in two YAML files

The entire cluster is declared in just two files:

**cluster.yml** defines the cluster identity, networking, and platform:

    cluster_name: "my-cluster"
    base_domain: "example.com"
    ocp_version: "4.22"
    platform_type: baremetal
    control_plane_replicas: 3
    app_node_replicas: 2
    machine_network_cidrs:
      - 192.168.122.0/24
    api_vips:
      - 192.168.122.100
    app_vips:
      - 192.168.122.101

**nodes.yml** defines each machine's identity, network configuration, and BMC access:

    nodes:
      - hostname: master-0
        role: master
        mac_address: "52:54:00:aa:bb:01"
        ip_address: 192.168.122.10
        root_device_hint: /dev/vda
        bmc_address: "192.168.122.1:8000"

That's it. No hand-writing install-config.yaml, no agent-config.yaml, no manually constructing ImageDigestMirrorSet manifests for disconnected environments. The Ansible templating layer handles version-specific generation, including the switch from the deprecated imageContentSources to IDMS for OpenShift 4.20+ disconnected deployments.

## Step 3: generate the bootable ISO

Run the ISO creation script, which orchestrates the Ansible templating and the openshift-install agent create image command:

    ./hack/create-iso.sh my-cluster

Behind the scenes, this reads your cluster.yml and nodes.yml, runs the Ansible playbook to template all required manifests into ~/generated_assets/my-cluster/, and then invokes openshift-install to produce the bootable agent ISO.

## Step 4: deploy with a single command (KVM) or deliver to bare metal

**For KVM lab deployments**, the deploy-connected-full.sh script handles everything in sequence: DNS infrastructure setup, environment validation, ISO generation, DNS entry creation, optional HAProxy configuration, VM creation, and installation monitoring:

    ./hack/deploy-connected-full.sh examples/ha-4.22-standard

**For bare-metal deployments**, deliver the ISO to your servers via Redfish virtual media:

    ./hack/deploy-iso-baremetal.sh site-config/my-cluster/nodes.yml \
      --method redfish \
      --iso ~/generated_assets/my-cluster/agent.x86_64.iso

The framework spins up a temporary HTTP server, mounts the ISO through each node's BMC, and triggers a boot. No USB drives, no PXE infrastructure.

## Tips and best practices

**Start with SNO for learning.** A single-node cluster requires modest resources (8 vCPUs, 32 GB RAM, 130 GB disk) and deploys in under 45 minutes on a KVM host. The examples/sno-4.20-standard configuration is a good starting point.

**Always validate DNS before deploying.** DNS misconfiguration is the number-one cause of ABI install failures. The framework includes automated DNS setup via dnsmasq and validates resolution before creating VMs. For bare-metal environments, ensure your corporate DNS has api., api-int., and *.apps. records configured before booting the ISO.

**Use version boundary enforcement.** The Ansible templates automatically block invalid configurations. If you accidentally set network_type to OpenShiftSDN on a 4.21+ cluster (where it was removed), the tooling catches it before you waste 45 minutes on a doomed install.

**Leverage the external access stack.** For lab clusters that need public reachability, the framework includes HAProxy load balancing, AWS Route53 DNS, and Let's Encrypt TLS certificate orchestration in a single script.

## What's new in OpenShift 4.22 for platform engineers

OpenShift 4.22, released June 9, 2026, brings several capabilities relevant to automated deployment:

- **Kubernetes 1.35** with the latest upstream improvements
- **Two-node OpenShift with fencing** for edge deployments that need HA without a third node
- **ClusterImagePolicy layer verification** for supply chain security enforcement
- **MCP server for AI agents** (Tech Preview) enabling programmatic cluster interaction
- **JobSet Operator** for orchestrating distributed AI training workloads
- **RHEL 10 tech preview** support for next-generation node operating systems

The openshift-agent-install framework already supports 4.22 deployments with the same two-file declarative workflow described above.

## Get started

The fastest path from zero to a running OpenShift 4.22 cluster is:

1. Clone the repository
2. Copy an example configuration into site-config/
3. Customize your cluster.yml and nodes.yml
4. Run a single deploy command

Whether you're building a development lab on KVM or rolling out production clusters on bare metal, declarative automation eliminates the manual toil and version-specific gotchas that make OpenShift deployment error-prone.

Clone the repository and deploy your first cluster today: [https://github.com/tosin2013/openshift-agent-install](https://github.com/tosin2013/openshift-agent-install)
