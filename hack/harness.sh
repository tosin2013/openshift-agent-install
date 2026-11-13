#!/bin/bash
# harness.sh - Interactive deployment harness for OpenShift Agent-Based Installer
#
# Guides users through the full deployment lifecycle via interactive menus.
# Works without any AI tool — a pure shell alternative to the Claude Code agent.
#
# Usage:
#   ./hack/harness.sh
#   SITE_CONFIG_DIR=site-config ./hack/harness.sh

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "${SCRIPT_DIR}/.."

SITE_CONFIG_DIR="${SITE_CONFIG_DIR:-examples}"
GENERATED_ASSET_PATH="${GENERATED_ASSET_PATH:-${HOME}/generated_assets}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

banner() {
    echo ""
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║   OpenShift Agent-Based Installer Deployment Harness ║${NC}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Config dir:  ${YELLOW}${SITE_CONFIG_DIR}/${NC}"
    echo -e "  Assets dir:  ${YELLOW}${GENERATED_ASSET_PATH}/${NC}"
    echo ""
}

confirm() {
    local msg="$1"
    local default="${2:-n}"
    local prompt

    if [ "${default}" = "y" ]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi

    echo -e "${YELLOW}${msg}${NC} ${prompt} "
    read -r answer
    answer="${answer:-${default}}"
    [[ "${answer}" =~ ^[Yy]$ ]]
}

press_enter() {
    echo ""
    echo -e "${BLUE}Press ENTER to continue...${NC}"
    read -r
}

list_configs() {
    local dir="${1:-${SITE_CONFIG_DIR}}"
    if ls "${dir}"/*/cluster.yml &>/dev/null 2>&1; then
        ls "${dir}"/*/cluster.yml | xargs -I{} dirname {} | xargs -I{} basename {}
    else
        echo "(none found)"
    fi
}

pick_config() {
    local label="${1:-cluster config}"
    local dir="${SITE_CONFIG_DIR}"
    local configs
    mapfile -t configs < <(list_configs "${dir}" 2>/dev/null)

    if [ "${#configs[@]}" -eq 0 ] || [ "${configs[0]}" = "(none found)" ]; then
        echo -e "${YELLOW}No configs found in ${dir}/.${NC} Create one first (option 2 from main menu)."
        return 1
    fi

    echo ""
    echo -e "Available ${label}s in ${dir}/:"
    local i=1
    for c in "${configs[@]}"; do
        echo "  ${i}) ${c}"
        i=$((i + 1))
    done
    echo ""
    echo -n "Enter number or name: "
    read -r selection

    # Accept numeric or name
    if [[ "${selection}" =~ ^[0-9]+$ ]]; then
        local idx=$((selection - 1))
        if [ "${idx}" -ge 0 ] && [ "${idx}" -lt "${#configs[@]}" ]; then
            echo "${configs[${idx}]}"
            return 0
        fi
    else
        for c in "${configs[@]}"; do
            if [ "${c}" = "${selection}" ]; then
                echo "${c}"
                return 0
            fi
        done
    fi

    echo -e "${RED}Invalid selection.${NC}"
    return 1
}

# ─── Menu Handlers ────────────────────────────────────────────────────────────

menu_bootstrap() {
    echo ""
    echo -e "${BOLD}=== Bootstrap Environment ===${NC}"
    echo ""
    echo "This will set up a fresh RHEL host for OpenShift ABI deployments."
    echo ""
    echo -e "${YELLOW}Prerequisites:${NC}"
    echo "  • RHEL 9.x or compatible OS"
    echo "  • sudo / root access"
    echo "  • Internet access (or configured package mirror)"
    echo "  • Minimum: 32 GB RAM (SNO) or 96 GB RAM (HA)"
    echo "  • At least 150 GB free disk space"
    echo ""

    if ! confirm "Run bootstrap_env.sh (installs packages, configures libvirt, Ansible)?"; then
        return 0
    fi

    echo ""
    log_info "Running: sudo ./e2e-tests/bootstrap_env.sh"
    sudo ./e2e-tests/bootstrap_env.sh

    echo ""
    if confirm "Also install dnsmasq DNS server (recommended for new setups)?"; then
        log_info "Running: sudo ./hack/setup-dnsmasq.sh"
        sudo ./hack/setup-dnsmasq.sh
    fi

    echo ""
    if confirm "Validate the environment now?"; then
        ./e2e-tests/validate_env.sh
    fi

    press_enter
}

