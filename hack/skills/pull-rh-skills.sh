#!/bin/bash
# pull-rh-skills.sh - Download AI skills from public Red Hat repositories
#
# Fetches skills from:
#   - openshift/agentic-skills
#   - RHEcosystemAppEng/agentic-plugins
#   - redhat-developer/agentic-skills
#
# Output: .rh-skills/<repo>/<skill>/ (gitignored, local only)
#
# Usage:
#   ./hack/skills/pull-rh-skills.sh              # Fetch all recommended skills
#   ./hack/skills/pull-rh-skills.sh --list       # Show what would be fetched
#   ./hack/skills/pull-rh-skills.sh --clean      # Remove .rh-skills/ directory
#   ./hack/skills/pull-rh-skills.sh --repo <name> # Fetch from one repo only

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
OUTPUT_DIR="${PROJECT_ROOT}/.rh-skills"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERR]${NC} $1"; }
log_header()  { echo -e "\n${CYAN}=== $1 ===${NC}"; }

# Skills to fetch per repo — sparse paths within each repo
declare -A REPO_URLS
REPO_URLS["openshift-agentic-skills"]="https://github.com/openshift/agentic-skills"
REPO_URLS["rhecosystemappeng-agentic-plugins"]="https://github.com/RHEcosystemAppEng/agentic-plugins"
REPO_URLS["redhat-developer-agentic-skills"]="https://github.com/redhat-developer/agentic-skills"

declare -A REPO_PATHS
# Skills to sparse-checkout from each repo
REPO_PATHS["openshift-agentic-skills"]="cluster-troubleshoot cluster-update gitops"
REPO_PATHS["rhecosystemappeng-agentic-plugins"]="ocp-admin rh-basic"
REPO_PATHS["redhat-developer-agentic-skills"]="skills/argo-knowledge skills/argo-repo-audit skills/argo-cluster-debug skills/argo-performance-tuning"

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Download AI skills from public Red Hat repositories into .rh-skills/

Options:
  --list           Show what would be fetched without downloading
  --clean          Remove the .rh-skills/ directory
  --repo <name>    Fetch from one repo only (openshift, rhecosystemappeng, redhat-developer)
  -h, --help       Show this help

