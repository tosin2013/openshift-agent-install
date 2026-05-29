#!/bin/bash
# deploy-iso-baremetal.sh — ISO delivery to physical bare metal servers via Redfish or IPMI
#
# The bare metal counterpart to deploy-on-kvm.sh.
# Reads bmc.address, bmc.username, bmc.password from nodes.yml and automates
# ISO delivery to each node using the specified method.
#
# Usage:
#   ./hack/deploy-iso-baremetal.sh <nodes.yml> --method redfish --iso <path-to-iso>
#   ./hack/deploy-iso-baremetal.sh <nodes.yml> --method ipmi    --iso <path-to-iso>
#   ./hack/deploy-iso-baremetal.sh <nodes.yml> --method check
#
# Methods:
#   redfish  Mount ISO via Redfish virtual media (iDRAC 9+ / iLO 5+) and boot once.
#            Starts a temporary HTTP server on --http-port (default 8080) so the BMC
#            can pull the ISO over the network.
#   ipmi     Set chassis boot device to cdrom and power-cycle via ipmitool.
#            The ISO must already be present as physical or pre-staged virtual media.
#   check    Ping each BMC address and verify Redfish/IPMI reachability only.
#
# Environment variables:
#   SITE_CONFIG_DIR       Where cluster configs live (default: examples)
#   GENERATED_ASSET_PATH  Where ISOs live (default: ~/generated_assets)
#   HTTP_BIND_IP          IP the HTTP server will listen on (default: auto-detected)
#
# Examples:
#   export SITE_CONFIG_DIR=site-config
#   ./hack/deploy-iso-baremetal.sh site-config/my-cluster/nodes.yml \
#       --method redfish \
#       --iso ~/generated_assets/my-cluster/agent.x86_64.iso
#
#   ./hack/deploy-iso-baremetal.sh site-config/my-cluster/nodes.yml \
#       --method ipmi \
#       --iso ~/generated_assets/my-cluster/agent.x86_64.iso
#
#   ./hack/deploy-iso-baremetal.sh site-config/my-cluster/nodes.yml \
#       --method check

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$SCRIPT_DIR/.."

# ── Defaults ──────────────────────────────────────────────────────────────────
SITE_CONFIG_DIR="${SITE_CONFIG_DIR:-examples}"
GENERATED_ASSET_PATH="${GENERATED_ASSET_PATH:-${HOME}/generated_assets}"
HTTP_PORT=8080
METHOD=""
ISO_PATH=""
HTTP_SERVER_PID=""

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓ $*${NC}"; }
fail() { echo -e "${RED}✗ $*${NC}"; }
info() { echo -e "${BLUE}  $*${NC}"; }
warn() { echo -e "${YELLOW}⚠ $*${NC}"; }
section() {
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}$*${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $0 <nodes.yml> --method <redfish|ipmi|check> [options]

Options:
  --method redfish    Mount ISO via Redfish virtual media and boot once
  --method ipmi       Set IPMI boot device to cdrom and power-cycle
  --method check      Test BMC reachability only (no boot)
  --iso <path>        Path to agent.x86_64.iso (required for redfish/ipmi)
  --http-port <port>  HTTP server port for Redfish ISO serving (default: 8080)
  --http-ip <ip>      IP to advertise for HTTP server (default: auto-detect)

Environment:
  SITE_CONFIG_DIR       Config directory (default: examples)
  GENERATED_ASSET_PATH  ISO directory (default: ~/generated_assets)
  HTTP_BIND_IP          HTTP server IP override

Examples:
  $0 site-config/my-cluster/nodes.yml \\
      --method redfish \\
      --iso ~/generated_assets/my-cluster/agent.x86_64.iso

  $0 site-config/my-cluster/nodes.yml --method check
EOF
    exit 1
}

# ── Argument parsing ──────────────────────────────────────────────────────────
if [ $# -lt 1 ]; then
    usage
fi

NODES_FILE="$1"
shift

while [[ $# -gt 0 ]]; do
    case "$1" in
        --method)   METHOD="$2";    shift 2 ;;
        --iso)      ISO_PATH="$2";  shift 2 ;;
        --http-port) HTTP_PORT="$2"; shift 2 ;;
        --http-ip)  HTTP_BIND_IP="$2"; shift 2 ;;
        -h|--help)  usage ;;
        *) echo "Unknown argument: $1"; usage ;;
    esac
