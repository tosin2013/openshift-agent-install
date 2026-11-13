# AI Skills Catalog — openshift-agent-install

This repository includes a **portable AI skills system** for Claude Code, Cursor, and GitHub Copilot.
Skills teach AI assistants repeatable, validated procedures for OpenShift Agent-Based Installer
deployments. They are plain markdown files — readable and followable without any AI tool.

**Quick install:**
```bash
./hack/skills/install-skills.sh --all
```

For full step-by-step usage instructions, see [hack/skills/README.md](hack/skills/README.md).

---

## All Skills (13)

### Core Deployment Skills

| Skill | Description | Key Scripts |
|-------|-------------|-------------|
| `bootstrap-environment` | Install packages, configure KVM/libvirt, set up dnsmasq on a fresh RHEL host | `e2e-tests/bootstrap_env.sh`, `e2e-tests/validate_env.sh` |
| `create-cluster-config` | Author cluster.yml and nodes.yml for SNO, 3-node compact, or HA deployments | `hack/validate-kvm-examples.sh`, `hack/validate-baremetal-env.sh` |
| `deploy-cluster-kvm` | Full lifecycle KVM deployment: DNS setup, ISO generation, VM creation, install monitoring (7 phases) | `hack/deploy-connected-full.sh`, `hack/deploy-ha-full.sh` |
| `deploy-cluster-baremetal` | Deliver agent ISO to physical servers via Redfish virtual media or IPMI | `hack/deploy-iso-baremetal.sh`, `hack/validate-baremetal-env.sh` |
| `destroy-cluster` | Tear down KVM VMs, disk images, DNS entries, and generated assets | `hack/destroy-on-kvm.sh`, `e2e-tests/delete_e2e.sh` |

### Networking and Infrastructure Skills

| Skill | Description | Key Scripts |
|-------|-------------|-------------|
| `configure-external-access` | Set up HAProxy forwarding, Route53 public DNS, and Let's Encrypt TLS certificates | `hack/configure-external-access.sh` |
| `deploy-vyos-router` | Deploy VyOS virtual router for VLAN networking (requires manual Cockpit console steps) | `hack/vyos-router.sh` |
| `troubleshoot-dns` | Diagnose and fix DNS issues that block deployment or cluster access | `hack/verify-dns-resolution.sh`, `hack/configure-dnsmasq-entries.sh` |
| `setup-sushy-emulator` | Configure Redfish BMC emulation for KVM VMs using sushy-tools | `hack/configure-sushy-unix.sh`, `hack/test-libvirt-ssh.sh` |

### Validation and Testing Skills

| Skill | Description | Key Scripts |
|-------|-------------|-------------|
| `validate-and-compare-manifests` | Generate manifests for multiple OCP versions, diff them, and validate against deployment standards | `hack/generate-version-manifests.sh`, `hack/compare-version-manifests.sh`, `hack/validate-deployment-standards.sh` |
| `generate-acm-hosts` | Convert nodes.yml into BareMetalHost and Secret manifests for RHACM/Metal3 hub deployment | `hack/generate_bmc_acm_hosts.py` |
| `run-e2e-tests` | Execute the full E2E test suite (ISO + VMs + install) or version validation tests (no VMs) | `e2e-tests/run_e2e.sh`, `e2e-tests/test_version_validation.sh` |
| `pre-release-validation` | Orchestrate all validation phases and generate a markdown evidence report | `hack/pre-release-validation.sh` |

---

## How Skills Chain Together

Skills are designed to be used in sequence. The typical KVM deployment flow:

```
bootstrap-environment  →  deploy-vyos-router (if VLAN lab)
        ↓
create-cluster-config
        ↓
validate-and-compare-manifests (optional pre-deploy version check)
        ↓
deploy-cluster-kvm  or  deploy-cluster-baremetal
        ↓
configure-external-access (optional)
        ↓
destroy-cluster (teardown or redeploy)
```

For testing and release:
```
run-e2e-tests  ──────────────────────────┐
validate-and-compare-manifests  ─────────┤→  pre-release-validation
                                         │   (orchestrates both)
                                         └────────────────────────
```

For RHACM hub-based deployment:
```
create-cluster-config  →  setup-sushy-emulator (if KVM)
        ↓
generate-acm-hosts  →  apply to hub cluster  →  hub runs deploy-cluster-baremetal
```

If DNS fails at any point: use `troubleshoot-dns`.

---

## Installing Skills

```bash
# Install for all supported IDEs at once (recommended)
./hack/skills/install-skills.sh --all

# Or install per-IDE:
./hack/skills/install-skills.sh --claude-code   # Claude Code (updates CLAUDE.md)
./hack/skills/install-skills.sh --cursor        # Cursor IDE (symlinks into .cursor/skills/)
./hack/skills/install-skills.sh --copilot       # GitHub Copilot (generates copilot-instructions.md)

# After creating new skills, re-run to pick them up:
./hack/skills/install-skills.sh --all
```

Skills are stored canonically in `hack/skills/<name>/SKILL.md`. The install script is idempotent.

---

## Red Hat AI Skills Catalog

Red Hat maintains an official AI Skills Catalog at:

**https://catalog.redhat.com/en/ai/skills**

The catalog includes skill packs for Claude Code and Cursor covering multiple Red Hat products.

### Official OpenShift Skill vs. This Repository

The official **"Plugin for Red Hat OpenShift"** skill covers:
- OpenShift Cluster Manager (OCM) operations
- ROSA (Red Hat OpenShift Service on AWS) provisioning
- ARO (Azure Red Hat OpenShift) provisioning
- Day-2 managed service operations

**What it does not cover**: Agent-Based Installer (ABI) deployments to bare metal or KVM — which
is precisely what this repository automates. The two are complementary:

| Task | Use |
|------|-----|
| Provision ROSA or ARO | Official catalog "Plugin for Red Hat OpenShift" |
| Self-managed OpenShift via ABI on bare metal | This repository |
| OpenShift on KVM for development/lab | This repository |
| RHACM hub-managed spoke clusters | This repository (`generate-acm-hosts` skill) |

### Accessing Official Skills

The Red Hat AI Skills Catalog is not publicly downloadable from GitHub. To access:
1. Visit https://catalog.redhat.com/en/ai/skills
2. Contact your Red Hat account team

A public contribution pathway is listed as "coming soon" as of late 2025.

---

## Contributing a New Skill

See [hack/skills/README.md](hack/skills/README.md) for the full authoring guide and quality checklist.

**Write a skill when** the task:
- Has 3+ steps requiring sequencing and judgment
- Is specific to this repository's deployment patterns
- Has observable validation criteria
- Is performed repeatedly by multiple users
- Has failure modes worth documenting

**Steps**:
1. Create `hack/skills/<your-skill-name>/SKILL.md`
2. Write YAML frontmatter (`name`, `description`, `triggers`)
3. Follow the section structure: When to Use / Prerequisites / Procedure / Validation Criteria / Related Skills / Common Failure Modes / Key Files
4. Re-run `./hack/skills/install-skills.sh --all`
5. Update this file (SKILLS.md) and [hack/skills/README.md](hack/skills/README.md) tables
6. Submit a PR — see [CONTRIBUTING.md](CONTRIBUTING.md)

### Toward the Red Hat AI Skills Catalog

When Red Hat opens the catalog contribution pathway:
- Skills most likely to qualify: `create-cluster-config`, `deploy-cluster-baremetal`, `validate-and-compare-manifests`
- Requirements will likely include: standardized metadata format, compliance review, Red Hat branding attribution
- Monitor https://catalog.redhat.com/en/ai/skills for contribution guidelines and open a repository issue to coordinate submission
