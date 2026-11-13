# AI Task Skills

This directory contains portable AI task skills for the openshift-agent-install repository.
Each skill documents a repeatable multi-step procedure that an AI assistant can follow.

Skills are plain markdown files. They work with **Claude Code**, **Cursor**, and **GitHub Copilot**,
and are fully readable without any AI tool — just open the SKILL.md and follow it manually.

---

## Step 1: Install Skills into Your IDE

Skills must be installed before your AI assistant can discover them automatically:

```bash
# Install for all supported IDEs at once (recommended)
./hack/skills/install-skills.sh --all

# Or install for a specific IDE
./hack/skills/install-skills.sh --cursor       # Cursor IDE
./hack/skills/install-skills.sh --claude-code  # Claude Code
./hack/skills/install-skills.sh --copilot      # GitHub Copilot

# See what will be installed
./hack/skills/install-skills.sh --list

# Remove all installed skills
./hack/skills/install-skills.sh --uninstall
```

Re-run after adding new skills — the install script is idempotent.

---

## Step 2: Activate a Skill

Once installed, say or type a trigger phrase in your AI assistant's chat:

| You say / type | Skill activated |
|----------------|-----------------|
| "bootstrap environment" or "set up host" | `bootstrap-environment` |
| "create a new cluster config" or "write cluster.yml" | `create-cluster-config` |
| "deploy on KVM" or "deploy OpenShift" | `deploy-cluster-kvm` |
| "deploy to bare metal" or "redfish deploy" | `deploy-cluster-baremetal` |
| "destroy cluster" or "tear down cluster" | `destroy-cluster` |
| "deploy VyOS" or "VLAN networking setup" | `deploy-vyos-router` |
| "external access" or "configure HAProxy" | `configure-external-access` |
| "DNS not resolving" or "NXDOMAIN" | `troubleshoot-dns` |
| "setup sushy" or "redfish emulator" | `setup-sushy-emulator` |
| "compare manifests" or "validate manifests" | `validate-and-compare-manifests` |
| "generate ACM hosts" or "BareMetalHost" | `generate-acm-hosts` |
| "run e2e tests" or "automated testing" | `run-e2e-tests` |
| "pre-release validation" or "cut a release" | `pre-release-validation` |

The AI assistant reads the full SKILL.md file and follows the procedure step by step.

---

## Step 3: Follow the Skill Procedure

Each skill's procedure is structured to be followed sequentially:

1. The assistant confirms **prerequisites** are met before starting
2. It runs commands from the **Procedure** section in order
3. At the end it checks the **Validation Criteria** to confirm success
4. If something goes wrong it consults the **Common Failure Modes** table

You can ask the assistant to pause at any step, explain what a command does,
or skip optional steps.

---

## Walkthrough: First-Time KVM Deployment

Here is a complete scenario using skills from start to finish.

**Goal**: Deploy a Single Node OpenShift cluster on a fresh KVM host.

**Step 1 — Bootstrap the host** (once per machine):

Type: `bootstrap environment`

The assistant runs `sudo ./e2e-tests/bootstrap_env.sh` and then
`./e2e-tests/validate_env.sh` to confirm the host is ready.

**Step 2 — Set up VLAN networking** (if needed):

Type: `deploy VyOS router`

The assistant walks you through `./hack/vyos-router.sh` including the required
manual Cockpit console steps. This step is only needed if your cluster uses
VLAN-tagged interfaces (192.168.50.x network).

**Step 3 — Create cluster configuration**:

Type: `create a new cluster config for SNO`

The assistant selects an appropriate example from `examples/`, guides you through
writing `cluster.yml` and `nodes.yml` for your environment, and validates both files.

**Step 4 — Deploy the cluster**:

Type: `deploy on KVM`

The assistant runs DNS setup, ISO generation, VM creation, and monitors the
installation to completion (bootstrap ~10 min, full install ~40 min for SNO).

**Step 5 — Clean up** (when done):

Type: `destroy cluster`

The assistant removes VMs, disks, and DNS entries cleanly.

---

## Reading Skills Manually (No IDE Required)

Skills are plain markdown files. You can read and follow them without any AI tool:

```bash
# Read a specific skill
cat hack/skills/deploy-cluster-kvm/SKILL.md

# Browse all skills
ls hack/skills/

# Open a skill in your editor
vi hack/skills/create-cluster-config/SKILL.md
```

All scripts documented in the skills work independently — the skills just provide
structured guidance for following the same steps an experienced operator would take.

---

## Available Skills (13)

