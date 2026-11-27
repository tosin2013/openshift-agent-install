# OpenShift Agent Based Installer Helper

Automated deployment tooling for OpenShift clusters using the Agent-Based Installer (ABI).
Supports **bare metal, vSphere, Nutanix AHV, and KVM** in SNO, 3-node compact, and HA configurations across OpenShift 4.15–5.x.

📚 **Full documentation**: https://tosin2013.github.io/openshift-agent-install/

---

## Choose Your Path

| | 🔩 Bare Metal Production | 🖥️ KVM Development |
|---|---|---|
| **Goal** | Deploy real production clusters | Learn, test, and validate configs |
| **DNS** | Corporate DNS (BIND / Infoblox / AD) | dnsmasq on `192.168.122.1` |
| **BMC** | Real iDRAC / iLO / IPMI | sushy Redfish emulator |
| **ISO delivery** | `./hack/deploy-iso-baremetal.sh` | `./hack/deploy-on-kvm.sh` |
| **Environment check** | `./hack/validate-baremetal-env.sh` | `./e2e-tests/validate_env.sh` |
| **Start here** | [Bare Metal Tutorial →][bm] | [Developer Guide →][dev] |

**Migrating KVM config to production?** → [Fork & Adapt Checklist][fork]

---

## Quick Start

```bash
# 1. Bootstrap environment (installs packages, DNS, libvirt)
sudo ./e2e-tests/bootstrap_env.sh

# 2. Download OpenShift CLI tools
./download-openshift-cli.sh 5.0        # or 4.22, 4.21, etc.
sudo cp ./bin/* /usr/local/bin/

# 3. Create your cluster config (copy an example)
cp -r examples/sno-5.0-standard site-config/my-cluster
# Edit site-config/my-cluster/cluster.yml and nodes.yml

# 4. Generate the agent ISO
export SITE_CONFIG_DIR=site-config
./hack/create-iso.sh my-cluster

# 5. Deploy and monitor
./hack/deploy-on-kvm.sh site-config/my-cluster/nodes.yml          # KVM
# ./hack/deploy-iso-baremetal.sh site-config/my-cluster/nodes.yml  # Bare metal
./bin/openshift-install agent wait-for install-complete \
    --dir ~/generated_assets/my-cluster/ --log-level=info
```

---

## Post-Install (KVM Only)

Run these **once after `install-complete`**, before deploying workloads:

```bash
./hack/harden-olm.sh                    # Fix OLM probes + apply etcd disk tuning
INSTALL_API_CERT=n ./hack/configure-letsencrypt-certs.sh   # Ingress cert only
EXTERNAL_IP=<ip> ./hack/configure-haproxy-forwarder.sh site-config/my-cluster/cluster.yml
./hack/validate-kvm-deployment.sh       # Verify everything is healthy
```

> ⚠️ **Do not apply the API server cert on KVM** — it triggers a 1-2 hour kube-apiserver rollout cascade. Ingress cert only is sufficient. See [Lessons Learned][lessons].

---

## Example Configurations

| Config | Pattern |
|--------|---------|
| `examples/sno-5.0-standard/` | SNO on OCP 5.0 (RHCOS 10) |
| `examples/ha-5.0-standard/` | HA on OCP 5.0 |
| `examples/cnv-5.0-single-bond0-vlan/` | OpenShift Virtualization, bond0 + VLAN |
| `examples/sno-4.20-standard/` | SNO on OCP 4.20 |
| `examples/ha-4.21-disconnected/` | HA air-gapped on OCP 4.21 |
| `examples/baremetal-example/` | Bare metal HA with BMC |
| `examples/nutanix-sno/` | SNO on Nutanix AHV |

All 23+ examples: `ls examples/`

---

## Supported Versions

| OCP | Status | Notes |
|-----|--------|-------|
| 5.0.x | ✅ Current | RHCOS 10, x86-64-v3+ required |
| 4.22.x | ✅ Supported | — |
| 4.21.x | ✅ Supported | OpenShiftSDN removed — use OVNKubernetes |
| 4.20.x | ⚠️ Maintenance | — |
| 4.18.x | ⚠️ EUS | — |
| ≤ 4.17 | ❌ EOL | — |

---

## AI Skills

This repo includes step-by-step skills for Claude Code, Cursor, and GitHub Copilot:

```bash
./hack/skills/install-skills.sh --all   # Install into your IDE
./hack/harness.sh                       # Interactive shell menu (no AI needed)
```

Trigger phrases: `"deploy on KVM"`, `"DNS not resolving"`, `"create cluster config"`, etc. See [SKILLS.md](SKILLS.md).

---

## Documentation

| | |
|---|---|
| 📖 Full docs | https://tosin2013.github.io/openshift-agent-install/ |
| 🔩 Bare metal tutorial | [/bare-metal-tutorial][bm] |
| 🖥️ KVM developer guide | [/developer-guide][dev] |
| ⚙️ Configuration reference | [/configuration-guide][config] |
| 🔀 Fork & adapt checklist | [/fork-and-adapt-checklist][fork] |
| 🌐 Platform guides | [/platform-guides][platforms] |
| 🔧 BMC management | [/bmc-management][bmc] |
| 🔍 Troubleshooting | [/troubleshooting][ts] |
| 📋 Lessons learned (KVM) | [deploy-cluster-kvm skill][lessons] |

---

## License

Apache 2.0 — see [LICENSE](LICENSE).

[bm]: https://tosin2013.github.io/openshift-agent-install/bare-metal-tutorial
[dev]: https://tosin2013.github.io/openshift-agent-install/developer-guide
[fork]: https://tosin2013.github.io/openshift-agent-install/fork-and-adapt-checklist
[config]: https://tosin2013.github.io/openshift-agent-install/configuration-guide
[platforms]: https://tosin2013.github.io/openshift-agent-install/platform-guides
[bmc]: https://tosin2013.github.io/openshift-agent-install/bmc-management
[ts]: https://tosin2013.github.io/openshift-agent-install/troubleshooting
[lessons]: hack/skills/deploy-cluster-kvm/SKILL.md
