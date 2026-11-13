#!/bin/bash
# install-skills.sh - Install AI skills into IDE-specific locations
#
# Supports: Cursor, Claude Code, GitHub Copilot
# Skills are stored canonically in hack/skills/<name>/SKILL.md
#
# Usage:
#   ./hack/skills/install-skills.sh              # Install for Cursor (default)
#   ./hack/skills/install-skills.sh --cursor     # Install for Cursor
#   ./hack/skills/install-skills.sh --claude-code # Install for Claude Code
#   ./hack/skills/install-skills.sh --copilot    # Install for GitHub Copilot
#   ./hack/skills/install-skills.sh --all        # Install for all IDEs
#   ./hack/skills/install-skills.sh --uninstall  # Remove all installed skills
#   ./hack/skills/install-skills.sh --list       # List available skills

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

SKILLS_DIR="$SCRIPT_DIR"
CURSOR_SKILLS_DIR="$PROJECT_ROOT/.cursor/skills"
CLAUDE_MD="$PROJECT_ROOT/CLAUDE.md"
COPILOT_MD="$PROJECT_ROOT/.github/copilot-instructions.md"

SKILLS_MARKER_START="<!-- SKILLS-AUTO-START -->"
SKILLS_MARKER_END="<!-- SKILLS-AUTO-END -->"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERR]${NC} $1"; }

# Parse YAML frontmatter from a SKILL.md file
parse_skill_metadata() {
    local skill_file="$1"
    local field="$2"
    # Extract value between --- markers
    sed -n '/^---$/,/^---$/p' "$skill_file" | grep "^${field}:" | sed "s/^${field}: *//" | tr -d '"'
}

parse_skill_triggers() {
    local skill_file="$1"
    sed -n '/^triggers:$/,/^[^ -]/p' "$skill_file" | grep "^  - " | sed 's/^  - //' | tr -d '"'
}

