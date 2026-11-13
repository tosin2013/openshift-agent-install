---
name: validate-and-compare-manifests
description: Generate ABI manifests for multiple OCP versions, diff them to surface breaking changes, and validate against version-specific deployment standards using LLM analysis
compatibility: "RHEL 9.x or 10.x host. OpenShift 4.15-4.22 and 5.x. OCP 5.x uses openshift-v5 mirror. Requires: LITELLM_API_KEY for LLM steps (optional --skip-llm mode available)."
triggers:
  - validate manifests
  - compare manifests
  - version manifests
  - generate version manifests
  - deployment standards validation
  - version comparison
  - compare version manifests
  - manifest validation
  - LLM manifest analysis
  - OCP version upgrade check
---

# Validate and Compare Version Manifests

## When to Use This Skill

Activate when a user wants to:
- Check for breaking manifest changes before upgrading a cluster config to a new OCP version
- Generate manifests for side-by-side comparison of two OCP releases
- Validate that a configuration meets version-specific deployment standards
- Identify whether `imageContentSources` → `imageDigestSources` migration is needed
- Run `hack/generate-version-manifests.sh`, `hack/compare-version-manifests.sh`, or `hack/validate-deployment-standards.sh`

## Prerequisites

- `ansible-core` installed and working (`ansible --version`)
- Cluster example directory exists in `examples/` or `site-config/` with `cluster.yml` and `nodes.yml`
- For LLM analysis steps: `LITELLM_API_KEY` environment variable set
- For version-specific OC CLI: internet access or cached CLIs in `~/.cache/ocp-cli/`

**Note**: Steps 1 (generate) and manual diff are usable without an LLM API key. Steps 2 and 3
require `LITELLM_API_KEY` for the AI analysis. Use `--skip-llm` flag to run without it.

## Procedure

### Quick Diagnostics (run first)

```bash
# Check LLM API key (required for compare/validate steps)
[ -n "$LITELLM_API_KEY" ] && echo "LITELLM_API_KEY: set" || echo "LITELLM_API_KEY: NOT SET (source ~/env or export it)"

# List available example configs
ls "${SITE_CONFIG_DIR:-examples}/"

# Check for previously generated version manifests
ls ~/generated_assets/version-compare/ 2>/dev/null | head -20 || echo "No version manifests generated yet"
```

Determine the target example name and which versions to compare before proceeding. Use `--skip-llm` if LITELLM_API_KEY is not available.

### Step 1: Generate Manifests for Each Target Version

```bash
./hack/generate-version-manifests.sh <example-name> "<version-list>"
# Examples:
./hack/generate-version-manifests.sh sno-disconnected "4.20 4.21"
./hack/generate-version-manifests.sh ha-4.21-disconnected "4.19 4.20 4.21"
```

Output lands in `~/generated_assets/version-compare/<example>-<version>/`.
Each subdirectory contains the full set of ABI manifests (install-config.yaml,
agent-config.yaml, and all custom manifests) for that version.

A `generation.log` per version records the Ansible playbook output.

Verify generation succeeded:
```bash
ls ~/generated_assets/version-compare/
# Should show: sno-disconnected-4.20/  sno-disconnected-4.21/

ls ~/generated_assets/version-compare/sno-disconnected-4.21/
# Should show: install-config.yaml  agent-config.yaml  ...
```

### Step 2: Compare Two Versions (LLM-Powered)

```bash
export LITELLM_API_KEY="<your-key>"
./hack/compare-version-manifests.sh 4.20 4.21 sno-disconnected
```

This:
1. Runs a structural diff across all YAML files between the two version directories
2. Sends the diff to the Granite 3.2 8B model at the LiteLLM endpoint
3. Returns a semantic analysis highlighting:
   - Breaking API changes (e.g., deprecated fields)
   - New required fields in the target version
   - Configuration patterns that must change
   - Recommended actions before upgrading

### Step 3: Validate Against Deployment Standards (LLM-Powered)

```bash
export LITELLM_API_KEY="<your-key>"
./hack/validate-deployment-standards.sh \
  ~/generated_assets/version-compare/sno-disconnected-4.21 4.21
```

Validates the manifests in a specific versioned directory against known rules for
that OCP version. Key checks include:
- `networkType: OVNKubernetes` required for 4.21+
- `imageDigestSources` (not `imageContentSources`) for disconnected 4.20+
- Platform-specific fields present and correct
- Rendezvous IP within machine network