menu_create_config() {
    echo ""
    echo -e "${BOLD}=== Create Cluster Configuration ===${NC}"
    echo ""
    echo "This opens the reference documentation for authoring cluster.yml and nodes.yml."
    echo ""
    echo "Reference examples:"
    list_configs "examples"
    echo ""
    echo -e "${YELLOW}For guided cluster config creation, use Claude Code:${NC}"
    echo "  Type: 'create a new cluster config for SNO' in Claude Code"
    echo ""
    echo -e "${YELLOW}To start from an example manually:${NC}"
    echo "  cp -r examples/sno-4.20-standard site-config/my-cluster"
    echo "  # Edit site-config/my-cluster/cluster.yml and nodes.yml"
    echo ""
    echo -e "${YELLOW}After editing, validate:${NC}"
    echo "  ./hack/validate-kvm-examples.sh       # KVM configs"
    echo "  ./hack/validate-baremetal-env.sh <config>  # Bare metal configs"
    echo ""
    press_enter
}

menu_deploy_kvm() {
    echo ""
    echo -e "${BOLD}=== Deploy Cluster on KVM ===${NC}"
    echo ""
    echo -e "${YELLOW}Prerequisites:${NC}"
    echo "  • Environment bootstrapped (option 1 above)"
    echo "  • Cluster config in ${SITE_CONFIG_DIR}/"
    echo "  • Pull secret at ~/pull-secret.json"
    echo "  • Sufficient resources: SNO=32GB RAM/130GB disk, HA=96GB RAM/600GB disk"
    echo ""

    local config
    config=$(pick_config "cluster") || return 0

    echo ""
    echo -e "Selected: ${GREEN}${config}${NC}"
    echo ""

    echo "Deployment options:"
    echo "  1) One-shot (recommended) — ./hack/deploy-connected-full.sh"
    echo "  2) Step-by-step — DNS, ISO, VMs, monitoring individually"
    echo "  3) HA with HAProxy — ./hack/deploy-ha-full.sh"
    echo ""
    echo -n "Choose [1]: "
    read -r deploy_opt
    deploy_opt="${deploy_opt:-1}"

    case "${deploy_opt}" in
        1)
            if ! confirm "Run deploy-connected-full.sh for '${config}'?"; then return 0; fi
            echo ""
            log_info "Running: ./hack/deploy-connected-full.sh ${SITE_CONFIG_DIR}/${config}"
            ./hack/deploy-connected-full.sh "${SITE_CONFIG_DIR}/${config}"
            ;;
        2)
            echo ""
            echo "--- Step 1: DNS Setup ---"
            if confirm "Configure dnsmasq entries for '${config}'?"; then
                sudo ./hack/configure-dnsmasq-entries.sh add "${SITE_CONFIG_DIR}/${config}/cluster.yml"
                ./hack/verify-dns-resolution.sh "${SITE_CONFIG_DIR}/${config}/cluster.yml"
            fi

            echo ""
            echo "--- Step 2: Generate ISO ---"
            if confirm "Generate agent ISO for '${config}'?"; then
                SITE_CONFIG_DIR="${SITE_CONFIG_DIR}" ./hack/create-iso.sh "${config}"
            fi

            echo ""
            echo "--- Step 3: Deploy VMs ---"
            if confirm "Create KVM VMs for '${config}'?"; then
                ./hack/deploy-on-kvm.sh "${SITE_CONFIG_DIR}/${config}/nodes.yml"
                echo ""
                echo -e "${YELLOW}IMPORTANT: Starting the VM reboot watcher in background.${NC}"
                echo "Agent VMs shut down after writing disk — they must be restarted automatically."
                ./hack/watch-and-reboot-kvm-vms.sh "${SITE_CONFIG_DIR}/${config}/nodes.yml" &
                echo "Watcher PID: $!"
            fi

            echo ""
            echo "--- Step 4: Monitor Installation ---"
            local cluster_name
            cluster_name=$(grep "cluster_name" "${SITE_CONFIG_DIR}/${config}/cluster.yml" | awk '{print $2}' | tr -d '"')
            if confirm "Wait for bootstrap-complete?"; then
                ./bin/openshift-install agent wait-for bootstrap-complete \
                    --dir "${GENERATED_ASSET_PATH}/${cluster_name}/"
            fi
            if confirm "Wait for install-complete?"; then
                ./bin/openshift-install agent wait-for install-complete \
                    --dir "${GENERATED_ASSET_PATH}/${cluster_name}/"
            fi
            ;;
        3)
            echo -n "Enter EXTERNAL_IP for HAProxy: "
            read -r ext_ip
            if ! confirm "Run deploy-ha-full.sh for '${config}' with EXTERNAL_IP=${ext_ip}?"; then return 0; fi
            echo ""
            log_info "Running: EXTERNAL_IP=${ext_ip} ./hack/deploy-ha-full.sh ${SITE_CONFIG_DIR}/${config}"
            EXTERNAL_IP="${ext_ip}" ./hack/deploy-ha-full.sh "${SITE_CONFIG_DIR}/${config}"
            ;;
        *)
            echo "Invalid option."
            ;;
    esac

    press_enter
}