Repos fetched:
  openshift/agentic-skills          → cluster-troubleshoot, cluster-update, gitops
  RHEcosystemAppEng/agentic-plugins → ocp-admin/*, rh-basic/*
  redhat-developer/agentic-skills   → argo-* skills

Output directory: .rh-skills/ (gitignored)

After fetching, install into your IDE:
  Claude Code: Copy skill content and reference in CLAUDE.md
  Cursor:      Copy skill files to .cursor/skills/
EOF
}

list_skills() {
    log_header "Skills that would be fetched"
    echo ""
    for repo_key in "${!REPO_URLS[@]}"; do
        local url="${REPO_URLS[$repo_key]}"
        local paths="${REPO_PATHS[$repo_key]}"
        echo -e "  ${CYAN}${url}${NC}"
        for path in $paths; do
            echo "    → ${path}"
        done
        echo ""
    done

    echo -e "Output: ${OUTPUT_DIR}/"
    echo ""
    echo "Note: Skills from these repos are Apache 2.0 licensed."
    echo "      They complement this repo's skills — they do NOT cover Agent-Based Installer deployments."
}

clean_skills() {
    if [ -d "${OUTPUT_DIR}" ]; then
        log_info "Removing ${OUTPUT_DIR}/"
        rm -rf "${OUTPUT_DIR}"
        log_success "Removed .rh-skills/"
    else
        log_info ".rh-skills/ does not exist, nothing to clean"
    fi
}

check_dependencies() {
    if ! command -v git &>/dev/null; then
        log_error "git is required. Install with: sudo dnf install git"
        exit 1
    fi
}

fetch_repo() {
    local repo_key="$1"
    local url="${REPO_URLS[$repo_key]}"
    local paths="${REPO_PATHS[$repo_key]}"
    local dest="${OUTPUT_DIR}/${repo_key}"

    log_header "Fetching from ${url}"

    if [ -d "${dest}/.git" ]; then
        log_info "Repo already cloned, pulling latest..."
        git -C "${dest}" pull --quiet 2>/dev/null || log_warn "Pull failed — using cached version"
        log_success "Updated ${repo_key}"
        return 0
    fi

    mkdir -p "${dest}"

    # Use sparse checkout to avoid downloading the entire repo
    log_info "Cloning with sparse checkout (paths: ${paths})..."

    git clone --filter=blob:none --no-checkout --depth=1 --quiet "${url}" "${dest}" 2>/dev/null || {
        log_warn "Could not clone ${url} — repo may be private or unreachable"
        rm -rf "${dest}"
        return 1
    }

    git -C "${dest}" sparse-checkout init --cone 2>/dev/null || {
        # Fallback: older git without cone mode
        git -C "${dest}" sparse-checkout init 2>/dev/null || true
    }

    git -C "${dest}" sparse-checkout set ${paths} 2>/dev/null || true
    git -C "${dest}" checkout --quiet 2>/dev/null || git -C "${dest}" checkout HEAD --quiet 2>/dev/null || true

    local fetched=$(find "${dest}" -name "*.md" -not -path "*/.git/*" 2>/dev/null | wc -l)
    if [ "${fetched}" -gt 0 ]; then
        log_success "Fetched ${repo_key} (${fetched} markdown files)"
    else
        log_warn "Fetched ${repo_key} but found no markdown files — repo structure may have changed"
    fi
}

print_post_fetch_instructions() {
    log_header "Fetched skills are in .rh-skills/"
    echo ""
    echo "These skills complement this repo — they cover OpenShift day-2 operations,"
    echo "GitOps with Argo CD, and RHEL administration."
    echo ""
    echo "To use in Claude Code, add references to CLAUDE.md or copy skills into hack/skills/."
    echo "To use in Cursor, copy skill files into .cursor/skills/."
    echo ""
    echo "Note: .rh-skills/ is gitignored — your local copy is not committed to this repo."
    echo ""
    echo "For the official Red Hat AI Skills Catalog (not on GitHub):"
    echo "  https://catalog.redhat.com/en/ai/skills"
    echo "  Contact: agentskills@redhat.com"
}

ensure_gitignore() {
    local gitignore="${PROJECT_ROOT}/.gitignore"
    if [ -f "${gitignore}" ]; then
        if ! grep -q "^\.rh-skills" "${gitignore}" 2>/dev/null; then
            echo ".rh-skills/" >> "${gitignore}"
            log_info "Added .rh-skills/ to .gitignore"
        fi
    fi
}

# Parse args
REPO_FILTER=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --list)
            list_skills
            exit 0
            ;;
        --clean)
            clean_skills
            exit 0
            ;;
        --repo)
            REPO_FILTER="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

check_dependencies
ensure_gitignore
mkdir -p "${OUTPUT_DIR}"

FETCH_COUNT=0
FAIL_COUNT=0

for repo_key in "${!REPO_URLS[@]}"; do
    # Apply repo filter if specified
    if [ -n "${REPO_FILTER}" ]; then
        if [[ "${repo_key}" != *"${REPO_FILTER}"* ]]; then
            continue
        fi
    fi

    if fetch_repo "${repo_key}"; then
        FETCH_COUNT=$((FETCH_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

echo ""
echo -e "${GREEN}Done.${NC} Fetched: ${FETCH_COUNT}  Failed: ${FAIL_COUNT}"

if [ "${FAIL_COUNT}" -gt 0 ]; then
    log_warn "Some repos failed — check network connectivity and repo availability"
fi

if [ "${FETCH_COUNT}" -gt 0 ]; then
    print_post_fetch_instructions
fi
