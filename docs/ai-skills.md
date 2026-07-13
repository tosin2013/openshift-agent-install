---
layout: default
title: AI Task Skills
parent: How-to Guides
nav_order: 20
---

# AI Task Skills

This repository includes a portable **AI task skills** system that provides AI coding assistants with structured procedures for common deployment tasks. Skills work across multiple IDEs and AI tools.

## What Are Skills?

Skills are structured markdown documents that teach AI assistants how to perform repository-specific tasks. Each skill contains:

- **Trigger conditions** -- when the AI should activate the skill
- **Prerequisites** -- what must be true before starting
- **Step-by-step procedure** -- exact commands and decision points
- **Validation criteria** -- how to verify success
- **Failure modes** -- common issues and their fixes

## Available Skills

| Skill | Description | Typical Trigger |
|-------|-------------|-----------------|
| `create-cluster-config` | Author cluster.yml and nodes.yml for SNO/3-node/HA deployments | "Create a new cluster config" |
| `deploy-cluster-kvm` | Full lifecycle KVM deployment (7 phases) | "Deploy a cluster on KVM" |
| `deploy-cluster-baremetal` | Bare metal ISO delivery via Redfish/IPMI | "Deploy to bare metal servers" |
| `configure-external-access` | HAProxy + Route53 + Let's Encrypt | "Set up external access" |
| `deploy-vyos-router` | VyOS virtual router with manual steps | "Deploy VyOS router" |
| `troubleshoot-dns` | DNS diagnostic and repair procedures | "DNS isn't resolving" |

## Installation

Skills are stored in `hack/skills/` and must be installed into your IDE to be discoverable:

```bash
# Install for all supported IDEs
./hack/skills/install-skills.sh --all

# Or install for a specific IDE
./hack/skills/install-skills.sh --cursor       # Cursor IDE
./hack/skills/install-skills.sh --claude-code   # Claude Code
./hack/skills/install-skills.sh --copilot      # GitHub Copilot

# List available skills
./hack/skills/install-skills.sh --list

# Remove all installations
./hack/skills/install-skills.sh --uninstall
```

## Supported IDEs

| IDE | Install Flag | How Skills Are Delivered |
|-----|-------------|------------------------|
| **Cursor** | `--cursor` | Symlinks into `.cursor/skills/<name>/SKILL.md` |
| **Claude Code** | `--claude-code` | Appends skill references to `CLAUDE.md` |
| **GitHub Copilot** | `--copilot` | Generates `.github/copilot-instructions.md` |

## How It Works

```
hack/skills/                          ← Source of truth (tracked in git)
  ├── install-skills.sh               ← Installer script
  ├── README.md
  ├── create-cluster-config/SKILL.md
  ├── deploy-cluster-kvm/SKILL.md
  ├── deploy-cluster-baremetal/SKILL.md
  ├── configure-external-access/SKILL.md
  ├── deploy-vyos-router/SKILL.md
  └── troubleshoot-dns/SKILL.md

.cursor/skills/                       ← Generated (symlinks, can be gitignored)
CLAUDE.md                             ← Appended with skill references
.github/copilot-instructions.md       ← Generated skill index
```

The install script:
1. Discovers all `SKILL.md` files in `hack/skills/`
2. Parses the YAML frontmatter (name, description, triggers)
3. Installs into the target IDE's expected location
4. Is idempotent -- safe to run multiple times

## Adding a New Skill

1. Create a directory under `hack/skills/`:

```bash
mkdir hack/skills/my-new-skill
```

2. Write `SKILL.md` with required frontmatter:

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

## Validation Criteria

...

## Common Failure Modes

| Symptom | Cause | Fix |
|---------|-------|-----|
| ... | ... | ... |

## Key Files

- ...
```

3. Re-run the install script:

```bash
./hack/skills/install-skills.sh --all
```

## When to Create a Skill vs. Not

**Create a skill when:**
- The task has multiple steps requiring judgment
- Users would naturally request it by name
- Performing it incorrectly causes meaningful problems
- It is performed repeatedly
- It is specific to this repository
- It can be validated with observable results

**Do NOT create a skill when:**
- It is a single trivial command
- It is one step inside a larger task (put it in that task's skill)
- It contains only generic programming knowledge
- It substantially overlaps another skill
- The workflow is experimental or rapidly changing

## Relationship to Other Documentation

| File | Purpose |
|------|---------|
| `AGENTS.md` | Universal repository conventions (apply to ALL changes) |
| `CLAUDE.md` | Cursor/Claude Code project guidance + skill references |
| `hack/skills/*.md` | Task-specific procedures (activated on demand) |
| `llm.txt` | Comprehensive deployment reference |
| `docs/` | Human-readable documentation site |

Skills complement -- but do not replace -- the existing documentation. They provide AI assistants with actionable procedures, while docs provide humans with understanding.