done

# ── Validation ────────────────────────────────────────────────────────────────
if [ ! -f "$NODES_FILE" ]; then
    fail "nodes.yml not found: $NODES_FILE"
    exit 1
fi

if [ -z "$METHOD" ]; then
    fail "--method is required (redfish | ipmi | check)"
    usage
fi

if [[ "$METHOD" == "redfish" || "$METHOD" == "ipmi" ]]; then
    if [ -z "$ISO_PATH" ]; then
        fail "--iso is required for method '$METHOD'"
        exit 1
    fi
    if [ ! -f "$ISO_PATH" ]; then
        fail "ISO not found: $ISO_PATH"
        exit 1
    fi
fi

# ── Tool checks ───────────────────────────────────────────────────────────────
check_tools() {
    local missing=0
    case "$METHOD" in
        redfish)
            command -v curl    &>/dev/null || { fail "curl not found — install it first"; missing=1; }
            command -v python3 &>/dev/null || { fail "python3 not found"; missing=1; }
            ;;
        ipmi)
            command -v ipmitool &>/dev/null || { fail "ipmitool not found — sudo dnf install -y ipmitool"; missing=1; }
            ;;
    esac
    [ $missing -eq 0 ]
}

# ── Parse nodes.yml → BMC list ────────────────────────────────────────────────
# Outputs lines: HOSTNAME|ADDRESS|USERNAME|PASSWORD
parse_bmc_nodes() {
    python3 - "$NODES_FILE" <<'PYEOF'
import sys, re

def load_yaml_simple(path):
    """
    Minimal YAML parser for the nodes.yml structure used in this repo.
    Handles the bmc: block under each node. Falls back to key: value parsing.
    """
    try:
        import yaml
        with open(path) as f:
            return yaml.safe_load(f)
    except ImportError:
        pass

    # Fallback: manual parse (handles indented key: value blocks)
    nodes = []
    current_node = None
    in_bmc = False
    current_bmc = {}

    with open(path) as f:
        for raw_line in f:
            line = raw_line.rstrip()
            stripped = line.lstrip()
            indent = len(line) - len(stripped)

            # Skip comments and empty lines
            if not stripped or stripped.startswith('#'):
                continue

            # Detect "- hostname:" which starts a node block
            m = re.match(r'-\s+hostname:\s*(\S+)', stripped)
            if m:
                if current_node and current_bmc:
                    current_node['bmc'] = current_bmc
                if current_node:
                    nodes.append(current_node)
                current_node = {'hostname': m.group(1)}
                in_bmc = False
                current_bmc = {}
                continue

            if current_node is None:
                continue

            # Detect "bmc:" block start
            if stripped == 'bmc:':
                in_bmc = True
                current_bmc = {}
                continue

            # Parse bmc sub-keys
            if in_bmc and indent >= 6:
                m = re.match(r'(\w+):\s*(.*)', stripped)
                if m:
                    key, val = m.group(1), m.group(2).strip('"\'')
                    current_bmc[key] = val
                continue

            # Leaving bmc block
            if in_bmc and indent < 6 and stripped != 'bmc:':
                in_bmc = False

        if current_node and current_bmc:
            current_node['bmc'] = current_bmc
        if current_node:
            nodes.append(current_node)

    return {'nodes': nodes}

data = load_yaml_simple(sys.argv[1])
nodes = data.get('nodes', [])

found = 0
for node in nodes:
    bmc = node.get('bmc')
    if not bmc:
        continue
    hostname = node.get('hostname', 'unknown')
    address  = bmc.get('address', '')
    username = bmc.get('username', '')
    password = bmc.get('password', '')
    if address:
        print(f"{hostname}|{address}|{username}|{password}")
        found += 1

if found == 0:
    import sys
    print("ERROR: No nodes with bmc: blocks found in nodes.yml", file=sys.stderr)
    print("  Uncomment the bmc: sections in your nodes.yml first.", file=sys.stderr)
    sys.exit(1)
PYEOF
}