Optional flag to track findings:
```bash
./hack/validate-deployment-standards.sh \
  ~/generated_assets/version-compare/sno-disconnected-4.21 4.21 --create-issue
```

### Step 4: Manual Diff (Without LLM)

If the LLM endpoint is unavailable:
```bash
# Structural diff between two versions
diff -r \
  ~/generated_assets/version-compare/sno-disconnected-4.20/ \
  ~/generated_assets/version-compare/sno-disconnected-4.21/ \
  | grep -v "Only in"

# Check for the specific 4.20→4.21 networkType change
grep "networkType" ~/generated_assets/version-compare/sno-disconnected-4.21/install-config.yaml
# Must show: networkType: OVNKubernetes
```

## Environment Variables

| Variable | Required | Purpose |
|----------|----------|---------|
| `LITELLM_API_KEY` | Yes (Steps 2 & 3) | API key for LLM endpoint authentication |
| `LITELLM_ENDPOINT` | No | Override endpoint URL (default: `https://litellm-prod.apps.maas.redhatworkshops.io/v1/chat/completions`) |
| `LITELLM_MODEL` | No | Override model (default: `granite-3-2-8b-instruct`) |
| `GENERATED_ASSET_PATH` | No | Base output directory (default: `~/generated_assets`) |
| `SITE_CONFIG_DIR` | No | Config location (default: `examples`) |

## Validation Criteria

The validation workflow is complete when:
1. All `generate-version-manifests.sh` versions succeed (exit 0, no FAILED count)
2. `compare-version-manifests.sh` produces a diff report without errors
3. `validate-deployment-standards.sh` returns PASS for the target version's key checks
4. Known version boundary changes are correctly flagged:
   - 4.19→4.20: `imageContentSources` → standalone `ImageDigestMirrorSet` manifest
   - 4.20→4.21: `networkType: OpenShiftSDN` → `OVNKubernetes`

## Version Notes

| OCP Version | Key Requirements |
|-------------|-----------------|
| 4.15–4.19 | `imageContentSources` for disconnected; OpenShiftSDN allowed |
| 4.20–4.21 | `imageDigestSources` required; OVNKubernetes required |
| 4.22 | Same as 4.20–4.21; last OCP 4.x release |
| 5.0+ | RHCOS 10 default; CLI downloads from `openshift-v5` mirror; `os_image_stream` field available |

## Related Skills

- **Before this skill**: Run `create-cluster-config` first — this skill consumes the `cluster.yml` and `nodes.yml` that skill produces
- **Also called by**: `pre-release-validation` runs this skill automatically as part of its validation pipeline
- **After passing**: Proceed with confidence to `deploy-cluster-kvm` or `deploy-cluster-baremetal`

## Common Failure Modes

| Phase | Symptom | Cause | Fix |
|-------|---------|-------|-----|
| Generate | "Example not found" | Wrong example name passed | `ls examples/` to find correct directory name |
| Generate | Ansible playbook fails | Syntax error in cluster.yml | Check `generation.log` in output dir; fix cluster.yml |
| Generate | "nodes.yml not found" | Missing file in example directory | Verify `examples/<name>/nodes.yml` exists |
| Compare | "Base version directory not found" | Generate step not run for base version | Run `generate-version-manifests.sh` for both versions first |
| LLM | "Authentication failed" | Invalid or missing LITELLM_API_KEY | `export LITELLM_API_KEY=<key>` or add to `~/env` file |
| LLM | "Connection refused" to endpoint | LiteLLM endpoint unreachable | Verify network access; use manual diff (Step 4) instead |
| Validate | "install-config.yaml not found" | Generate step incomplete | Check generation.log; re-run generate for that version |
| Validate | FAIL on networkType | Old config using OpenShiftSDN | Set `network_type: OVNKubernetes` in cluster.yml for 4.21+ |

## Key Files

- `hack/generate-version-manifests.sh` - Generates manifests for a list of OCP versions
- `hack/compare-version-manifests.sh` - Diffs two version directories with LLM analysis
- `hack/validate-deployment-standards.sh` - Validates manifests against version rules
- `e2e-tests/test_version_validation.sh` - Full E2E suite wrapping all three scripts
- `~/generated_assets/version-compare/` - Output directory for all version manifests
