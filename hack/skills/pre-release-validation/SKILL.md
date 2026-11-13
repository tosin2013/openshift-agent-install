---
name: pre-release-validation
description: Orchestrate the full pre-release test suite across all phases (version tests, platform manifests, disconnected workflow, E2E deployment) and generate a markdown report
compatibility: "RHEL 9.x or 10.x host. OpenShift 4.15-4.22 and 5.x. Requires: LITELLM_API_KEY, example configs for all tested platforms."
triggers:
  - pre-release validation
  - release validation
  - pre-release-validation
  - prepare release
  - validate for release
  - release testing
  - cut a release
  - release checklist
  - v4.x validation
---

# Pre-Release Validation

## When to Use This Skill

Activate when a user wants to:
- Run the full validation suite before tagging a new release
- Generate evidence of test coverage for a release PR
- Validate all supported platforms and deployment patterns in one pass
- Run `hack/pre-release-validation.sh`

## Prerequisites

- Fully bootstrapped KVM environment (`./e2e-tests/validate_env.sh` passes)
- `LITELLM_API_KEY` set for LLM-powered validation phases
- Example configurations present for tested platforms:
  - `examples/nutanix-sno/`
  - `examples/nutanix-ha/`
  - `examples/vmware-disconnected-example/`
  - `examples/ha-4.21-disconnected/`
- Sufficient disk for manifest generation (all examples × multiple versions)
- Network access to `litellm-prod.apps.maas.redhatworkshops.io`

## Procedure

### Quick Diagnostics (run first)

```bash
# Check LLM API key
[ -n "$LITELLM_API_KEY" ] && echo "LITELLM_API_KEY: set" || { [ -f ~/env ] && echo "source ~/env to set it" || echo "LITELLM_API_KEY: NOT SET and ~/env not found"; }

# Check required example configs exist
for example in sno-4.20-standard ha-4.21-disconnected; do
  ls "examples/${example}/cluster.yml" 2>/dev/null && echo "${example}: OK" || echo "${example}: MISSING"
done

# Check environment
./e2e-tests/validate_env.sh 2>&1 | tail -10
```

### Step 1: Set Required Environment Variables

```bash
export LITELLM_API_KEY="<your-key>"

# If you use a ~/env file for credentials:
source ~/env
```

Verify the LLM endpoint is reachable before starting:
```bash
curl -sf https://litellm-prod.apps.maas.redhatworkshops.io/health && echo "LLM endpoint reachable"
```

### Step 2: Run the Validation Orchestrator

```bash
./hack/pre-release-validation.sh
```

The script runs four phases in sequence, logging each to the report file and to stdout:

**Phase 1 — Version Validation E2E Tests**
Calls `e2e-tests/test_version_validation.sh --quick`
- Generates manifests for OCP 4.19, 4.20, 4.21
- Validates deployment standards per version via LLM
- Compares version boundaries (4.19→4.20, 4.20→4.21) with LLM analysis

**Phase 2 — Platform-Specific Manifest Validation**
For each of: nutanix-sno, nutanix-ha, vmware-disconnected-example
- Runs `hack/create-iso.sh <example>` to generate manifests
- Records PASSED/FAILED/SKIPPED per platform

**Phase 3 — Disconnected Workflow**
For `ha-4.21-disconnected`:
- Generates manifests and checks for `ImageDigestMirrorSet` manifest
- Verifies disconnected-specific API usage (no inline `imageContentSources`)

**Phase 4 — Full E2E Deployment** (optional, requires resources)
- Runs `e2e-tests/run_e2e.sh` for the primary test example
- Records install completion and cluster health

### Step 3: Review the Report

```bash
cat ~/validation-report-v4.21.0.md
```

The report contains per-phase status (PASSED/FAILED/SKIPPED/WARNING) and is formatted
as a GitHub-flavored markdown document ready to attach to a release PR.

### Step 4: Address Failures Before Releasing

For any FAILED item:
- Phase 1 failures: use `validate-and-compare-manifests` skill to investigate
- Phase 2 failures: check the specific example's cluster.yml for version-incompatible fields
- Phase 3 failures: verify `disconnected_registries` section exists in cluster.yml
- Phase 4 failures: use `deploy-cluster-kvm` skill for detailed troubleshooting

Only proceed to tagging when the report shows zero FAILED items.

## Environment Variables

| Variable | Required | Purpose |
|----------|----------|---------|
| `LITELLM_API_KEY` | Yes | Authentication for LLM endpoint |
| `REPORT_FILE` | No | Override report path (default: `~/validation-report-v4.21.0.md`) |
| `GENERATED_ASSET_PATH` | No | Output directory (default: `~/generated_assets`) |

## Validation Criteria

The pre-release validation is complete when:
1. All four phases complete without script-level errors (exit 0)
2. Report shows zero FAILED items
3. Phase 3 `ImageDigestMirrorSet` check shows PASSED or WARNING (not FAILED)
4. Report file exists at expected path and contains all four phase headers

## Related Skills

- **Calls these skills internally**: `validate-and-compare-manifests` (Phase 1), `run-e2e-tests` (Phase 4)
- **Before this skill**: Environment must be bootstrapped (`bootstrap-environment` complete) on the validation host
- **After passing**: Tag the release; use `destroy-cluster` to clean up any VMs created during E2E phases
- **For Phase 1 failures**: Use `validate-and-compare-manifests` skill directly with `--skip-llm` to isolate the issue

## Common Failure Modes

| Phase | Symptom | Cause | Fix |
|-------|---------|-------|-----|
| Phase 1 | LLM calls fail | API key invalid or endpoint unreachable | Verify key; check network; run `test_version_validation.sh --skip-llm` |
| Phase 1 | Manifest generation fails | cluster.yml syntax error in one example | Check `generation.log` per version; fix and re-run phase manually |
| Phase 2 | Example SKIPPED | Example directory missing | Add the example config or note as not-applicable in release notes |
| Phase 2 | ISO generation fails | Ansible error for that platform | Check create-iso.sh output for the failing example |
| Phase 3 | "ImageDigestMirrorSet not generated" | Missing `disconnected_registries` in cluster.yml | Add disconnected registry configuration to `ha-4.21-disconnected/cluster.yml` |
| Phase 4 | E2E install timeout | Insufficient resources on validation host | Reduce to SNO test example; ensure 32 GB RAM available |
| General | Script exits on first failure | `set -e` stops execution | Run each phase script individually to isolate; fix and re-run |

## Key Files

- `hack/pre-release-validation.sh` - Main orchestrator script (all four phases)
- `e2e-tests/test_version_validation.sh` - Phase 1: version validation
- `hack/generate-version-manifests.sh` - Phase 1: manifest generation per version
- `hack/validate-deployment-standards.sh` - Phase 1: LLM standards validation
- `hack/compare-version-manifests.sh` - Phase 1: version boundary comparison
- `e2e-tests/run_e2e.sh` - Phase 4: full E2E deployment
- `~/validation-report-v4.21.0.md` - Generated report (replace version in name)