# ── Extract BMC IP and scheme from an address string ─────────────────────────
# Input: redfish-virtualmedia://10.0.1.10/redfish/v1/Systems/System.Embedded.1
# Output: IP=10.0.1.10, SYSTEM_PATH=/redfish/v1/Systems/System.Embedded.1, VENDOR=dell|hpe|generic
parse_bmc_address() {
    local address="$1"
    BMC_SCHEME=""
    BMC_HOST=""
    BMC_SYSTEM_PATH=""
    BMC_VENDOR="generic"

    if [[ "$address" =~ ^(redfish[^:]*|http[s]?)://([^/]+)(/.*)? ]]; then
        BMC_SCHEME="${BASH_REMATCH[1]}"
        BMC_HOST="${BASH_REMATCH[2]}"
        BMC_SYSTEM_PATH="${BASH_REMATCH[3]}"
    elif [[ "$address" =~ ^ipmi://([^/]+) ]]; then
        BMC_SCHEME="ipmi"
        BMC_HOST="${BASH_REMATCH[1]}"
    else
        # Plain IP address — assume IPMI
        BMC_SCHEME="ipmi"
        BMC_HOST="$address"
    fi

    # Detect vendor from system path
    if [[ "$BMC_SYSTEM_PATH" == *"System.Embedded"* ]]; then
        BMC_VENDOR="dell"
    elif [[ "$BMC_SYSTEM_PATH" == *"/Systems/1"* ]]; then
        BMC_VENDOR="hpe"
    fi
}

# ── Auto-detect outbound IP toward BMC host ───────────────────────────────────
detect_host_ip() {
    local target_ip="$1"
    if [ -n "$HTTP_BIND_IP" ]; then
        echo "$HTTP_BIND_IP"
        return
    fi
    # Use the source IP that would route to target BMC
    python3 -c "
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.connect(('$target_ip', 80))
print(s.getsockname()[0])
s.close()
" 2>/dev/null || hostname -I | awk '{print $1}'
}

# ── HTTP server lifecycle ─────────────────────────────────────────────────────
start_http_server() {
    local iso_dir
    iso_dir=$(dirname "$ISO_PATH")

    section "Starting HTTP server to serve ISO"
    info "ISO directory : $iso_dir"
    info "HTTP port     : $HTTP_PORT"

    python3 -m http.server "$HTTP_PORT" --directory "$iso_dir" &>/tmp/deploy-iso-http.log &
    HTTP_SERVER_PID=$!
    sleep 2

    if ! kill -0 "$HTTP_SERVER_PID" 2>/dev/null; then
        fail "HTTP server failed to start — check port $HTTP_PORT is free"
        cat /tmp/deploy-iso-http.log
        exit 1
    fi
    pass "HTTP server started (pid $HTTP_SERVER_PID)"
}

stop_http_server() {
    if [ -n "$HTTP_SERVER_PID" ] && kill -0 "$HTTP_SERVER_PID" 2>/dev/null; then
        kill "$HTTP_SERVER_PID" 2>/dev/null || true
        info "HTTP server stopped"
    fi
}
trap stop_http_server EXIT

# ── Redfish actions ───────────────────────────────────────────────────────────
redfish_deploy_node() {
    local hostname="$1"
    local bmc_host="$2"
    local username="$3"
    local password="$4"
    local system_path="$5"
    local vendor="$6"
    local iso_url="$7"

    local AUTH="${username}:${password}"
    local CURL_OPTS=(-sk -u "$AUTH" -H "Content-Type: application/json")

    info "BMC host   : $bmc_host"
    info "ISO URL    : $iso_url"
    info "Vendor     : $vendor"

    # Build endpoint paths based on vendor
    local vm_insert_url="" boot_url="" reset_url=""
    case "$vendor" in
        dell)
            vm_insert_url="https://${bmc_host}/redfish/v1/Managers/iDRAC.Embedded.1/VirtualMedia/CD/Actions/VirtualMedia.InsertMedia"
            boot_url="https://${bmc_host}/redfish/v1/Systems/System.Embedded.1"
            reset_url="https://${bmc_host}/redfish/v1/Systems/System.Embedded.1/Actions/ComputerSystem.Reset"
            ;;
        hpe)
            vm_insert_url="https://${bmc_host}/redfish/v1/Managers/1/VirtualMedia/2/Actions/VirtualMedia.InsertMedia"
            boot_url="https://${bmc_host}/redfish/v1/Systems/1"
            reset_url="https://${bmc_host}/redfish/v1/Systems/1/Actions/ComputerSystem.Reset"
            ;;
        *)
            # Generic: discover system path from root
            if [ -n "$system_path" ]; then
                local sys="${bmc_host}${system_path}"
                vm_insert_url="https://${bmc_host}/redfish/v1/Managers/1/VirtualMedia/CD/Actions/VirtualMedia.InsertMedia"
                boot_url="https://$sys"
                reset_url="https://${sys}/Actions/ComputerSystem.Reset"
            else
                fail "Cannot determine Redfish paths for $hostname (unknown vendor). Set bmc.address with a full redfish-virtualmedia:// path."
                return 1
            fi
            ;;
    esac

    # Step 1: Mount virtual media
    info "Step 1/3: Mounting ISO via virtual media..."
    local mount_resp
    mount_resp=$(curl "${CURL_OPTS[@]}" -o /tmp/vm_mount_resp.json -w "%{http_code}" -X POST \
        "$vm_insert_url" \
        -d "{\"Image\": \"${iso_url}\", \"Inserted\": true, \"WriteProtected\": true}" 2>/dev/null)

    if [[ "$mount_resp" =~ ^2 ]]; then
        pass "Virtual media mounted"
    else
        warn "Virtual media mount returned HTTP $mount_resp — continuing (may already be mounted)"
        cat /tmp/vm_mount_resp.json 2>/dev/null | python3 -m json.tool 2>/dev/null || true
    fi

    # Step 2: Set one-time boot to CD
    info "Step 2/3: Setting one-time boot to virtual CD..."
    local boot_resp
    boot_resp=$(curl "${CURL_OPTS[@]}" -o /dev/null -w "%{http_code}" -X PATCH \
        "$boot_url" \
        -d '{"Boot": {"BootSourceOverrideTarget": "Cd", "BootSourceOverrideEnabled": "Once"}}' 2>/dev/null)

    if [[ "$boot_resp" =~ ^2 ]]; then
        pass "Boot override set to CD (once)"
    else
        fail "Failed to set boot override on $hostname (HTTP $boot_resp)"
        return 1
    fi

    # Step 3: Power reset
    info "Step 3/3: Power cycling server..."
    local reset_resp
    reset_resp=$(curl "${CURL_OPTS[@]}" -o /dev/null -w "%{http_code}" -X POST \
        "$reset_url" \
        -d '{"ResetType": "ForceRestart"}' 2>/dev/null)

    if [[ "$reset_resp" =~ ^2 ]]; then
        pass "Power reset issued — $hostname is booting"
    else
        # Try GracefulRestart as fallback
        reset_resp=$(curl "${CURL_OPTS[@]}" -o /dev/null -w "%{http_code}" -X POST \
            "$reset_url" \
            -d '{"ResetType": "GracefulRestart"}' 2>/dev/null)
        if [[ "$reset_resp" =~ ^2 ]]; then
            pass "Graceful restart issued — $hostname is booting"
        else
            fail "Power reset failed on $hostname (HTTP $reset_resp)"
            return 1
        fi
    fi
}

# ── IPMI actions ──────────────────────────────────────────────────────────────
ipmi_deploy_node() {
    local hostname="$1"
    local bmc_host="$2"
    local username="$3"
    local password="$4"

    local IPMI_OPTS=(-I lanplus -H "$bmc_host" -U "$username" -P "$password")

    info "BMC host  : $bmc_host"

    # Set boot device to cdrom (UEFI)
    info "Step 1/2: Setting boot device to cdrom (EFI)..."
    if ipmitool "${IPMI_OPTS[@]}" chassis bootdev cdrom options=efiboot &>/dev/null; then
        pass "Boot device set to cdrom"
    else
        # Fallback: try without efiboot option
        if ipmitool "${IPMI_OPTS[@]}" chassis bootdev cdrom &>/dev/null; then
            pass "Boot device set to cdrom (legacy mode)"
            warn "Server may boot in BIOS mode — ensure UEFI is configured in BIOS"
        else
            fail "Failed to set boot device on $hostname"
            return 1
        fi
    fi

    # Power cycle
    info "Step 2/2: Power cycling server..."
    if ipmitool "${IPMI_OPTS[@]}" chassis power reset &>/dev/null; then
        pass "Power reset issued — $hostname is booting"
    elif ipmitool "${IPMI_OPTS[@]}" chassis power on &>/dev/null; then
        pass "Power on issued — $hostname is booting"
    else
        fail "Power command failed on $hostname"
        return 1
    fi
}

# ── Check action ──────────────────────────────────────────────────────────────
check_node() {
    local hostname="$1"
    local bmc_host="$2"
    local username="$3"
    local scheme="$4"

    # Ping
    if ping -c 1 -W 3 "$bmc_host" &>/dev/null; then
        pass "Ping: $bmc_host reachable"
    else
        fail "Ping: $bmc_host unreachable"
        return 1
    fi

    # Scheme-specific check
    case "$scheme" in
        redfish*|https|http)
            local http_code
            http_code=$(curl -sk -o /dev/null -w "%{http_code}" \
                "https://${bmc_host}/redfish/v1" 2>/dev/null || echo "000")
            if [[ "$http_code" =~ ^2 ]]; then
                pass "Redfish API reachable (HTTP $http_code)"
            else
                warn "Redfish API returned HTTP $http_code (may need credentials or cert trust)"
            fi
            ;;
        ipmi)
            if ipmitool -I lanplus -H "$bmc_host" -U "$username" -P "PLACEHOLDER" \
                    chassis status &>/dev/null 2>&1 | grep -q "System Power"; then
                pass "IPMI reachable (LAN+ interface)"
            else
                warn "IPMI LAN check inconclusive (may still be functional)"
            fi
            ;;
    esac
}