# Discover all skills
discover_skills() {
    local skills=()
    for dir in "$SKILLS_DIR"/*/; do
        if [ -f "$dir/SKILL.md" ]; then
            skills+=("$(basename "$dir")")
        fi
    done
    echo "${skills[@]}"
}

# Install for Cursor: symlink SKILL.md files
install_cursor() {
    log_info "Installing skills for Cursor..."
    mkdir -p "$CURSOR_SKILLS_DIR"

    local count=0
    for skill_name in $(discover_skills); do
        local source="$SKILLS_DIR/$skill_name/SKILL.md"
        local target_dir="$CURSOR_SKILLS_DIR/$skill_name"
        local target="$target_dir/SKILL.md"

        mkdir -p "$target_dir"

        # Remove existing (symlink or file)
        [ -L "$target" ] && rm "$target"
        [ -f "$target" ] && rm "$target"

        # Create symlink
        ln -s "$source" "$target"
        log_success "  $skill_name -> .cursor/skills/$skill_name/SKILL.md"
        count=$((count + 1))
    done

    log_success "Installed $count skills for Cursor"
}

# Install for Claude Code: append skill references to CLAUDE.md
install_claude_code() {
    log_info "Installing skills for Claude Code..."

    # Remove existing skills section
    if [ -f "$CLAUDE_MD" ] && grep -q "$SKILLS_MARKER_START" "$CLAUDE_MD"; then
        # Remove between markers (inclusive)
        sed -i "/$SKILLS_MARKER_START/,/$SKILLS_MARKER_END/d" "$CLAUDE_MD"
    fi

    # Generate skills section
    local skills_content=""
    skills_content+="$SKILLS_MARKER_START\n"
    skills_content+="\n## Skills Reference\n\n"
    skills_content+="The following task-specific skills are available in \`hack/skills/\`. "
    skills_content+="Read the full SKILL.md file when a user's request matches the trigger conditions.\n\n"

    for skill_name in $(discover_skills); do
        local skill_file="$SKILLS_DIR/$skill_name/SKILL.md"
        local name=$(parse_skill_metadata "$skill_file" "name")
        local description=$(parse_skill_metadata "$skill_file" "description")

        skills_content+="### $name\n\n"
        skills_content+="- **File:** \`hack/skills/$skill_name/SKILL.md\`\n"
        skills_content+="- **Description:** $description\n"
        skills_content+="- **Triggers:**\n"

        while IFS= read -r trigger; do
            skills_content+="  - $trigger\n"
        done <<< "$(parse_skill_triggers "$skill_file")"

        skills_content+="\n"
    done

    skills_content+="$SKILLS_MARKER_END\n"

    # Append to CLAUDE.md
    if [ -f "$CLAUDE_MD" ]; then
        echo -e "\n$skills_content" >> "$CLAUDE_MD"
    else
        echo -e "$skills_content" > "$CLAUDE_MD"
    fi

    log_success "Updated CLAUDE.md with skill references"
}

# Install for GitHub Copilot: generate .github/copilot-instructions.md
install_copilot() {
    log_info "Installing skills for GitHub Copilot..."
    mkdir -p "$PROJECT_ROOT/.github"

    local content=""

    # If file exists, remove old skills section
    if [ -f "$COPILOT_MD" ] && grep -q "$SKILLS_MARKER_START" "$COPILOT_MD"; then
        sed -i "/$SKILLS_MARKER_START/,/$SKILLS_MARKER_END/d" "$COPILOT_MD"
    fi

    # Generate skills content
    local skills_content=""
    skills_content+="$SKILLS_MARKER_START\n"
    skills_content+="## Task Skills\n\n"
    skills_content+="This repository includes task-specific skills in \`hack/skills/\`. "
    skills_content+="When a user's request matches these patterns, read the full skill file for detailed procedures.\n\n"

    for skill_name in $(discover_skills); do
        local skill_file="$SKILLS_DIR/$skill_name/SKILL.md"
        local name=$(parse_skill_metadata "$skill_file" "name")
        local description=$(parse_skill_metadata "$skill_file" "description")

        skills_content+="### $name (\`hack/skills/$skill_name/SKILL.md\`)\n\n"
        skills_content+="$description\n\n"
        skills_content+="**Trigger patterns:**\n"

        while IFS= read -r trigger; do
            skills_content+="- $trigger\n"
        done <<< "$(parse_skill_triggers "$skill_file")"

        skills_content+="\n"
    done

    skills_content+="$SKILLS_MARKER_END\n"

    # Append or create
    if [ -f "$COPILOT_MD" ]; then
        echo -e "\n$skills_content" >> "$COPILOT_MD"
    else
        # Create with header
        {
            echo "# OpenShift Agent Install - Copilot Instructions"
            echo ""
            echo "This file provides GitHub Copilot with repository-specific context."
            echo "See CLAUDE.md and AGENTS.md for comprehensive project guidance."
            echo ""
            echo -e "$skills_content"
        } > "$COPILOT_MD"
    fi

    log_success "Updated .github/copilot-instructions.md"
}

# Create scripts/ directory with symlinks to hack/ and e2e-tests/ scripts
# Implements the agentskills.io scripts/ convention for callable script bundling
install_scripts() {
    log_info "Creating scripts/ directories with symlinks..."

    # Map: skill_name -> "symlink_name:relative_target ..."
    # Targets are relative from hack/skills/<skill>/scripts/ to repo root scripts
    declare -A SKILL_SCRIPTS
    SKILL_SCRIPTS["bootstrap-environment"]="bootstrap_env.sh:../../../../e2e-tests/bootstrap_env.sh validate_env.sh:../../../../e2e-tests/validate_env.sh setup-dnsmasq.sh:../../../../hack/setup-dnsmasq.sh download-cli.sh:../../../../download-openshift-cli.sh"
    SKILL_SCRIPTS["create-cluster-config"]="validate-kvm-examples.sh:../../../../hack/validate-kvm-examples.sh validate-baremetal-env.sh:../../../../hack/validate-baremetal-env.sh"
    SKILL_SCRIPTS["deploy-cluster-kvm"]="deploy-connected-full.sh:../../../../hack/deploy-connected-full.sh deploy-ha-full.sh:../../../../hack/deploy-ha-full.sh deploy-on-kvm.sh:../../../../hack/deploy-on-kvm.sh create-iso.sh:../../../../hack/create-iso.sh watch-and-reboot-kvm-vms.sh:../../../../hack/watch-and-reboot-kvm-vms.sh verify-dns-resolution.sh:../../../../hack/verify-dns-resolution.sh configure-dnsmasq-entries.sh:../../../../hack/configure-dnsmasq-entries.sh"
    SKILL_SCRIPTS["deploy-cluster-baremetal"]="deploy-iso-baremetal.sh:../../../../hack/deploy-iso-baremetal.sh validate-baremetal-env.sh:../../../../hack/validate-baremetal-env.sh"
    SKILL_SCRIPTS["destroy-cluster"]="destroy-on-kvm.sh:../../../../hack/destroy-on-kvm.sh delete_e2e.sh:../../../../e2e-tests/delete_e2e.sh configure-dnsmasq-entries.sh:../../../../hack/configure-dnsmasq-entries.sh"
    SKILL_SCRIPTS["configure-external-access"]="configure-external-access.sh:../../../../hack/configure-external-access.sh configure-haproxy-forwarder.sh:../../../../hack/configure-haproxy-forwarder.sh configure-route53-dns.sh:../../../../hack/configure-route53-dns.sh configure-letsencrypt-certs.sh:../../../../hack/configure-letsencrypt-certs.sh"
    SKILL_SCRIPTS["deploy-vyos-router"]="vyos-router.sh:../../../../hack/vyos-router.sh"
    SKILL_SCRIPTS["troubleshoot-dns"]="verify-dns-resolution.sh:../../../../hack/verify-dns-resolution.sh configure-dnsmasq-entries.sh:../../../../hack/configure-dnsmasq-entries.sh setup-dnsmasq.sh:../../../../hack/setup-dnsmasq.sh fix-kvm-dns.sh:../../../../hack/fix-kvm-dns.sh"
    SKILL_SCRIPTS["setup-sushy-emulator"]="configure-sushy-unix.sh:../../../../hack/configure-sushy-unix.sh test-libvirt-ssh.sh:../../../../hack/test-libvirt-ssh.sh"
    SKILL_SCRIPTS["validate-and-compare-manifests"]="generate-version-manifests.sh:../../../../hack/generate-version-manifests.sh compare-version-manifests.sh:../../../../hack/compare-version-manifests.sh validate-deployment-standards.sh:../../../../hack/validate-deployment-standards.sh"
    SKILL_SCRIPTS["generate-acm-hosts"]="generate_bmc_acm_hosts.py:../../../../hack/generate_bmc_acm_hosts.py"
    SKILL_SCRIPTS["run-e2e-tests"]="run_e2e.sh:../../../../e2e-tests/run_e2e.sh test_version_validation.sh:../../../../e2e-tests/test_version_validation.sh delete_e2e.sh:../../../../e2e-tests/delete_e2e.sh"
    SKILL_SCRIPTS["pre-release-validation"]="pre-release-validation.sh:../../../../hack/pre-release-validation.sh"

    local ok=0
    local broken=0

    for skill_name in $(discover_skills); do
        local scripts_dir="$SKILLS_DIR/$skill_name/scripts"
        local entries="${SKILL_SCRIPTS[$skill_name]:-}"

        if [ -z "$entries" ]; then
            continue
        fi

        mkdir -p "$scripts_dir"

        for entry in $entries; do
            local link_name="${entry%%:*}"
            local target="${entry##*:}"
            local link_path="$scripts_dir/$link_name"

            # Resolve the target relative to scripts_dir to check if it exists
            local resolved_target
            resolved_target=$(realpath "$scripts_dir/$target" 2>/dev/null || echo "")

            # Remove stale symlink
            [ -L "$link_path" ] && rm "$link_path"

            ln -sf "$target" "$link_path"

            if [ -n "$resolved_target" ] && [ -f "$resolved_target" ]; then
                ok=$((ok + 1))
            else
                log_warn "  Broken symlink: $skill_name/scripts/$link_name -> $target (target not found)"
                broken=$((broken + 1))
            fi
        done
    done

    log_success "Created scripts/ symlinks: $ok OK, $broken broken"
    echo ""
    log_info "Skills can now invoke scripts via relative paths, e.g.:"
    log_info "  hack/skills/bootstrap-environment/scripts/validate_env.sh"
}

# Uninstall all IDE integrations
uninstall() {
    log_info "Uninstalling skills from all IDE targets..."

    # Cursor: remove symlinks
    if [ -d "$CURSOR_SKILLS_DIR" ]; then
        for skill_name in $(discover_skills); do
            local target="$CURSOR_SKILLS_DIR/$skill_name/SKILL.md"
            if [ -L "$target" ]; then
                rm "$target"
                rmdir "$CURSOR_SKILLS_DIR/$skill_name" 2>/dev/null || true
                log_success "  Removed Cursor: $skill_name"
            fi
        done
    fi

    # Claude Code: remove skills section
    if [ -f "$CLAUDE_MD" ] && grep -q "$SKILLS_MARKER_START" "$CLAUDE_MD"; then
        sed -i "/$SKILLS_MARKER_START/,/$SKILLS_MARKER_END/d" "$CLAUDE_MD"
        log_success "  Removed skills section from CLAUDE.md"
    fi

    # Copilot: remove skills section
    if [ -f "$COPILOT_MD" ] && grep -q "$SKILLS_MARKER_START" "$COPILOT_MD"; then
        sed -i "/$SKILLS_MARKER_START/,/$SKILLS_MARKER_END/d" "$COPILOT_MD"
        log_success "  Removed skills section from copilot-instructions.md"
    fi

    log_success "Uninstall complete"
}

# List available skills
list_skills() {
    echo "Available skills in hack/skills/:"
    echo ""
    for skill_name in $(discover_skills); do
        local skill_file="$SKILLS_DIR/$skill_name/SKILL.md"
        local name=$(parse_skill_metadata "$skill_file" "name")
        local description=$(parse_skill_metadata "$skill_file" "description")
        printf "  %-30s %s\n" "$skill_name" "$description"
    done
    echo ""
    echo "Install targets: --cursor, --claude-code, --copilot, --all"
}

# Main
main() {
    local install_cursor_flag=false
    local install_claude_flag=false
    local install_copilot_flag=false
    local install_scripts_flag=false

    if [ $# -eq 0 ]; then
        # Default: install for Cursor
        install_cursor_flag=true
    fi

    while [[ $# -gt 0 ]]; do
        case $1 in
            --cursor)
                install_cursor_flag=true
                shift
                ;;
            --claude-code)
                install_claude_flag=true
                shift
                ;;
            --copilot)
                install_copilot_flag=true
                shift
                ;;
            --scripts)
                install_scripts_flag=true
                shift
                ;;
            --all)
                install_cursor_flag=true
                install_claude_flag=true
                install_copilot_flag=true
                install_scripts_flag=true
                shift
                ;;
            --uninstall)
                uninstall
                exit 0
                ;;
            --list)
                list_skills
                exit 0
                ;;
            --help|-h)
                echo "Usage: $0 [--cursor] [--claude-code] [--copilot] [--scripts] [--all] [--uninstall] [--list]"
                echo ""
                echo "Install AI task skills into IDE-specific locations."
                echo ""
                echo "Options:"
                echo "  --cursor       Install for Cursor IDE (.cursor/skills/)"
                echo "  --claude-code  Install for Claude Code (CLAUDE.md)"
                echo "  --copilot      Install for GitHub Copilot (.github/copilot-instructions.md)"
                echo "  --scripts      Create scripts/ symlinks in each skill (agentskills.io spec)"
                echo "  --all          Install for all IDEs + create scripts/ symlinks"
                echo "  --uninstall    Remove all installed skills"
                echo "  --list         List available skills"
                echo "  --help, -h     Show this help"
                echo ""
                echo "Default (no args): --cursor"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Run '$0 --help' for usage"
                exit 1
                ;;
        esac
    done

    echo ""
    echo "=========================================="
    echo " OpenShift Agent Install - Skills Installer"
    echo "=========================================="
    echo ""

    local skills_count=$(discover_skills | wc -w)
    log_info "Found $skills_count skills in hack/skills/"
    echo ""

    [ "$install_scripts_flag" = true ] && install_scripts
    [ "$install_cursor_flag" = true ] && install_cursor
    [ "$install_claude_flag" = true ] && install_claude_code
    [ "$install_copilot_flag" = true ] && install_copilot

    echo ""
    log_success "Done! Skills are now available in your IDE."
}

main "$@"