| Skill | Description |
|-------|-------------|
| `bootstrap-environment` | Install packages, configure KVM/libvirt, set up dnsmasq on a fresh RHEL host |
| `create-cluster-config` | Author cluster.yml and nodes.yml for SNO, 3-node compact, or HA deployments |
| `deploy-cluster-kvm` | Full lifecycle KVM deployment: DNS, ISO, VMs, install monitoring (7 phases) |
| `deploy-cluster-baremetal` | Deliver agent ISO to physical servers via Redfish virtual media or IPMI |
| `destroy-cluster` | Tear down KVM VMs, disk images, DNS entries, and generated assets |
| `deploy-vyos-router` | VyOS virtual router with VLAN networking (requires manual Cockpit steps) |
| `configure-external-access` | HAProxy + Route53 + Let's Encrypt TLS for external cluster access |
| `troubleshoot-dns` | Diagnose and fix DNS issues that block deployment or access |
| `setup-sushy-emulator` | Configure Redfish BMC emulation for KVM VMs using sushy-tools |
| `validate-and-compare-manifests` | Generate manifests for multiple OCP versions, diff them, validate with LLM |
| `generate-acm-hosts` | Convert nodes.yml into BareMetalHost and Secret manifests for RHACM/Metal3 |
| `run-e2e-tests` | Execute the full E2E test suite (ISO + VMs + install) or version validation |
| `pre-release-validation` | Orchestrate all validation phases and generate a release evidence report |

---

## How Skills Relate to Each Other

Skills are designed to chain together. Each SKILL.md has a "Related Skills" section
showing what comes before and after it. The high-level chain:

```
bootstrap-environment → deploy-vyos-router → create-cluster-config
                                                      ↓
                        validate-and-compare-manifests (optional pre-deploy check)
                                                      ↓
                             deploy-cluster-kvm  or  deploy-cluster-baremetal
                                                      ↓
                             configure-external-access (optional)
                                                      ↓
                                              destroy-cluster
```

If DNS fails at any stage, use `troubleshoot-dns`.
For release testing: `run-e2e-tests` → `pre-release-validation`.
For RHACM hub: `generate-acm-hosts` feeds into hub-orchestrated deployment.

---

## How It Works

```
hack/skills/                          ← Source of truth (tracked in git)
  ├── install-skills.sh               ← Installer script
  ├── README.md                       ← This file
  ├── bootstrap-environment/SKILL.md
  ├── create-cluster-config/SKILL.md
  ├── deploy-cluster-kvm/SKILL.md
  ├── deploy-cluster-baremetal/SKILL.md
  ├── destroy-cluster/SKILL.md
  ├── deploy-vyos-router/SKILL.md
  ├── configure-external-access/SKILL.md
  ├── troubleshoot-dns/SKILL.md
  ├── setup-sushy-emulator/SKILL.md
  ├── validate-and-compare-manifests/SKILL.md
  ├── generate-acm-hosts/SKILL.md
  ├── run-e2e-tests/SKILL.md
  └── pre-release-validation/SKILL.md

.cursor/skills/                       ← Cursor: symlinks to above
CLAUDE.md                             ← Claude Code: skill references appended
.github/copilot-instructions.md       ← GitHub Copilot: generated index
```

The install script:
1. Discovers all `SKILL.md` files in `hack/skills/`
2. Parses the YAML frontmatter (name, description, triggers)
3. Installs into the target IDE's expected location
4. Is idempotent — safe to run multiple times

---

## Adding a New Skill

1. Create a directory: `hack/skills/<skill-name>/`
2. Write `SKILL.md` with the required structure:

```markdown
---
name: Human-Readable Name
description: One-line description of what this skill does
triggers:
  - phrase that would trigger this skill
  - another trigger phrase
---

# Skill Title

## When to Use This Skill

Activate when a user wants to:
- ...

## Prerequisites

- ...

## Procedure

### Step 1: ...

```bash
# concrete command with example
```

## Validation Criteria

The task is complete when:
1. ...

## Related Skills

- **Before this skill**: ...
- **After this skill**: ...

## Common Failure Modes

| Symptom | Cause | Fix |
|---------|-------|-----|
| ... | ... | ... |

## Key Files

- `path/to/script.sh` - what it does
```

3. Re-run the install script: `./hack/skills/install-skills.sh --all`
4. Update `SKILLS.md` (root level) and this README with the new skill
5. Submit a PR — see [CONTRIBUTING.md](../../CONTRIBUTING.md)

---

## Design Principles

- **Portable**: Skills are plain markdown, not IDE-specific
- **Single source of truth**: Canonical files in `hack/skills/`, deployed to IDEs
- **Chained**: Each skill has a "Related Skills" section showing what comes before and after
- **Idempotent**: The install script can run repeatedly without side effects
- **Manual-compatible**: Every skill can be read and followed without an AI tool
- **Git-friendly**: Source is tracked; generated outputs (`.cursor/skills/`) can be gitignored
