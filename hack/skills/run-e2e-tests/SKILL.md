---
name: Run End-to-End Tests
description: Execute the full E2E test suite (ISO creation, VM deployment, installation monitoring) or version validation tests against configured cluster examples
triggers:
  - run e2e tests
  - end-to-end tests
  - e2e testing
  - run tests
  - run_e2e
  - test version validation
  - full deployment test
  - automated testing
  - CI testing
  - test deployment
---

# Run End-to-End Tests

## When to Use This Skill

Activate when a user wants to:
- Run automated end-to-end deployment tests on a KVM host
- Validate that changes to scripts or templates don't break existing examples
- Run multi-version manifest validation and comparison (no VMs required)
- Execute the CI/CD validation pipeline locally
- Run `e2e-tests/run_e2e.sh` or `e2e-tests/test_version_validation.sh`

## Prerequisites

For **full E2E tests** (Option A — deploys VMs):
- Environment bootstrapped (`./e2e-tests/validate_env.sh` passes)
- dnsmasq running (`sudo systemctl status dnsmasq`)
- VyOS router active if using VLAN-based examples
- At least one example config in `examples/`
- Resources: SNO = 32 GB RAM + 130 GB disk; HA = 96 GB RAM + 600 GB disk

For **version validation tests** (Option B — no VMs):
- `ansible-core` installed
- `LITELLM_API_KEY` set (or use `--skip-llm` to run without AI analysis)
- Example configs in `examples/` with correct `cluster.yml` and `nodes.yml`

## Procedure

### Option A: Full E2E Test (ISO + VMs + Install)

```bash
export DOMAIN="example.com"
./e2e-tests/run_e2e.sh <example-name>
# Example:
./e2e-tests/run_e2e.sh sno-4.20-standard
```

The script runs these phases in order:
1. Updates `base_domain` in the cluster config to match `$DOMAIN`
2. Configures dnsmasq DNS entries for the cluster
3. Verifies DNS resolution (hard gate — exits if DNS fails)
4. Generates the agent ISO via `hack/create-iso.sh`
5. Deploys KVM VMs via `hack/deploy-on-kvm.sh`
6. Starts the VM reboot watcher in the background
7. Monitors installation with `openshift-install agent wait-for install-complete`

**Important**: `DOMAIN` must match what your DNS and dnsmasq are configured for.

### Option B: Version Validation Tests (No VMs)

```bash
# Full version validation with LLM analysis
export LITELLM_API_KEY="<your-key>"
./e2e-tests/test_version_validation.sh

# Skip LLM calls (use manual diff only)
./e2e-tests/test_version_validation.sh --skip-llm

# Fast mode (skip time-consuming steps)
./e2e-tests/test_version_validation.sh --quick
```

Runs three test categories:
1. **generate-version-manifests.sh** — generates manifests for 4.19, 4.20, 4.21
2. **validate-deployment-standards.sh** — LLM validation of deployment patterns
3. **compare-version-manifests.sh** — version boundary diff and AI analysis

Output: `PASSED`, `FAILED`, or `SKIPPED` count per test.

### Option C: Cleanup After Testing

```bash
./e2e-tests/delete_e2e.sh <example-name>
```

Destroys VMs, removes DNS entries, and cleans up `~/generated_assets/<cluster-name>/`.

### Monitoring a Running Test

```bash
# Watch VM status during deployment
watch -n 10 'virsh list --all'

# Tail the install log
tail -f ~/generated_assets/<cluster-name>/agent.x86_64.iso 2>/dev/null || \
  journalctl -f -u openshift-install

# After bootstrap completes, check operator status
export KUBECONFIG=~/generated_assets/<cluster-name>/auth/kubeconfig
watch -n 30 'oc get co'
```

## Environment Variables

| Variable | Required | Purpose |
|----------|----------|---------|
| `DOMAIN` | Yes (Option A) | Base domain for cluster DNS (e.g., `example.com`) |
| `LITELLM_API_KEY` | Yes (LLM tests) | API key for version validation AI analysis |
| `TEST_QUICK` | No | Set `true` to skip slow steps in test_version_validation.sh |
| `SITE_CONFIG_DIR` | No | Config directory (default: `examples`) |
| `GENERATED_ASSET_PATH` | No | Output directory (default: `~/generated_assets`) |

## Validation Criteria

**Full E2E (Option A)** passes when:
1. DNS resolves before VM deployment (`verify-dns-resolution.sh` exits 0)
2. All VMs are created and booting (`virsh list --all` shows them)
3. `wait-for bootstrap-complete` exits 0
4. `wait-for install-complete` exits 0
5. `oc get nodes` shows all nodes Ready
6. `oc get co` shows all operators Available=True, Degraded=False

**Version tests (Option B)** pass when:
1. Script exits 0
2. All non-LLM tests PASSED
3. With LLM enabled: zero FAILED tests in output

## Related Skills

- **Before this skill**: `bootstrap-environment` must be complete; for Option A, `deploy-vyos-router` must be running if using VLAN examples
- **Also called by**: `pre-release-validation` runs this skill automatically as one of its phases
- **Cleanup after tests**: Use `destroy-cluster` skill or the built-in Option C (`delete_e2e.sh`)
- **If version tests fail**: Use `validate-and-compare-manifests` to investigate specific manifest diffs in detail

## Common Failure Modes

| Phase | Symptom | Cause | Fix |
|-------|---------|-------|-----|
| DNS | "DNS verification failed" | dnsmasq not configured for this cluster | `sudo ./hack/configure-dnsmasq-entries.sh add <cluster.yml>` |
| DNS | "dnsmasq is not running" | Service stopped | `sudo systemctl start dnsmasq` |
| ISO | "Failed to create ISO" | Ansible playbook error | Check cluster.yml syntax; check Ansible collections installed |
| VMs | "Please generate the agent.iso first" | CLUSTER_NAME mismatch | Set `CLUSTER_NAME` to match cluster.yml `cluster_name` field |
| VMs | "Permission denied" | User not in libvirt group | `sudo usermod -aG libvirt $USER` and re-login |
| Install | Stuck at bootstrap >45 min | VMs not auto-rebooting | `run_e2e.sh` starts the watcher; check it's running: `ps aux | grep watch-and-reboot` |
| Version tests | "LITELLM_API_KEY not set" | Missing env var | `source ~/env` or `export LITELLM_API_KEY=<key>` |
| Version tests | Ansible fails per version | Missing required fields in cluster.yml | Check `generation.log` files in `~/generated_assets/version-compare/` |

## Key Files

- `e2e-tests/run_e2e.sh` - Full E2E orchestrator (ISO + VMs + monitoring)
- `e2e-tests/test_version_validation.sh` - Version validation test suite (no VMs)
- `e2e-tests/delete_e2e.sh` - E2E environment cleanup
- `e2e-tests/validate_env.sh` - Environment prerequisite checker
- `e2e-tests/bootstrap_env.sh` - Full host bootstrap (run once before tests)