menu_deploy_baremetal() {
    echo ""
    echo -e "${BOLD}=== Deploy Cluster on Bare Metal ===${NC}"
    echo ""
    echo -e "${YELLOW}Prerequisites:${NC}"
    echo "  • Agent ISO already generated (use option 3 step-by-step first)"
    echo "  • BMC credentials in nodes.yml (Redfish or IPMI)"
    echo "  • Physical servers reachable from this host"
    echo ""

    local config
    config=$(pick_config "cluster") || return 0

    local cluster_name
    cluster_name=$(grep "cluster_name" "${SITE_CONFIG_DIR}/${config}/cluster.yml" | awk '{print $2}' | tr -d '"')
    local iso_path="${GENERATED_ASSET_PATH}/${cluster_name}/agent.x86_64.iso"

    echo ""
    echo "ISO path: ${iso_path}"
    if [ ! -f "${iso_path}" ]; then
        echo -e "${RED}ISO not found at ${iso_path}${NC}"
        echo "Generate it first: ./hack/create-iso.sh ${config}"
        press_enter
        return 0
    fi
    echo -e "${GREEN}ISO found.${NC}"

    echo ""
    echo "Deployment method:"
    echo "  1) Redfish virtual media (iDRAC 9+, iLO 5+) — recommended"
    echo "  2) IPMI boot from URL"
    echo "  3) Check BMC connectivity only"
    echo ""
    echo -n "Choose [1]: "
    read -r bm_opt
    bm_opt="${bm_opt:-1}"

    case "${bm_opt}" in
        1) method="redfish" ;;
        2) method="ipmi" ;;
        3) method="check" ;;
        *) echo "Invalid."; return 0 ;;
    esac

    if ! confirm "Run deploy-iso-baremetal.sh --method ${method} for '${config}'?"; then return 0; fi

    ./hack/deploy-iso-baremetal.sh "${SITE_CONFIG_DIR}/${config}/nodes.yml" \
        --method "${method}" --iso "${iso_path}"

    press_enter
}

