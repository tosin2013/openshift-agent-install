# Run OpenShift 4.22 in your home lab with KVM and the Agent-Based Installer

You don't need a cloud account to learn Red Hat OpenShift. You don't need a data center budget, either. If you have a spare desktop, a refurbished server, or even a beefy mini PC, you can run a production-grade OpenShift cluster in your home lab — and build the skills that employers are actively hiring for.

I've been helping people stand up OpenShift clusters on bare metal and virtual machines (VMs) for a while now, and the most common blocker I hear isn't technical. It's the assumption that you need expensive infrastructure to get started. You don't. With Kernel-based Virtual Machine (KVM), the Agent-Based Installer (ABI), and an open source helper framework called openshift-agent-install, I can go from zero to a running cluster in about 45 minutes.

Let me show you how.

## Why a home lab matters for your career

Certifications like the Red Hat Certified Specialist in OpenShift Administration and the Certified Kubernetes Administrator (CKA) test hands-on skills, not theory. A home lab gives you a safe, repeatable environment to practice those skills without worrying about cloud bills or breaking a shared environment.

Home labs also let you build muscle memory with the same tooling used in production. The Agent-Based Installer, Redfish baseboard management controller (BMC) emulation, dnsmasq DNS, and NMState networking you'll use in your home lab are the same patterns you'll encounter on physical servers in a data center. When you destroy a cluster and rebuild it three times in a weekend, that's exactly the kind of repetition that makes concepts stick.

## Hardware you probably already have

Here's the good news: a Single Node OpenShift (SNO) deployment needs just 8 vCPUs, 32 GB of RAM, and 130 GB of disk. A modern desktop with a Ryzen 7 or 9 processor and 64 GB of DDR5 handles this easily. So does a refurbished Dell PowerEdge R630 or HP ProLiant — machines you can find for a couple hundred dollars on the used market.

If you want a 3-node compact cluster, aim for 16+ cores and 64 GB or more of RAM. And OpenShift 4.22, released June 9, 2026, introduces two-node clusters with fencing support — a great option if you want high availability but have limited resources.

Don't let hardware gatekeep you. Start with what you have. SNO on a single machine is a perfectly legitimate way to learn.

## How the Agent-Based Installer simplifies everything

The Agent-Based Installer creates a bootable ISO image that contains everything a node needs to install OpenShift — no bootstrap node, no external provisioning infrastructure. Boot the ISO, and the node discovers its peers, forms a cluster, and converges.

The [openshift-agent-install](https://github.com/tosin2013/openshift-agent-install) repository wraps the official `openshift-install` tool with automation that handles the tedious parts: DNS record creation, VM provisioning on KVM, ISO generation, and installation monitoring. It's open source (Apache 2.0), purpose-built for KVM/libvirt as a first-class deployment target, and includes over 20 example configurations you can adapt.

Here's what it gives you:

- **One-time bootstrap** — `bootstrap_env.sh` installs everything: libvirt, Ansible, dnsmasq, command-line interface (CLI) tools, and all dependencies.
- **Automated DNS** — `configure-dnsmasq-entries.sh` reads your cluster configuration and creates all the DNS records. No external DNS infrastructure needed.
- **Single-command deployment** — `deploy-connected-full.sh` orchestrates the entire flow: DNS setup, validation, ISO generation, VM creation, and installation monitoring.
- **Full lifecycle** — Create, deploy, monitor, access, destroy, repeat. Tear it all down with `destroy-on-kvm.sh` and start fresh.
- **Redfish emulation** — The sushy-tools service emulates BMC management, so you learn the same server management patterns used on physical hardware.

## The deployment workflow

You can deploy with a single orchestration command, or walk through each step individually to understand what's happening. Here's the step-by-step path:

1. **Bootstrap your environment** (one-time, with sudo): `bootstrap_env.sh` installs all prerequisites.
2. **Validate** everything is ready: `validate_env.sh` confirms your system is configured correctly.
3. **Configure DNS**: `configure-dnsmasq-entries.sh add cluster.yml` creates all required DNS records from your cluster configuration.
4. **Generate the ISO**: `create-iso.sh sno-4.20-standard` builds the installer image.
5. **Deploy VMs**: `deploy-on-kvm.sh nodes.yml --redfish` creates the virtual machine and boots it from the ISO.
6. **Start the reboot watcher**: `watch-and-reboot-kvm-vms.sh nodes.yml &` runs in the background. This step is required — ABI VMs shut down after writing the operating system to disk but don't self-reboot on KVM. The watcher detects this and restarts them automatically.
7. **Monitor the installation**: `openshift-install agent wait-for install-complete` lets you watch the cluster converge in real time.
8. **Access your cluster**: Export the KUBECONFIG file and run `oc get nodes`. You're in.

Or skip straight to `deploy-connected-full.sh examples/sno-4.20-standard` and let it handle everything.

### A few things to know

I want to be upfront about some caveats so you don't hit surprises:

- The reboot watcher (`watch-and-reboot-kvm-vms.sh`) must run in the background during installation. If you skip it, your VMs won't boot back up after the disk write phase.
- Libvirt's dnsmasq doesn't support wildcard DNS entries, so `*.apps` records aren't available. The tooling adds common application hostnames individually instead.
- If you need VLAN networking, the VyOS router script (`vyos-router.sh`) requires about 30 minutes of manual configuration through the Cockpit web console — it's not fully automated. That said, a simple flat-network SNO deployment doesn't need VyOS at all.

## Skills you'll build

Running OpenShift in your home lab builds real, transferable skills:

- **Cluster lifecycle management** — Deploy, upgrade, and tear down clusters on demand.
- **Bare metal patterns** — Redfish BMC management, NMState networking, and PXE-like boot workflows.
- **DNS and networking** — Configure dnsmasq, manage DNS records, and troubleshoot name resolution.
- **Infrastructure as code** — Declarative YAML configurations, Ansible playbooks, and repeatable automation.
- **Day-2 operations** — Once your cluster is running, practice deploying workloads, configuring storage, and managing operators.

OpenShift 4.22 ships with Kubernetes 1.35 and includes an MCP server for AI agent access — a fun experiment if you're exploring how AI tooling interacts with cluster APIs. It also adds Red Hat Enterprise Linux 10 as a tech preview for node operating systems.

## Get started

Clone the repository, bootstrap your environment, and deploy your first cluster this weekend:

[https://github.com/tosin2013/openshift-agent-install](https://github.com/tosin2013/openshift-agent-install)

Start with the `examples/sno-4.20-standard` configuration as your template, adjust it for your network, and run the deployment. When something breaks — and it will, because that's how you learn — destroy it and try again. That's the whole point of a home lab.

The barrier to learning OpenShift isn't infrastructure. It's just deciding to start.
