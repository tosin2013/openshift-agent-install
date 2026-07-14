## 5 reasons the Agent-Based Installer will change how you deploy OpenShift 4.22

If you've ever spent an afternoon debugging a failed Red Hat OpenShift installation only to discover a DNS typo or a misconfigured network bond, you know the pain. The Agent-Based Installer (ABI) already simplified OpenShift deployments by removing the bootstrap node, but what if you could wrap that workflow in declarative automation that fits into your existing GitOps practices?

That's the idea behind the [openshift-agent-install](https://github.com/tosin2013/openshift-agent-install) framework. It's a helper layer on top of Red Hat's standard `openshift-install` tool that turns cluster provisioning into a two-file, git-tracked, repeatable process. With OpenShift 4.22 now available — bringing Kubernetes 1.35, two-node clusters with fencing, and a Model Context Protocol (MCP) server for AI agents in Tech Preview — I wanted to share why this approach matters for DevOps engineers and site reliability engineers (SREs) who manage OpenShift at scale.

Here are five reasons to try it.

## 1. Your entire cluster is two YAML files in a git repo

Traditional OpenShift deployments require you to hand-craft `install-config.yaml` and `agent-config.yaml`, often copying from documentation and tweaking values by hand. This creates tribal knowledge — the configuration lives in someone's head or a wiki page that's already out of date.

The openshift-agent-install framework replaces that with two declarative files: `cluster.yml` for your cluster topology (version, virtual IPs (VIPs), networking, platform type) and `nodes.yml` for per-node details (MAC addresses, IP addresses, NMState network configuration, root device hints). An Ansible playbook templates these into the manifests that `openshift-install` expects, handling version-specific differences automatically. For example, it uses ImageDigestMirrorSet (IDMS) manifests for OpenShift 4.20+ disconnected installs and blocks the removed OpenShiftSDN network type for 4.21+.

Because everything is in git, your cluster configuration is pull-request reviewable and diffable. A peer can look at a two-line diff and approve a VIP change instead of comparing two walls of YAML.

```yaml
# cluster.yml — the essentials
cluster_name: prod-edge-01
base_domain: example.com
ocp_version: "4.22"
control_plane_replicas: 3
app_node_replicas: 2
api_vips:
  - 10.1.50.100
app_vips:
  - 10.1.50.101
platform_type: baremetal
network_type: OVNKubernetes
```

## 2. One ISO, no bootstrap node

The Agent-Based Installer bakes the control plane bootstrap into the ISO itself. You don't need a separate bootstrap virtual machine (VM), which means fewer moving parts and fewer failure modes. The framework wraps this into a single command:

```bash
./hack/create-iso.sh prod-edge-01
```

That command reads your `cluster.yml` and `nodes.yml`, runs the Ansible templating, calls `openshift-install agent create image`, and produces a bootable ISO in `~/generated_assets/prod-edge-01/`. For bare metal servers, the framework includes a Redfish virtual media delivery script that spins up a temporary HTTP server, mounts the ISO through your baseboard management controller (BMC), and boots the node — no USB drives, no PXE infrastructure.

```bash
./hack/deploy-iso-baremetal.sh site-config/prod-edge-01/nodes.yml \
  --method redfish --iso ~/generated_assets/prod-edge-01/agent.x86_64.iso
```

This matters for edge deployments and remote sites where you can't walk up to the server room.

## 3. Same workflow from single-node OpenShift to HA production

One of the most frustrating aspects of OpenShift deployment is that single-node OpenShift (SNO), compact three-node, and full high-availability (HA) clusters often feel like completely different workflows. With this framework, the process is identical — you change the YAML, not the toolchain.

The repository includes 22 example configurations covering every topology: SNO, three-node compact, HA with workers, disconnected air-gapped environments, vSphere, Nutanix, bonded interfaces with tagged VLANs, and even appliance builds. Each example is a self-contained directory with its own `cluster.yml` and `nodes.yml` that you can fork and adapt.

Want to go from a lab SNO to a production HA cluster? Change `control_plane_replicas` from 1 to 3, add worker entries to `nodes.yml`, and set your production VIPs. The rest of the workflow — ISO creation, manifest generation, deployment — stays the same.

## 4. DNS and network config automated

Ask any OpenShift administrator what causes the most installation failures, and the answer is almost always DNS. Missing `api.<cluster>.<domain>` records, incorrect wildcard entries for `*.apps.<cluster>.<domain>`, or nodes that can't resolve the rendezvous IP during bootstrap.

The framework attacks this problem directly. Running `setup-dnsmasq.sh` installs and configures dnsmasq as a lightweight DNS server. Then `configure-dnsmasq-entries.sh` reads your `cluster.yml` and automatically creates every DNS record your cluster needs — API, API internal, wildcard application routes, and per-node entries.

```bash
sudo ./hack/setup-dnsmasq.sh
sudo ./hack/configure-dnsmasq-entries.sh add site-config/prod-edge-01/cluster.yml
```

For networking, each node's configuration in `nodes.yml` uses NMState — the same declarative network API that OpenShift itself uses. You define VLANs, bonds, and bond-plus-VLAN combinations as structured YAML instead of scripting `nmcli` commands. The framework includes working examples for every common pattern: single NIC, dual NIC, VLAN-tagged interfaces, active-backup bonds, and LACP bonds with tagged VLANs.

## 5. Reproducible environments with end-to-end automation

When I'm standing up lab environments for testing or demos, I don't want a 12-step runbook. I want a single command that either succeeds or tells me exactly what's wrong.

The framework provides three scripts that form an end-to-end (E2E) pipeline. First, `bootstrap_env.sh` handles one-time host setup — installing packages, configuring libvirt, downloading the `openshift-install` binary. Second, `validate_env.sh` runs pre-flight checks to catch problems before you waste time on a doomed deployment. Third, the orchestrator brings it all together:

```bash
./hack/deploy-connected-full.sh examples/sno-4.20-standard
```

That single command configures DNS, validates the environment, generates the ISO, deploys VMs with appropriate sizing, and monitors the installation to completion. For KVM-based labs, it handles VM creation with correct CPU, memory, and disk sizing, dual-NIC configuration, and even a Redfish emulator through sushy-tools so you can test bare metal workflows locally.

The `examples/` directory is git-tracked for learning and continuous integration (CI). The `site-config/` directory is gitignored for your real deployments. Fork the pattern that's closest to your needs, adjust it, and you have a reproducible deployment you can hand off to anyone on your team.

## Get started

The openshift-agent-install framework doesn't replace Red Hat's installer — it makes it easier to use correctly and consistently. Whether you're deploying a single-node cluster at an edge site or a full HA cluster in your data center, the workflow is the same: define your cluster in YAML, generate an ISO, and deploy.

Clone the repository, pick the example that matches your topology, and try a deployment:

```bash
git clone https://github.com/tosin2013/openshift-agent-install.git
cd openshift-agent-install
ls examples/
```

The 22 example configurations give you a working starting point for nearly every scenario. If you're running OpenShift 4.22, the framework already supports the new version — just set `ocp_version: "4.22"` in your `cluster.yml` and go.

[Clone the repo on GitHub](https://github.com/tosin2013/openshift-agent-install) and start deploying OpenShift the declarative way.