menu_destroy() {
    echo ""
    echo -e "${BOLD}=== Destroy Cluster ===${NC}"
    echo ""
    echo -e "${RED}WARNING: This removes VMs, disk images, and DNS entries permanently.${NC}"
    echo ""

    local config
    config=$(pick_config "cluster") || return 0

    echo ""
    echo -e "Selected: ${RED}${config}${NC}"
    echo ""
    echo "This will:"
    echo "  • Remove DNS entries from dnsmasq"
    echo "  • Destroy and undefine all cluster VMs"
    echo "  • Delete qcow2 disk images from /var/lib/libvirt/images/"
    echo ""

    if ! confirm "DESTROY cluster '${config}'? This cannot be undone." "n"; then
        echo "Cancelled."
        return 0
    fi

    echo ""
    log_info "Running: ./hack/destroy-on-kvm.sh ${SITE_CONFIG_DIR}/${config}/nodes.yml"
    ./hack/destroy-on-kvm.sh "${SITE_CONFIG_DIR}/${config}/nodes.yml"

    local cluster_name
    cluster_name=$(grep "cluster_name" "${SITE_CONFIG_DIR}/${config}/cluster.yml" 2>/dev/null | awk '{print $2}' | tr -d '"')
    if [ -n "${cluster_name}" ] && confirm "Also remove generated assets at ${GENERATED_ASSET_PATH}/${cluster_name}/?"; then
        rm -rf "${GENERATED_ASSET_PATH}/${cluster_name}/"
        echo -e "${GREEN}Generated assets removed.${NC}"
    fi

    press_enter
}

menu_e2e_tests() {
    echo ""
    echo -e "${BOLD}=== Run E2E Tests ===${NC}"
    echo ""
    echo -e "${YELLOW}Prerequisites:${NC}"
    echo "  • Environment bootstrapped and validated"
    echo "  • LITELLM_API_KEY set (for version validation tests)"
    echo "  • Sufficient resources for full E2E: 32+ GB RAM"
    echo ""
    echo "Test options:"
    echo "  1) Full E2E deployment test (creates VMs, installs cluster, destroys after)"
    echo "  2) Version validation tests only (no VMs required)"
    echo ""
    echo -n "Choose [2]: "
    read -r test_opt
    test_opt="${test_opt:-2}"

    case "${test_opt}" in
        1)
            local config
            config=$(pick_config "cluster") || return 0
            echo -n "Base domain for cluster (e.g. example.com): "
            read -r domain
            if ! confirm "Run full E2E for '${config}' with domain '${domain}'?"; then return 0; fi
            DOMAIN="${domain}" ./e2e-tests/run_e2e.sh "${config}"
            ;;
        2)
            echo ""
            echo "  a) Full version validation (requires LITELLM_API_KEY)"
            echo "  b) Skip LLM calls (--skip-llm)"
            echo "  c) Quick mode (--quick)"
            echo ""
            echo -n "Choose [b]: "
            read -r llm_opt
            llm_opt="${llm_opt:-b}"
            case "${llm_opt}" in
                a) if confirm "Run test_version_validation.sh?"; then ./e2e-tests/test_version_validation.sh; fi ;;
                b) if confirm "Run test_version_validation.sh --skip-llm?"; then ./e2e-tests/test_version_validation.sh --skip-llm; fi ;;
                c) if confirm "Run test_version_validation.sh --quick?"; then ./e2e-tests/test_version_validation.sh --quick; fi ;;
                *) echo "Invalid." ;;
            esac
            ;;
        *)
            echo "Invalid option."
            ;;
    esac

    press_enter
}

menu_prerelease() {
    echo ""
    echo -e "${BOLD}=== Pre-Release Validation ===${NC}"
    echo ""
    echo -e "${YELLOW}Prerequisites:${NC}"
    echo "  • LITELLM_API_KEY set (source ~/env or export manually)"
    echo "  • Example configs for all tested platforms"
    echo "  • Internet access to LiteLLM endpoint"
    echo ""
    echo "This runs all 4 validation phases:"
    echo "  1. Version validation E2E tests"
    echo "  2. Platform-specific manifest validation"
    echo "  3. Disconnected workflow validation"
    echo "  4. Full E2E deployment (optional)"
    echo ""
    echo "Report saved to: ~/validation-report-v4.21.0.md"
    echo ""

    if [ -z "${LITELLM_API_KEY}" ]; then
        echo -e "${YELLOW}LITELLM_API_KEY is not set.${NC}"
        if confirm "Source ~/env to set it?"; then
            # shellcheck disable=SC1091
            source ~/env 2>/dev/null || { echo "~/env not found — set LITELLM_API_KEY manually"; return 0; }
        else
            echo "Set it with: export LITELLM_API_KEY=<key>"
            press_enter
            return 0
        fi
    fi

    if ! confirm "Run pre-release-validation.sh?"; then return 0; fi

    ./hack/pre-release-validation.sh

    press_enter
}

