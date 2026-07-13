# AI Task Skills

This directory contains portable AI task skills for the openshift-agent-install repository.
Each skill documents a repeatable multi-step procedure that an AI assistant can follow.

## Installation

Skills must be installed into your IDE to be discoverable by AI assistants:

```bash
# Install for all supported IDEs
./hack/skills/install-skills.sh --all

# Install for a specific IDE
./hack/skills/install-skills.sh --cursor      # Cursor IDE
./hack/skills/install-skills.sh --claude-code  # Claude Code
./hack/skills/install-skills.sh --copilot     # GitHub Copilot

# List available skills
./hack/skills/install-skills.sh --list

# Remove all installations
./hack/skills/install-skills.sh --uninstall
```

## Available Skills

| Skill | Description |
|-------|-------------|
| `create-cluster-config` | Author cluster.yml and nodes.yml for SNO/3-node/HA deployments |
| `deploy-cluster-kvm` | Full lifecycle KVM deployment (7 phases) |
| `deploy-cluster-baremetal` | Bare metal ISO delivery via Redfish/IPMI |
| `configure-external-access` | HAProxy + Route53 + Let's Encrypt for external access |
| `deploy-vyos-router` | VyOS virtual router with manual Cockpit configuration |
| `troubleshoot-dns` | DNS diagnostic and repair procedures |

## How It Works

Each skill is a markdown file (`SKILL.md`) with:
1. **YAML frontmatter** - metadata (name, description, trigger patterns)
2. **Trigger conditions** - when the AI should activate this skill
3. **Prerequisites** - what must be true before starting
4. **Step-by-step procedure** - exact commands and decisions
5. **Validation criteria** - how to verify success
6. **Failure modes** - common issues and fixes

The install script maps these into IDE-specific formats:
- **Cursor**: Symlinks into `.cursor/skills/<name>/SKILL.md`
- **Claude Code**: Appends references to `CLAUDE.md`
- **GitHub Copilot**: Generates `.github/copilot-instructions.md`

## Adding a New Skill

1. Create a directory: `hack/skills/<skill-name>/`
2. Write `SKILL.md` with the required frontmatter:

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
...
```

3. Re-run the install script: `./hack/skills/install-skills.sh --all`

## Design Principles

- **Portable**: Skills are plain markdown, not IDE-specific
- **Single source of truth**: Canonical files in `hack/skills/`, deployed elsewhere
- **Idempotent**: Install script can run repeatedly without side effects
- **Git-friendly**: Source is tracked; generated outputs (`.cursor/skills/`) can be gitignored