# ── Main ──────────────────────────────────────────────────────────────────────
section "deploy-iso-baremetal.sh — method: $METHOD"
info "Nodes file : $NODES_FILE"
[ -n "$ISO_PATH" ] && info "ISO        : $ISO_PATH"

check_tools || exit 1

# Parse BMC nodes
BMC_LINES=$(parse_bmc_nodes) || { fail "Failed to parse BMC nodes from $NODES_FILE"; exit 1; }
NODE_COUNT=$(echo "$BMC_LINES" | wc -l)
info "Found $NODE_COUNT node(s) with BMC configuration"

# For Redfish, start HTTP server once before iterating nodes
ISO_URL=""
if [ "$METHOD" = "redfish" ]; then
    start_http_server
fi

ERRORS=0
while IFS='|' read -r hostname address username password; do
    section "Node: $hostname"
    parse_bmc_address "$address"

    case "$METHOD" in
        redfish)
            HOST_IP=$(detect_host_ip "$BMC_HOST")
            ISO_FILENAME=$(basename "$ISO_PATH")
            ISO_URL="http://${HOST_IP}:${HTTP_PORT}/${ISO_FILENAME}"
            info "Serving ISO at: $ISO_URL"
            redfish_deploy_node "$hostname" "$BMC_HOST" "$username" "$password" \
                "$BMC_SYSTEM_PATH" "$BMC_VENDOR" "$ISO_URL" || { ERRORS=$((ERRORS+1)); }
            ;;
        ipmi)
            ipmi_deploy_node "$hostname" "$BMC_HOST" "$username" "$password" \
                || { ERRORS=$((ERRORS+1)); }
            ;;
        check)
            check_node "$hostname" "$BMC_HOST" "$username" "$BMC_SCHEME" \
                || { ERRORS=$((ERRORS+1)); }
            ;;
    esac
done <<< "$BMC_LINES"

# ── Summary ───────────────────────────────────────────────────────────────────
section "Summary"
TOTAL=$NODE_COUNT
OK=$((TOTAL - ERRORS))
echo ""
info "Nodes attempted : $TOTAL"
pass "Nodes succeeded : $OK"
[ $ERRORS -gt 0 ] && fail "Nodes failed    : $ERRORS"

if [ "$METHOD" != "check" ] && [ $ERRORS -eq 0 ]; then
    echo ""
    info "All nodes are booting from the agent ISO."
    info "Monitor installation progress with:"
    info ""
    echo "    ./bin/openshift-install agent wait-for bootstrap-complete \\"
    echo "        --dir ${GENERATED_ASSET_PATH}/<cluster-name>/ --log-level=info"
    echo ""
    echo "    ./bin/openshift-install agent wait-for install-complete \\"
    echo "        --dir ${GENERATED_ASSET_PATH}/<cluster-name>/ --log-level=info"
fi

[ $ERRORS -gt 0 ] && exit 1
exit 0