menu_fetch_rh_skills() {
    echo ""
    echo -e "${BOLD}=== Fetch Official Red Hat AI Skills ===${NC}"
    echo ""
    echo "Downloads skills from public Red Hat repositories:"
    echo "  • openshift/agentic-skills       → cluster-troubleshoot, cluster-update, gitops"
    echo "  • RHEcosystemAppEng/agentic-plugins → ocp-admin/*, rh-basic/*"
    echo "  • redhat-developer/agentic-skills → Argo CD skills"
    echo ""
    echo "Output: .rh-skills/ (gitignored, local only)"
    echo ""
    echo "Note: These skills cover OpenShift day-2 and GitOps operations."
    echo "      For Agent-Based Installer provisioning, use this repo's skills."
    echo ""
    echo "For the official (non-GitHub) Red Hat AI Skills Catalog:"
    echo "  https://catalog.redhat.com/en/ai/skills"
    echo ""

    if ! command -v git &>/dev/null; then
        echo -e "${RED}git is required for this option.${NC}"
        press_enter
        return 0
    fi

    echo "Options:"
    echo "  1) Fetch all recommended skills"
    echo "  2) List what would be fetched (no download)"
    echo "  3) Clean .rh-skills/ directory"
    echo ""
    echo -n "Choose [1]: "
    read -r rh_opt
    rh_opt="${rh_opt:-1}"

    case "${rh_opt}" in
        1) if confirm "Download Red Hat skills to .rh-skills/?"; then ./hack/skills/pull-rh-skills.sh; fi ;;
        2) ./hack/skills/pull-rh-skills.sh --list ;;
        3) if confirm "Remove .rh-skills/ directory?"; then ./hack/skills/pull-rh-skills.sh --clean; fi ;;
        *) echo "Invalid." ;;
    esac

    press_enter
}

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# ─── Main Loop ────────────────────────────────────────────────────────────────

main() {
    while true; do
        clear
        banner

        echo -e "${BOLD}What would you like to do?${NC}"
        echo ""
        echo "  1) Bootstrap Environment        — set up fresh RHEL host for deployments"
        echo "  2) Create Cluster Configuration — author cluster.yml + nodes.yml"
        echo "  3) Deploy on KVM                — DNS, ISO, VMs, install monitoring"
        echo "  4) Deploy on Bare Metal         — Redfish/IPMI ISO delivery"
        echo "  5) Destroy Cluster              — remove VMs, disks, DNS entries"
        echo "  6) Run E2E Tests                — full deployment test or version validation"
        echo "  7) Pre-Release Validation       — full validation suite + report"
        echo "  8) Fetch Red Hat AI Skills      — download skills from public RH repos"
        echo "  9) Exit"
        echo ""
        echo -n "Enter choice [1-9]: "
        read -r choice

        case "${choice}" in
            1) menu_bootstrap ;;
            2) menu_create_config ;;
            3) menu_deploy_kvm ;;
            4) menu_deploy_baremetal ;;
            5) menu_destroy ;;
            6) menu_e2e_tests ;;
            7) menu_prerelease ;;
            8) menu_fetch_rh_skills ;;
            9|q|quit|exit)
                echo ""
                echo "Goodbye."
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice. Enter 1-9.${NC}"
                sleep 1
                ;;
        esac
    done
}

main
